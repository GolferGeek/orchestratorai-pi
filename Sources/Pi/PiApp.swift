import AppKit
import Foundation
import SwiftUI
import Textual
import UniformTypeIdentifiers

struct PiRunRecord: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let workflow: String
    let sourceDocument: String
    let startedAt: String
    let completedAt: String?
    let status: String
    let relativeDirectory: String
}

struct AttorneyReviewItem: Identifiable, Hashable {
    let id: String
    let text: String
}

struct WorkflowDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let description: String
    let fileLabel: String
}

@main
struct PiApp: App {
    var body: some Scene {
        WindowGroup("OrchestratorAI - Pi") {
            ContentView()
                .frame(minWidth: 760, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @StateObject private var runner = PiRunner()
    @State private var selectedFile: URL?
    @State private var showingImporter = false
    @State private var reviewerSide = "Receiving party"
    @State private var reviewContext = "Issue spotting and negotiation preparation. Identify assumptions and questions for attorney review."
    @State private var model = "qwen3.6:latest"
    @State private var selectedWorkflow = "contract-review"
    @State private var showingActivity = false
    @State private var reviewedIssueIDs: Set<String> = []
    @State private var runPendingDeletion: PiRunRecord?
    @State private var showingDeleteConfirmation = false
    @State private var legalWorkflowsExpanded = true
    @State private var documentProcessingExpanded = true

    private let sides = ["Receiving party", "Disclosing party", "Both parties", "Not specified"]
    private let workflows = [
        WorkflowDefinition(id: "contract-review", title: "Review a contract", icon: "checklist", description: "Red/Blue issue spotting, arbitration, and attorney review.", fileLabel: "contract"),
        WorkflowDefinition(id: "document-onboarding", title: "Onboard a document", icon: "doc.badge.plus", description: "Classify, inventory, check completeness, and find initial issues.", fileLabel: "document")
    ]

    private var activeWorkflow: WorkflowDefinition {
        workflows.first(where: { $0.id == selectedWorkflow }) ?? workflows[0]
    }

    var body: some View {
        NavigationSplitView {
            workflowSidebar
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        taskCard
                        contextCard
                        sourceDocumentCard
                        attorneyReviewCard
                        resultCard
                        humanReviewCard
                    }
                    .padding(28)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            runner.loadRuns(projectDirectory: Self.findProjectDirectory())
            selectedWorkflow = runner.currentWorkflow
        }
        .onChange(of: selectedWorkflow) { _, _ in
            if selectedWorkflow != runner.currentWorkflow {
                selectedFile = nil
                runner.clearDisplayedRun()
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.item, .data, .text, .pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                selectedFile = urls.first
            }
        }
        .alert("OrchestratorAI - Pi", isPresented: Binding(
            get: { runner.errorMessage != nil },
            set: { if !$0 { runner.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { runner.errorMessage = nil }
        } message: {
            Text(runner.errorMessage ?? "Unknown error")
        }
        .alert("Delete this review?", isPresented: $showingDeleteConfirmation) {
            Button("Delete Review", role: .destructive) {
                if let run = runPendingDeletion {
                    runner.deleteRun(run, projectDirectory: Self.findProjectDirectory())
                }
                runPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the complete dated run directory, including its report, thinking notes, trace, request, manifest, and checkpoints.\n\n\(runPendingDeletion?.title ?? "This review")")
        }
    }

    private var workflowSidebar: some View {
        List(selection: $selectedWorkflow) {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        legalWorkflowsExpanded.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: legalWorkflowsExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.bold))
                            Label("Legal workflows", systemImage: "doc.text.magnifyingglass")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(.plain)

                    if legalWorkflowsExpanded {
                        Button {
                            documentProcessingExpanded.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: documentProcessingExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.bold))
                                Text("Document processing")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.leading, 18)
                        }
                        .buttonStyle(.plain)

                        if documentProcessingExpanded {
                            ForEach(workflows) { workflow in
                                Button {
                                    selectedWorkflow = workflow.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label(workflow.title, systemImage: workflow.icon)
                                        Text(workflow.description)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.leading, 24)
                                    }
                                    .padding(.leading, 36)
                                }
                                .buttonStyle(.plain)
                                .tag(workflow.id)
                            }
                        }
                    }

                    Text("Reviews")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    if runner.attentionReviewRuns.isEmpty {
                        Text("No reviews awaiting action")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(runner.attentionReviewRuns) { run in
                            HStack(spacing: 6) {
                                Button {
                                    openRun(run)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(run.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Text("\(run.status.replacingOccurrences(of: "_", with: " ")) · \(Self.displayDate(run.completedAt ?? run.startedAt))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer(minLength: 0)
                                deleteButton(for: run)
                            }
                        }
                    }

                    Text("Completed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    if runner.completedReviewRuns.isEmpty {
                        Text("No completed reviews")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(runner.completedReviewRuns) { run in
                            HStack(spacing: 6) {
                                Button {
                                    openRun(run)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(run.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Text("\(run.status.replacingOccurrences(of: "_", with: " ")) · \(Self.displayDate(run.completedAt ?? run.startedAt))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer(minLength: 0)
                                deleteButton(for: run)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Workflows")
        .frame(minWidth: 230)
    }

    private func deleteButton(for run: PiRunRecord) -> some View {
        Button {
            runPendingDeletion = run
            showingDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Delete this review and all of its run files")
    }

    private func openRun(_ run: PiRunRecord) {
        selectedWorkflow = run.workflow
        runner.loadRun(run, projectDirectory: Self.findProjectDirectory())
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("OrchestratorAI - Pi")
                    .font(.title2.weight(.semibold))
                Text(activeWorkflow.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(runner.isRunning ? .orange : .green)
                .frame(width: 9, height: 9)
            Text(runner.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !runner.runTitle.isEmpty {
                Text("· \(runner.runTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(.regularMaterial)
    }

    private var taskCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeWorkflow.title)
                            .font(.title3.weight(.semibold))
                        Text(activeWorkflow.description)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: activeWorkflow.icon)
                        .font(.largeTitle)
                        .foregroundStyle(.blue.opacity(0.75))
                }

                Button {
                    showingImporter = true
                } label: {
                    Label(
                        selectedFile == nil ? "Choose a \(activeWorkflow.fileLabel)" : "Choose a different \(activeWorkflow.fileLabel)",
                        systemImage: "folder"
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                if let selectedFile {
                    Label(selectedFile.path, systemImage: "doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Button {
                        startReview()
                    } label: {
                        Label(runner.isRunning ? "Working…" : "Start local workflow", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedFile == nil || runner.isRunning)

                    if runner.isRunning {
                        Button("Stop", role: .destructive) {
                            runner.stop()
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var contextCard: some View {
        GroupBox(activeWorkflow.id == "contract-review" ? "Review context" : "Onboarding context") {
            VStack(alignment: .leading, spacing: 12) {
                if activeWorkflow.id == "contract-review" {
                    HStack {
                    Text("Our side")
                        .frame(width: 90, alignment: .leading)
                    Picker("Our side", selection: $reviewerSide) {
                        ForEach(sides, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    }
                }

                HStack(alignment: .top) {
                    Text(activeWorkflow.id == "contract-review" ? "Objective" : "Intake goal")
                        .frame(width: 90, alignment: .leading)
                    TextEditor(text: $reviewContext)
                        .font(.body)
                        .frame(minHeight: 68)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }

                HStack {
                    Text("Local model")
                        .frame(width: 90, alignment: .leading)
                    TextField("Ollama model", text: $model)
                        .textFieldStyle(.roundedBorder)
                    Text("Ollama")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var resultCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Final report")
                        .font(.headline)
                    Spacer()
                    Button {
                        saveReport()
                    } label: {
                        Label("Save Markdown", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(runner.markdownReport.isEmpty || runner.isRunning)
                }

                if runner.markdownReport.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No review yet")
                            .font(.headline)
                        Text("Choose a \(activeWorkflow.fileLabel) and start the local workflow.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ScrollView {
                        reportContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(minHeight: 260, maxHeight: 430)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    activitySection
                }
            }
            .padding(8)
        }
    }

    private var attorneyReviewCard: some View {
        let items = runner.attorneyReviewItems
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Attorney review focus", systemImage: "exclamationmark.bubble")
                        .font(.headline)
                    Spacer()
                    if !items.isEmpty {
                        Text("\(reviewedIssueIDs.intersection(Set(items.map(\.id))).count)/\(items.count) reviewed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if items.isEmpty {
                    Text("The completed report will identify standout issues and questions here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            Button {
                                if reviewedIssueIDs.contains(item.id) {
                                    reviewedIssueIDs.remove(item.id)
                                } else {
                                    reviewedIssueIDs.insert(item.id)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: reviewedIssueIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(reviewedIssueIDs.contains(item.id) ? .green : .orange)
                                    Text(item.text)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var humanReviewCard: some View {
        guard runner.currentStatus == "awaiting_human_review" || runner.currentStatus == "revision_requested" else {
            return AnyView(EmptyView())
        }
        return AnyView(
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Attorney review required", systemImage: "person.badge.key")
                        .font(.headline)
                    Text("Review the report above and record a decision before this run is marked complete.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Approve review") {
                            runner.approveCurrentRun()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Request changes") {
                            runner.requestChangesForCurrentRun()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(8)
            }
        )
    }

    private var sourceDocumentCard: some View {
        GroupBox {
            DisclosureGroup {
                if let selectedFile,
                   let source = try? String(contentsOf: selectedFile, encoding: .utf8) {
                    ScrollView {
                        Text(source)
                            .font(.system(.body, design: .serif))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(minHeight: 120, maxHeight: 300)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Choose a readable text or Markdown contract to preview it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } label: {
            Label(
                selectedFile == nil ? "Source document" : "Source document — \(selectedFile?.deletingPathExtension().lastPathComponent ?? "")",
                systemImage: "doc.plaintext"
            )
                    .font(.headline)
            }
            .padding(8)
        }
    }

    private func startReview() {
        guard let selectedFile else { return }
        let projectDirectory = Self.findProjectDirectory()
        let documentTitle = selectedFile.deletingPathExtension().lastPathComponent
        let runTitle = "\(activeWorkflow.title) — \(documentTitle)"
        let prompt: String
        if activeWorkflow.id == "contract-review" {
            prompt = """
            Run the saved contract-review workflow.

            Target document: \(selectedFile.path)
            Reviewer side: \(reviewerSide)
            Review context: \(reviewContext)

            Execute the complete text-first composed workflow: independent Red and Blue contract reviews, arbitration of their natural-language findings, and summary generation. Do not edit the source document. Preserve source references and clearly identify limitations and issues requiring human attorney judgment. Do not launch a retry or an alternate workflow if the composed workflow fails; report the failure instead.
            """
        } else {
            prompt = """
            Run the saved document-onboarding workflow.

            Target document: \(selectedFile.path)
            Intake goal: \(reviewContext)

            Classify and inventory the document, check completeness, identify metadata and initial issues, and recommend the next legal workflow. Do not edit the source document. Return a readable Markdown intake report for human review with source references and explicit uncertainties.
            """
        }
        runner.start(prompt: prompt, projectDirectory: projectDirectory, model: model, runTitle: runTitle, workflow: activeWorkflow.id, sourceDocument: selectedFile.path)
    }

    private func saveReport() {
        guard !runner.markdownReport.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(runner.runTitle.replacingOccurrences(of: " — ", with: "-").replacingOccurrences(of: " ", with: "-"))-Report.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try runner.markdownReport.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                runner.errorMessage = "Could not save the report: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private var reportContent: some View {
        StructuredText(markdown: runner.finalMarkdown)
            .textual.structuredTextStyle(.gitHub)
            .textual.textSelection(.enabled)
    }

    private var activitySection: some View {
        DisclosureGroup(isExpanded: $showingActivity) {
            VStack(alignment: .leading, spacing: 10) {
                if !runner.workflowTraceLines.isEmpty {
                    Text("Live workflow activity")
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(runner.workflowTraceLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(line.contains("Failed") || line.contains("Workflow failed") ? .red : .secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }

                if !runner.thinkingOutput.isEmpty {
                    Text("Working notes")
                        .font(.subheadline.weight(.semibold))
                    Text(runner.thinkingOutput)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxHeight: 140, alignment: .topLeading)
                }

                if !runner.traceOutput.isEmpty {
                    Text("Trace")
                        .font(.subheadline.weight(.semibold))
                    Text(runner.traceOutput)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

            }
            .padding(.top, 8)
        } label: {
            HStack {
                Label("Activity", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text(runner.activitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func findProjectDirectory() -> URL {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["PI_PROJECT_PATH"].map(URL.init(fileURLWithPath:)),
            URL(fileURLWithPath: fileManager.currentDirectoryPath),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        ].compactMap { $0 }

        if let match = candidates.first(where: {
            fileManager.fileExists(atPath: $0.appendingPathComponent(".pi/settings.json").path)
        }) {
            return match
        }
        return candidates.first ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }

    private static func displayDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else { return value }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}

@MainActor
final class PiRunner: ObservableObject {
    @Published var output = ""
    @Published var thinkingOutput = ""
    @Published var traceOutput = ""
    @Published var status = "Ready"
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var runTitle = ""
    @Published var reviewRuns: [PiRunRecord] = []
    @Published var currentStatus = ""
    @Published var workflowTraceLines: [String] = []
    @Published var workflowFailed = false
    @Published var failureMessage: String?
    @Published var currentWorkflow = "contract-review"

    var pendingReviewRuns: [PiRunRecord] {
        reviewRuns.filter { $0.status == "awaiting_human_review" || $0.status == "revision_requested" }
    }

    var attentionReviewRuns: [PiRunRecord] {
        reviewRuns.filter { $0.status == "awaiting_human_review" || $0.status == "revision_requested" || $0.status == "failed" }
    }

    var completedReviewRuns: [PiRunRecord] {
        reviewRuns.filter { $0.status == "completed" }
    }

    var finalMarkdown: String {
        let report = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !report.isEmpty else { return "" }
        if report.hasPrefix("#") {
            if currentRun?.workflow == "document-onboarding", report.hasPrefix("# Contract review") {
                return "# Document onboarding" + report.dropFirst("# Contract review".count)
            }
            return report
        }
        let title = currentRun?.workflow == "document-onboarding" ? "Document onboarding" : "Contract review"
        return "# \(title)\n\n\(report)"
    }

    var attorneyReviewItems: [AttorneyReviewItem] {
        let lines = finalMarkdown.components(separatedBy: .newlines)
        var inQueue = false
        var items: [AttorneyReviewItem] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "^#{1,6}\\s+Attorney review focus", options: [.regularExpression, .caseInsensitive]) != nil ||
                trimmed.range(of: "^#{1,6}\\s+Issues requiring attorney review", options: [.regularExpression, .caseInsensitive]) != nil {
                inQueue = true
                continue
            }
            if inQueue && trimmed.hasPrefix("#") { break }
            guard inQueue, trimmed.hasPrefix("- [") else { continue }
            let value = trimmed.replacingOccurrences(of: "^- \\[.\\]\\s*", with: "", options: .regularExpression)
            guard !value.isEmpty else { continue }
            items.append(AttorneyReviewItem(id: "issue-\(items.count)-\(value)", text: value))
        }
        return items
    }

    var activitySummary: String {
        let traceEvents = max(workflowTraceLines.count, traceOutput.split(separator: "\n").count)
        let workingNotes = thinkingOutput.isEmpty ? "No working notes" : "Working notes available"
        return "\(traceEvents) events · \(workingNotes)"
    }

    var markdownReport: String {
        guard !output.isEmpty || !thinkingOutput.isEmpty || !traceOutput.isEmpty else { return "" }
        return """
        # OrchestratorAI - Pi workflow report

        ## Final report

        \(finalMarkdown.isEmpty ? "_No final report was returned._" : finalMarkdown)

        ## Thinking / working notes

        \(thinkingOutput.isEmpty ? "_No explicit thinking block was emitted by the model._" : thinkingOutput)

        ## Tool and session trace

        \(traceOutput.isEmpty ? "_No trace events were recorded._" : traceOutput)
        """
    }

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private let lineBuffer = LineBuffer()
    private var currentProjectDirectory: URL?
    private var currentRun: PiRunRecord?

    func loadRuns(projectDirectory: URL) {
        let root = projectDirectory.appendingPathComponent("data/runs")
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            reviewRuns = []
            return
        }

        var records: [PiRunRecord] = []
        for case let url as URL in enumerator where url.lastPathComponent == "manifest.json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(PiRunRecord.self, from: data),
                  ["awaiting_human_review", "completed", "revision_requested", "failed"].contains(record.status) else { continue }
            let directory = url.deletingLastPathComponent()
            let reportURL = directory.appendingPathComponent("final.md")
            guard let report = try? String(contentsOf: reportURL, encoding: .utf8),
                  !report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            records.append(normalizedReviewState(record, projectDirectory: projectDirectory))
        }
        reviewRuns = records.sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
        if currentRun == nil, let latest = reviewRuns.first {
            loadRun(latest, projectDirectory: projectDirectory)
        }
    }

    private func normalizedReviewState(_ record: PiRunRecord, projectDirectory: URL) -> PiRunRecord {
        let directory = projectDirectory.appendingPathComponent(record.relativeDirectory)
        let checkpointDirectory = directory.appendingPathComponent("checkpoints")
        guard let checkpointFiles = try? FileManager.default.contentsOfDirectory(
            at: checkpointDirectory,
            includingPropertiesForKeys: nil
        ) else { return record }

        let checkpointStatus = checkpointFiles
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { text in
                text.components(separatedBy: .newlines).compactMap { line -> String? in
                    guard line.hasPrefix("status:") else { return nil }
                    return line.dropFirst("status:".count).trimmingCharacters(in: .whitespaces)
                }
            }
            .first

        let normalizedStatus: String?
        switch checkpointStatus {
        case "pending": normalizedStatus = "awaiting_human_review"
        case "changes_requested": normalizedStatus = "revision_requested"
        case "approved": normalizedStatus = "completed"
        default: normalizedStatus = nil
        }
        guard let normalizedStatus, normalizedStatus != record.status else { return record }
        return PiRunRecord(
            id: record.id,
            title: record.title,
            workflow: record.workflow,
            sourceDocument: record.sourceDocument,
            startedAt: record.startedAt,
            completedAt: normalizedStatus == "completed" ? (record.completedAt ?? record.startedAt) : nil,
            status: normalizedStatus,
            relativeDirectory: record.relativeDirectory
        )
    }

    func loadRun(_ record: PiRunRecord, projectDirectory: URL) {
        let directory = projectDirectory.appendingPathComponent(record.relativeDirectory)
        output = (try? String(contentsOf: directory.appendingPathComponent("final.md"), encoding: .utf8)) ?? ""
        thinkingOutput = (try? String(contentsOf: directory.appendingPathComponent("thinking.md"), encoding: .utf8)) ?? ""
        traceOutput = (try? String(contentsOf: directory.appendingPathComponent("trace.md"), encoding: .utf8)) ?? ""
        workflowTraceLines = traceOutput
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("- ") }
        runTitle = record.title
        currentRun = record
        currentWorkflow = record.workflow
        currentProjectDirectory = projectDirectory
        currentStatus = record.status
        workflowFailed = record.status == "failed"
        failureMessage = nil
        status = switch record.status {
        case "awaiting_human_review": "Awaiting human review"
        case "revision_requested": "Changes requested"
        case "completed": "Completed"
        default: record.status.replacingOccurrences(of: "_", with: " ").capitalized
        }
        isRunning = false
    }

    func clearDisplayedRun() {
        guard !isRunning else { return }
        output = ""
        thinkingOutput = ""
        traceOutput = ""
        workflowTraceLines = []
        runTitle = ""
        currentRun = nil
        currentStatus = ""
        workflowFailed = false
        failureMessage = nil
        status = "Ready"
    }

    func deleteRun(_ record: PiRunRecord, projectDirectory: URL) {
        let runsRoot = projectDirectory.appendingPathComponent("data/runs").standardizedFileURL
        let directory = projectDirectory.appendingPathComponent(record.relativeDirectory).standardizedFileURL
        let rootPrefix = runsRoot.path.hasSuffix("/") ? runsRoot.path : runsRoot.path + "/"
        guard directory.path.hasPrefix(rootPrefix),
              directory.lastPathComponent == record.id,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path) else {
            errorMessage = "Could not delete this review because its run directory could not be verified."
            return
        }

        do {
            try FileManager.default.removeItem(at: directory)
            if currentRun?.id == record.id {
                output = ""
                thinkingOutput = ""
                traceOutput = ""
                workflowTraceLines = []
                runTitle = ""
                currentRun = nil
                currentProjectDirectory = nil
                currentStatus = ""
                status = "Ready"
                workflowFailed = false
                failureMessage = nil
            }
            loadRuns(projectDirectory: projectDirectory)
        } catch {
            errorMessage = "Could not delete the review: \(error.localizedDescription)"
        }
    }

    func start(prompt: String, projectDirectory: URL, model: String, runTitle: String, workflow: String, sourceDocument: String) {
        stop()
        output = ""
        thinkingOutput = ""
        traceOutput = ""
        workflowTraceLines = []
        workflowFailed = false
        failureMessage = nil
        self.runTitle = runTitle
        currentWorkflow = workflow
        currentProjectDirectory = projectDirectory
        currentRun = createRun(projectDirectory: projectDirectory, title: runTitle, workflow: workflow, sourceDocument: sourceDocument)
        currentStatus = "running"
        status = "Starting Pi…"
        isRunning = true

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.findPiExecutable())
        process.arguments = [
            "--mode", "rpc",
            "--approve",
            "--provider", "ollama",
            "--model", model,
            "--name", runTitle,
            "--session-dir", ".pi/sessions"
        ]
        process.currentDirectoryURL = projectDirectory
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
                self.isRunning = false
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                if self.workflowFailed {
                    self.status = "Workflow failed"
                    self.persistCurrentRun(status: "failed")
                    if self.output.isEmpty {
                        self.errorMessage = self.failureMessage ?? "The contract-review workflow failed before returning a report."
                    }
                } else if process.terminationStatus != 0 {
                    self.status = "Stopped"
                    self.persistCurrentRun(status: "stopped")
                    if self.output.isEmpty {
                        self.errorMessage = "Pi stopped before returning a report. Check that Ollama is running and the selected model is available."
                    }
                } else if self.output.isEmpty {
                    self.status = "Stopped"
                    self.persistCurrentRun(status: "stopped")
                    self.errorMessage = "Pi stopped before returning a report."
                } else {
                    self.status = "Complete"
                }
            }
        }

        do {
            try process.run()
            self.process = process
            self.inputPipe = input
            self.outputPipe = output
            send(["type": "prompt", "message": prompt])
            status = "Reviewing locally…"
        } catch {
            isRunning = false
            status = "Unavailable"
            errorMessage = "Could not start Pi: \(error.localizedDescription)"
        }
    }

    func stop() {
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
            Task { @MainActor in
                self.handle(line: line)
            }
        }
    }

    private func handle(line: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return
        }
        guard let type = event["type"] as? String else { return }
        switch type {
        case "message_update":
            if let assistantEvent = event["assistantMessageEvent"] as? [String: Any],
               let assistantEventType = assistantEvent["type"] as? String {
                if assistantEventType == "text_delta", let delta = assistantEvent["delta"] as? String {
                    output.append(delta)
                } else if assistantEventType == "thinking_delta", let delta = assistantEvent["delta"] as? String {
                    thinkingOutput.append(delta)
                }
            }
        case "tool_execution_start":
            if let toolName = event["toolName"] as? String {
                status = "Using \(toolName)…"
                traceOutput.append("- Started `\(toolName)`\n")
            }
        case "tool_execution_end":
            if let toolName = event["toolName"] as? String {
                let failed = (event["isError"] as? Bool) == true
                traceOutput.append("- Finished `\(toolName)`\(failed ? " — error" : "")\n")
            }
        case "extension_ui_request":
            handleExtensionUIRequest(event)
        case "agent_start":
            traceOutput.append("- Agent started\n")
        case "agent_settled":
            isRunning = false
            traceOutput.append("- Agent settled\n")
            if workflowFailed {
                status = "Workflow failed"
                persistCurrentRun(status: "failed")
            } else {
                status = "Awaiting human review"
                persistCurrentRun(status: "awaiting_human_review")
            }
        case "extension_error":
            let detail = (event["error"] as? String) ?? (event["message"] as? String)
            failureMessage = detail
            workflowFailed = true
            errorMessage = detail.map { "Pi extension error: \($0)" } ?? "Pi extension error. Check the project skills and extensions."
        default:
            break
        }
    }

    private func handleExtensionUIRequest(_ event: [String: Any]) {
        guard event["method"] as? String == "setWidget",
              let widgetLines = event["widgetLines"] as? [String],
              widgetLines.first == "ORCH_TRACE",
              let payload = widgetLines.dropFirst().first,
              let data = payload.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let lines = message["lines"] as? [String] {
            workflowTraceLines = lines
            traceOutput = lines.map { "- \($0)" }.joined(separator: "\n")
        }
        if let event = message["event"] as? [String: Any],
           let eventType = event["type"] as? String {
            if eventType == "node_failed" {
                workflowFailed = true
                failureMessage = (event["error"] as? String) ?? (event["message"] as? String) ?? "A workflow agent failed."
            }
            if eventType == "run_completed",
               let runStatus = event["status"] as? String,
               runStatus != "completed" {
                workflowFailed = true
                failureMessage = (event["error"] as? String) ?? (event["message"] as? String) ?? "The contract-review workflow failed."
                isRunning = false
                status = "Workflow failed"
                persistCurrentRun(status: "failed")
            }
        }
        if let statusText = message["status"] as? String, !statusText.isEmpty {
            status = workflowFailed ? "Workflow failed" : statusText
        }
    }

    private func createRun(projectDirectory: URL, title: String, workflow: String, sourceDocument: String) -> PiRunRecord? {
        let nowDate = Date()
        let now = ISO8601DateFormatter().string(from: nowDate)
        let calendar = Calendar(identifier: .gregorian)
        let year = String(calendar.component(.year, from: nowDate))
        let month = String(format: "%02d", calendar.component(.month, from: nowDate))
        let day = String(format: "%02d", calendar.component(.day, from: nowDate))
        let timeSlug = now.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        let id = "\(year)-\(month)-\(day)-\(timeSlug)-\(workflow)"
        let relativeDirectory = "data/runs/\(year)/\(month)/\(year)-\(month)-\(day)/\(id)"
        let directory = projectDirectory.appendingPathComponent(relativeDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try sourceDocument.write(to: directory.appendingPathComponent("request.md"), atomically: true, encoding: .utf8)
            let record = PiRunRecord(id: id, title: title, workflow: workflow, sourceDocument: sourceDocument, startedAt: now, completedAt: nil, status: "running", relativeDirectory: relativeDirectory)
            try writeManifest(record, to: directory)
            return record
        } catch {
            errorMessage = "Could not create the run record: \(error.localizedDescription)"
            return nil
        }
    }

    private func persistCurrentRun(status: String) {
        guard let currentRun, let projectDirectory = currentProjectDirectory else { return }
        let directory = projectDirectory.appendingPathComponent(currentRun.relativeDirectory)
        let completedAt = status == "completed" ? ISO8601DateFormatter().string(from: Date()) : currentRun.completedAt
        let updated = PiRunRecord(id: currentRun.id, title: currentRun.title, workflow: currentRun.workflow, sourceDocument: currentRun.sourceDocument, startedAt: currentRun.startedAt, completedAt: completedAt, status: status, relativeDirectory: currentRun.relativeDirectory)
        do {
            try finalMarkdown.write(to: directory.appendingPathComponent("final.md"), atomically: true, encoding: .utf8)
            try thinkingOutput.write(to: directory.appendingPathComponent("thinking.md"), atomically: true, encoding: .utf8)
            try traceOutput.write(to: directory.appendingPathComponent("trace.md"), atomically: true, encoding: .utf8)
            if status == "awaiting_human_review" {
                try writeCheckpoint(status: "pending", to: directory, comment: "Awaiting attorney review.")
            }
            try writeManifest(updated, to: directory)
            self.currentRun = updated
            currentStatus = status
            loadRuns(projectDirectory: projectDirectory)
        } catch {
            errorMessage = "Could not save the run record: \(error.localizedDescription)"
        }
    }

    private func writeManifest(_ record: PiRunRecord, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    func approveCurrentRun() {
        transitionCurrentRun(to: "completed", checkpointStatus: "approved", comment: "Approved by human reviewer.")
    }

    func requestChangesForCurrentRun() {
        transitionCurrentRun(to: "revision_requested", checkpointStatus: "changes_requested", comment: "Changes requested by human reviewer.")
    }

    private func transitionCurrentRun(to status: String, checkpointStatus: String, comment: String) {
        guard let currentRun, let projectDirectory = currentProjectDirectory else { return }
        let directory = projectDirectory.appendingPathComponent(currentRun.relativeDirectory)
        let completedAt = status == "completed" ? ISO8601DateFormatter().string(from: Date()) : nil
        let updated = PiRunRecord(id: currentRun.id, title: currentRun.title, workflow: currentRun.workflow, sourceDocument: currentRun.sourceDocument, startedAt: currentRun.startedAt, completedAt: completedAt, status: status, relativeDirectory: currentRun.relativeDirectory)
        do {
            try writeCheckpoint(status: checkpointStatus, to: directory, comment: comment)
            try writeManifest(updated, to: directory)
            self.currentRun = updated
            currentStatus = status
            self.status = status == "completed" ? "Completed" : "Changes requested"
            loadRuns(projectDirectory: projectDirectory)
        } catch {
            errorMessage = "Could not save the human-review decision: \(error.localizedDescription)"
        }
    }

    private func writeCheckpoint(status: String, to directory: URL, comment: String) throws {
        let checkpoints = directory.appendingPathComponent("checkpoints")
        try FileManager.default.createDirectory(at: checkpoints, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let yaml = """
        status: \(status)
        type: attorney_review
        workflow: contract-review
        updated_at: \(timestamp)
        comment: \(comment)
        """
        try yaml.write(to: checkpoints.appendingPathComponent("01-attorney-review.yaml"), atomically: true, encoding: .utf8)
    }

    private static func findPiExecutable() -> String {
        if let configured = ProcessInfo.processInfo.environment["PI_PATH"],
           FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }

        let candidates = [
            "/opt/homebrew/bin/pi",
            "/usr/local/bin/pi",
            "/Users/golfergeek/.nvm/versions/node/v22.22.3/bin/pi"
        ]
        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return match
        }
        return "/usr/bin/env"
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
