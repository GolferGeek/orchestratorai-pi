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
    @Published var evaluations: [EvaluationRecord] = []
    @Published var stepOutputs: [RunStore.StepOutput] = []
    @Published var liveText: [RunStore.LiveText] = []
    @Published var evaluationCounts: [String: (block: Int, review: Int, pass: Int)] = [:]
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
    // Store change notification: SQLite in WAL mode appends to <db>-wal on every
    // commit, so watching that file (and the db, for checkpoints) with a
    // dispatch source wakes us on writes instead of polling. A slow fallback
    // timer covers the rare case where the -wal file is recreated.
    private var storeWatchers: [DispatchSourceFileSystemObject] = []
    private var fallbackTimer: Timer?
    private var refreshCoalescer: DispatchWorkItem?

    var selectedRun: RunRecord? {
        runs.first { $0.id == selectedRunId }
    }

    func checkpoints(for runId: String) -> [CheckpointRecord] {
        checkpointsByRun[runId] ?? []
    }

    func reviewState(for run: RunRecord) -> ReviewState {
        store?.reviewState(for: run, checkpoints: checkpoints(for: run.id)) ?? .queued
    }

    /// The most severe Jev decision recorded for a run: block > review > pass; nil when no rubric ran.
    func worstDecision(for runId: String) -> String? {
        guard let counts = evaluationCounts[runId] else { return nil }
        if counts.block > 0 { return "block" }
        if counts.review > 0 { return "review" }
        if counts.pass > 0 { return "pass" }
        return nil
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
        markOrphanedRuns()
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
        evaluationCounts = store.evaluationSummary()
        if let selectedRunId {
            events = store.events(runId: selectedRunId)
            stepOutputs = store.stepOutputs(runId: selectedRunId)
            liveText = store.liveText(runId: selectedRunId)
            evaluations = store.evaluations(runId: selectedRunId)
        } else {
            events = []
            stepOutputs = []
            liveText = []
            evaluations = []
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
        stopWatching()
        guard let store else { return }
        for path in [store.path, store.path + "-wal"] {
            // The -wal file may not exist until the first write; the fallback timer re-arms us.
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let flags = source.data
                self.scheduleRefresh()
                if flags.contains(.delete) || flags.contains(.rename) {
                    // The file was replaced (e.g. WAL checkpoint/truncate); re-open our watchers.
                    self.schedulePolling()
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            storeWatchers.append(source)
        }
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                // Re-arm if the -wal appeared after we started (first write of a fresh store).
                if self.storeWatchers.count < 2, let store = self.store, FileManager.default.fileExists(atPath: store.path + "-wal") {
                    self.schedulePolling()
                }
            }
        }
    }

    /// Coalesce bursts of writes (a run emits many events in quick succession) into one refresh.
    private func scheduleRefresh() {
        refreshCoalescer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshCoalescer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func stopWatching() {
        for source in storeWatchers { source.cancel() }
        storeWatchers.removeAll()
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    func select(runId: String?) {
        selectedRunId = runId
        refresh()
    }

    // MARK: Launch

    func start(workflow: WorkflowDefinition, params: [String: String], sourceDocument: String, model: String) {
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
        launchPi(command: "start", request: request, runId: runId, model: model)
    }

    /// Crash-resume: the extension rebuilds the remainder of the stored flow from the
    /// completed steps' values (and any attorney overrides) and starts it under the same run id.
    func resume(run: RunRecord) {
        launchPi(command: "resume", request: ["runId": run.id], runId: run.id, model: run.model ?? "qwen3.6:latest")
    }

    /// One Pi RPC process per launch; `/orchestrator <command> {json}` is the only thing sent.
    private func launchPi(command: String, request: [String: Any], runId: String, model: String) {
        guard let projectDirectory else { return }
        guard let piPath = PiEnvironment.findPiExecutable() else {
            errorMessage = "Could not find the `pi` executable. Install it with `npm i -g @earendil-works/pi-coding-agent` or set PI_PATH."
            return
        }
        stop()
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
        process.environment = PiEnvironment.processEnvironment(piExecutable: piPath, projectDirectory: projectDirectory)
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
            send(["type": "prompt", "message": "/orchestrator \(command) \(jsonText)"])
            status = command == "resume" ? "Resuming workflow…" : "Launching workflow…"
        } catch {
            isRunning = false
            activeRunId = nil
            status = "Unavailable"
            errorMessage = "Could not start Pi: \(error.localizedDescription)"
        }
        refresh()
    }

    /// A run left "running" with no live Pi behind it (the app quit, a script ended) can only be
    /// resumed, never finished on its own. Called on attach; uses a staleness heuristic because
    /// runs launched by scripts are not this process's children.
    func markOrphanedRuns() {
        guard let store else { return }
        let cutoff = Date().addingTimeInterval(-180)
        for run in store.runs() where run.isLive && run.id != activeRunId {
            let lastActivity = store.events(runId: run.id).last.flatMap { Self.parseISO($0.at) } ?? Self.parseISO(run.updatedAt)
            if let lastActivity, lastActivity < cutoff {
                store.markOrphaned(runId: run.id, message: "No live Pi process behind this run (found at launch). Resume to finish it.")
            }
        }
    }

    private static func parseISO(_ value: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
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

    func overrideStep(runId: String, stepIndex: Int, text: String, note: String?) {
        store?.setStepOverride(runId: runId, stepIndex: stepIndex, text: text, note: note)
        refresh()
    }

    func clearOverride(runId: String, stepIndex: Int) {
        store?.clearStepOverride(runId: runId, stepIndex: stepIndex)
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
                status = reply["op"] as? String == "resume" ? "Workflow resumed" : "Workflow running"
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
