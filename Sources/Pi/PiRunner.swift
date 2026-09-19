import Foundation

/// Drives one Pi RPC process per launched run and mirrors the on-device run
/// store into published state. The store — not the RPC stream — is the source
/// of truth: the extension journals everything there, and this class only
/// listens to RPC for the deterministic `/orchestrator` reply and hard errors.
@MainActor
final class PiRunner: ObservableObject {
    @Published var runs: [RunRecord] = []
    @Published var checkpointsByRun: [String: [CheckpointRecord]] = [:]
    @Published var selectedRunId: String?
    @Published var events: [RunEventRecord] = []
    @Published var status = "Ready"
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var storeUnavailable = false

    private(set) var store: RunStore?
    private var projectDirectory: URL?
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private let lineBuffer = LineBuffer()
    private var activeRunId: String?
    private var pollTimer: Timer?

    var selectedRun: RunRecord? {
        runs.first { $0.id == selectedRunId }
    }

    func checkpoints(for runId: String) -> [CheckpointRecord] {
        checkpointsByRun[runId] ?? []
    }

    func reviewState(for run: RunRecord) -> ReviewState {
        store?.reviewState(for: run, checkpoints: checkpoints(for: run.id)) ?? .queued
    }

    var attentionRuns: [RunRecord] {
        runs.filter { reviewState(for: $0).needsAttention || reviewState(for: $0).isLive }
    }

    var completedRuns: [RunRecord] {
        runs.filter { reviewState(for: $0) == .approved }
    }

    // MARK: Store

    func attach(projectDirectory: URL) {
        self.projectDirectory = projectDirectory
        store = RunStore(projectDirectory: projectDirectory)
        storeUnavailable = store == nil
        refresh()
        if selectedRunId == nil { selectedRunId = runs.first?.id }
        schedulePolling()
    }

    func refresh() {
        guard let store else { return }
        runs = store.runs()
        var map: [String: [CheckpointRecord]] = [:]
        for run in runs { map[run.id] = store.checkpoints(runId: run.id) }
        checkpointsByRun = map
        if let selectedRunId {
            events = store.events(runId: selectedRunId)
        } else {
            events = []
        }
        if let activeRunId, let run = runs.first(where: { $0.id == activeRunId }) {
            let state = reviewState(for: run)
            status = state.label
            if !state.isLive {
                finishActiveProcess()
            }
        }
    }

    private func schedulePolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func select(runId: String?) {
        selectedRunId = runId
        refresh()
    }

    // MARK: Launch

    func start(workflow: WorkflowDefinition, params: [String: String], sourceDocument: String, model: String) {
        guard let projectDirectory else { return }
        guard let piPath = PiEnvironment.findPiExecutable() else {
            errorMessage = "Could not find the `pi` executable. Install it with `npm i -g @earendil-works/pi-coding-agent` or set PI_PATH."
            return
        }
        stop()

        let runId = UUID().uuidString.lowercased()
        let documentTitle = sourceDocument.hasPrefix("/")
            ? URL(fileURLWithPath: sourceDocument).deletingPathExtension().lastPathComponent
            : sourceDocument
        let request: [String: Any] = [
            "runId": runId,
            "workflow": workflow.id,
            "title": "\(workflow.title) — \(documentTitle)",
            "sourceDocument": sourceDocument,
            "params": params,
            "model": model
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: request),
              let jsonText = String(data: json, encoding: .utf8) else {
            errorMessage = "Could not encode the launch request."
            return
        }

        activeRunId = runId
        selectedRunId = runId
        isRunning = true
        status = "Starting Pi…"

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: piPath)
        process.arguments = [
            "--mode", "rpc",
            "--approve",
            "--no-session",
            "--provider", "ollama",
            "--model", model
        ]
        process.currentDirectoryURL = projectDirectory
        process.environment = PiEnvironment.processEnvironment(piExecutable: piPath)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.isRunning = false
                if let activeRunId = self.activeRunId, let run = self.store?.run(id: activeRunId), run.isLive {
                    let reason = process.terminationStatus == 0
                        ? "Pi exited before the workflow finished."
                        : "Pi stopped (exit \(process.terminationStatus)). Check that Ollama is running and the model is available."
                    self.store?.markOrphaned(runId: activeRunId, message: reason)
                    self.errorMessage = reason
                }
                self.activeRunId = nil
                self.refresh()
            }
        }

        do {
            try process.run()
            self.process = process
            inputPipe = input
            outputPipe = output
            send(["type": "prompt", "message": "/orchestrator start \(jsonText)"])
            status = "Launching workflow…"
        } catch {
            isRunning = false
            activeRunId = nil
            status = "Unavailable"
            errorMessage = "Could not start Pi: \(error.localizedDescription)"
        }
        refresh()
    }

    func stop() {
        if let activeRunId, process?.isRunning == true {
            send(["type": "prompt", "message": "/orchestrator stop {\"runId\":\"\(activeRunId)\"}"])
            store?.markOrphaned(runId: activeRunId, message: "Stopped by the user.")
        }
        finishActiveProcess()
        activeRunId = nil
        isRunning = false
        refresh()
    }

    private func finishActiveProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning {
            terminateDirectChildren(of: process.processIdentifier)
            process.terminate()
        }
        process = nil
        inputPipe = nil
        outputPipe = nil
        isRunning = false
    }

    private func terminateDirectChildren(of pid: Int32) {
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-TERM", "-P", String(pid)]
        try? killer.run()
        killer.waitUntilExit()
    }

    // MARK: Attorney decisions

    func decide(checkpoint: CheckpointRecord, approved: Bool, comment: String) {
        let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = approved ? "approved" : "changes_requested"
        let prefix = approved ? "Approved by attorney." : "Changes requested by attorney."
        store?.decide(checkpointId: checkpoint.id, status: status, comment: note.isEmpty ? prefix : "\(prefix) \(note)")
        refresh()
    }

    func reopenReview(runId: String) {
        store?.reopenFinalReview(runId: runId)
        refresh()
    }

    func deleteRun(_ run: RunRecord) {
        if run.id == activeRunId { stop() }
        store?.deleteRun(id: run.id)
        if selectedRunId == run.id { selectedRunId = nil }
        refresh()
    }

    // MARK: RPC plumbing

    private func send(_ command: [String: Any]) {
        guard let inputPipe, JSONSerialization.isValidJSONObject(command) else { return }
        do {
            var data = try JSONSerialization.data(withJSONObject: command)
            data.append(0x0A)
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            errorMessage = "Could not send the request to Pi: \(error.localizedDescription)"
        }
    }

    private nonisolated func consume(_ data: Data) {
        let lines = lineBuffer.append(data)
        for line in lines {
            Task { @MainActor in self.handle(line: line) }
        }
    }

    private func handle(line: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = event["type"] as? String else { return }
        switch type {
        case "message_start":
            guard let message = event["message"] as? [String: Any],
                  message["customType"] as? String == "orchestrator:reply",
                  let content = message["content"] as? String,
                  let reply = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any] else { return }
            if reply["ok"] as? Bool == true {
                status = "Workflow running"
                if let warnings = reply["warnings"] as? [String], !warnings.isEmpty {
                    errorMessage = "Pi warnings: " + warnings.joined(separator: " · ")
                }
            } else {
                let message = reply["error"] as? String ?? "The workflow could not be started."
                errorMessage = message
                status = "Failed"
                finishActiveProcess()
                activeRunId = nil
            }
            refresh()
        case "extension_error":
            let detail = (event["error"] as? String) ?? (event["message"] as? String)
            errorMessage = detail.map { "Pi extension error: \($0)" } ?? "Pi extension error."
        case "extension_ui_request":
            if event["method"] as? String == "notify",
               event["notifyType"] as? String == "error",
               let message = event["message"] as? String {
                errorMessage = message
            }
        default:
            break
        }
    }

    private final class LineBuffer: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()

        func append(_ incoming: Data) -> [Data] {
            lock.lock()
            defer { lock.unlock() }
            data.append(incoming)
            var lines: [Data] = []
            while let newline = data.firstIndex(of: 0x0A) {
                lines.append(Data(data[..<newline]))
                data.removeSubrange(...newline)
            }
            return lines
        }
    }
}
