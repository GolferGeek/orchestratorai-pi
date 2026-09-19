import AppKit
import Foundation
import SwiftUI
import Textual
import UniformTypeIdentifiers

struct AttorneyReviewItem: Identifiable, Hashable {
    let id: String
    let text: String
    let severity: String?
}

@main
struct PiApp: App {
    var body: some Scene {
        WindowGroup("OrchestratorAI - Pi") {
            ContentView()
                .frame(minWidth: 960, idealWidth: 1500, minHeight: 720, idealHeight: 1150)
        }
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    @StateObject private var runner = PiRunner()
    @State private var selectedFile: URL?
    @State private var showingImporter = false
    @State private var paramValues: [String: String] = [:]
    @State private var model = "qwen3.6:latest"
    @State private var selectedWorkflow = "contract-review"
    @State private var showingActivity = false
    @State private var reviewedIssueIDs: Set<String> = []
    @State private var reviewDecisionComment = ""
    @State private var gateDecisionComment = ""
    @State private var runPendingDeletion: RunRecord?
    @State private var showingDeleteConfirmation = false
    @State private var runsPendingClear: [RunRecord] = []
    @State private var showingClearApprovedConfirmation = false
    @State private var sidebarSelection: SidebarSelection? = .workflow("contract-review")
    @State private var expandedGroups: Set<String> = Set(LegalWorkflowCatalog.groups.map(\.id))
    @State private var projectDirectory = PiEnvironment.findProjectDirectory()
    @State private var projectTrusted = false
    @State private var workflows: [WorkflowDefinition] = []

    private var activeWorkflow: WorkflowDefinition? {
        workflows.first(where: { $0.id == selectedWorkflow })
            ?? workflows.first(where: { $0.id == "contract-review" })
            ?? workflows.first
    }

    /// The run shown in the detail pane: the selected run when it belongs to the active workflow.
    private var displayedRun: RunRecord? {
        guard let run = runner.selectedRun, run.workflow == activeWorkflow?.id else { return nil }
        return run
    }

    private var displayedState: ReviewState? {
        displayedRun.map { runner.reviewState(for: $0) }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                runner: runner,
                workflows: workflows,
                selection: $sidebarSelection,
                expandedGroups: $expandedGroups
            )
        } content: {
            RunListView(
                runner: runner,
                selection: sidebarSelection,
                workflow: sidebarSelection?.workflowId.flatMap { id in workflows.first(where: { $0.id == id }) },
                onOpen: openRun,
                onNewRun: startNewRun,
                onDelete: { run in
                    runPendingDeletion = run
                    showingDeleteConfirmation = true
                },
                onClearApproved: { runs in
                    guard !runs.isEmpty else { return }
                    runsPendingClear = runs
                    showingClearApprovedConfirmation = true
                }
            )
        } detail: {
            if sidebarSelection == .inbox, runner.selectedRun == nil {
                inboxPlaceholder
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if !projectTrusted { trustCard }
                            if runner.storeUnavailable { storeCard }
                            taskCard
                            if let workflow = activeWorkflow, workflow.isReady || displayedRun != nil {
                                contextCard
                                sourceDocumentCard
                                gateCard
                                attorneyReviewCard
                                resultCard
                                EvaluationsCard(evaluations: runner.evaluations)
                                humanReviewCard
                            }
                        }
                        .padding(28)
                    }
                }
                .frame(minWidth: 400)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            reloadProject()
            runner.attach(projectDirectory: projectDirectory)
            if let run = runner.selectedRun, workflows.contains(where: { $0.id == run.workflow }) {
                selectedWorkflow = run.workflow
            } else if let firstReady = workflows.first(where: \.isReady) {
                selectedWorkflow = firstReady.id
            }
            sidebarSelection = .workflow(selectedWorkflow)
            resetParams()
        }
        .onChange(of: sidebarSelection) { _, newValue in
            // Inbox keeps whatever run is open; a catalog row switches the active workflow.
            if case .workflow(let id) = newValue {
                selectedWorkflow = id
            }
        }
        .onChange(of: selectedWorkflow) { _, _ in
            reviewedIssueIDs = []
            reviewDecisionComment = ""
            gateDecisionComment = ""
            resetParams()
            if runner.selectedRun?.workflow != selectedWorkflow {
                selectedFile = nil
                runner.select(runId: nil)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: activeWorkflow?.launch?.inputKind == .folder ? [.folder] : [.item, .data, .text, .pdf],
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
        .alert("Delete this run?", isPresented: $showingDeleteConfirmation) {
            Button("Delete Run", role: .destructive) {
                if let run = runPendingDeletion { runner.deleteRun(run) }
                runPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes the run, its journal, and its attorney checkpoints from the on-device store.\n\n\(runPendingDeletion?.title ?? "This run")")
        }
        .alert("Clear approved runs?", isPresented: $showingClearApprovedConfirmation) {
            Button("Delete \(runsPendingClear.count) Approved", role: .destructive) {
                for run in runsPendingClear { runner.deleteRun(run) }
                runsPendingClear = []
            }
            Button("Cancel", role: .cancel) { runsPendingClear = [] }
        } message: {
            Text("This permanently removes \(runsPendingClear.count) approved run\(runsPendingClear.count == 1 ? "" : "s") in this list, with their journals and attorney checkpoints, from the on-device store.")
        }
    }

    private func reloadProject() {
        projectDirectory = PiEnvironment.findProjectDirectory()
        workflows = LegalWorkflowCatalog.workflows(projectDirectory: projectDirectory)
        projectTrusted = PiEnvironment.isProjectTrusted(projectDirectory)
    }

    private func resetParams() {
        paramValues = activeWorkflow?.launch?.initialValues() ?? [:]
    }

    // MARK: Selection

    /// Inbox with nothing open: the detail has no workflow to frame, so say so.
    private var inboxPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Select a run")
                .font(.headline)
            Text("Pick a run from the list to review it, or choose a workflow in the sidebar to start a new one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .frame(minWidth: 400)
    }

    /// "New run" in the list: drop the open run so the detail shows the bare launch card.
    private func startNewRun() {
        reviewedIssueIDs = []
        reviewDecisionComment = ""
        gateDecisionComment = ""
        selectedFile = nil
        runner.select(runId: nil)
        resetParams()
    }

    private func openRun(_ run: RunRecord) {
        reviewedIssueIDs = []
        reviewDecisionComment = ""
        gateDecisionComment = ""
        selectedWorkflow = run.workflow
        runner.select(runId: run.id)
        if let source = run.sourceDocument, source.hasPrefix("/") {
            selectedFile = URL(fileURLWithPath: source)
        } else {
            selectedFile = nil
        }
        paramValues.merge(run.params) { _, stored in stored }
    }

    // MARK: Header and setup cards

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("OrchestratorAI - Pi")
                    .font(.title2.weight(.semibold))
                Text(activeWorkflow?.title ?? "Workflows")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(runner.isRunning || (displayedState?.isLive ?? false) ? .orange : .green)
                .frame(width: 9, height: 9)
            Text(displayedState?.label ?? runner.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let run = displayedRun {
                Text("· \(run.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(.regularMaterial)
    }

    private var trustCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Pi has not trusted this project yet", systemImage: "lock.shield")
                    .font(.headline)
                Text("Delegated agents are spawned by Pi without the app's approval flag, so the project must be trusted in ~/.pi/agent/trust.json before workflow agents can load project profiles, skills, and the attorney gate. This is the same decision `/trust` records in the Pi terminal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(projectDirectory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                Button("Trust this project for Pi") {
                    do {
                        try PiEnvironment.trustProject(projectDirectory)
                        projectTrusted = true
                    } catch {
                        runner.errorMessage = "Could not save the trust decision: \(error.localizedDescription)"
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("trust.approve")
            }
            .padding(8)
        }
    }

    private var storeCard: some View {
        GroupBox {
            Label("Could not open data/orchestrator.sqlite in \(projectDirectory.path)", systemImage: "externaldrive.badge.xmark")
                .font(.callout)
                .foregroundStyle(.red)
                .padding(8)
        }
    }

    // MARK: Launch

    private var taskCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                if let workflow = activeWorkflow {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(workflow.title)
                                    .font(.title3.weight(.semibold))
                                Text(workflow.status.label)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(workflow.isReady ? Color.green.opacity(0.18) : Color.secondary.opacity(0.14))
                                    .foregroundStyle(workflow.isReady ? Color.green : Color.secondary)
                                    .clipShape(Capsule())
                            }
                            Text(workflow.description)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: workflow.icon)
                            .font(.largeTitle)
                            .foregroundStyle(.blue.opacity(0.75))
                    }

                    if let launch = workflow.launch {
                        launchControls(workflow: workflow, launch: launch)
                    } else {
                        notInstalled(workflow: workflow)
                    }
                } else {
                    Text("No workflows found in \(projectDirectory.appendingPathComponent(".pi/workflows").path)")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    /// Start is allowed once the input the launch block asks for is present.
    private func canStart(_ launch: WorkflowLaunchSpec) -> Bool {
        switch launch.inputKind {
        case .file, .folder:
            return selectedFile != nil
        case .none:
            return launch.requiredFieldParams.allSatisfy { !(paramValues[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    @ViewBuilder
    private func launchControls(workflow: WorkflowDefinition, launch: WorkflowLaunchSpec) -> some View {
        if launch.inputKind != .none {
            Button {
                showingImporter = true
            } label: {
                Label(
                    selectedFile == nil ? "Choose a \(launch.fileLabel)" : "Choose a different \(launch.fileLabel)",
                    systemImage: launch.inputKind == .folder ? "folder.badge.plus" : "folder"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("launch.choose_file")
        } else {
            Text("No document upload — fill in the fields below, then start.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let selectedFile, launch.inputKind != .none {
            Label(selectedFile.path, systemImage: "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        if !launch.samples.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Demo samples")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                // Samples come from the workflow's own launch block — not a per-workflow screen.
                ForEach(launch.samples) { sample in
                    let url = projectDirectory.appendingPathComponent(sample.relativePath)
                    let exists = FileManager.default.fileExists(atPath: url.path)
                    Button {
                        guard exists else {
                            runner.errorMessage = "Demo sample missing: \(sample.relativePath)"
                            return
                        }
                        selectedFile = url
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedFile?.path == url.path ? "checkmark.circle.fill" : "doc.text")
                            Text(sample.title)
                            Spacer(minLength: 0)
                            if !exists {
                                Text("missing")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!exists)
                    .accessibilityIdentifier("launch.sample.\(sample.id)")
                }
            }
        }

        HStack {
            Button {
                startRun(workflow: workflow, launch: launch)
            } label: {
                Label(runner.isRunning ? "Working…" : "Start local workflow", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart(launch) || runner.isRunning || !projectTrusted)
            .accessibilityIdentifier("launch.start")

            if runner.isRunning {
                Button("Stop", role: .destructive) {
                    runner.stop()
                }
                .accessibilityIdentifier("launch.stop")
            }
        }
    }

    private func notInstalled(workflow: WorkflowDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not installed yet", systemImage: "hourglass")
                .font(.subheadline.weight(.semibold))
            Text("No `.pi/workflows/\(workflow.id).yaml` in this project. Add the workflow YAML with an `orchestrator-launch` block in its `doc:` and it appears here with its own launch UI — no app change needed.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                // Intentionally disabled — do not fake a run.
            } label: {
                Label("Start local workflow", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var contextCard: some View {
        Group {
            if let launch = activeWorkflow?.launch {
                GroupBox("Workflow context") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(launch.fields) { field in
                            HStack(alignment: field.kind == .text ? .top : .center) {
                                Text(field.label)
                                    .frame(width: 90, alignment: .leading)
                                switch field.kind {
                                case .choice:
                                    Picker(field.label, selection: binding(for: field.param)) {
                                        ForEach(field.options, id: \.self) { Text($0).tag($0) }
                                    }
                                    .labelsHidden()
                                    .accessibilityIdentifier("context.field.\(field.param)")
                                case .line:
                                    TextField(field.label, text: binding(for: field.param))
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityIdentifier("context.field.\(field.param)")
                                case .text:
                                    TextEditor(text: binding(for: field.param))
                                        .font(.body)
                                        .frame(minHeight: 68)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                                        .accessibilityIdentifier("context.field.\(field.param)")
                                }
                            }
                        }

                        HStack {
                            Text("Local model")
                                .frame(width: 90, alignment: .leading)
                            TextField("Ollama model", text: $model)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("context.model")
                            Text("Ollama")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func binding(for param: String) -> Binding<String> {
        Binding(
            get: { paramValues[param] ?? "" },
            set: { paramValues[param] = $0 }
        )
    }

    private func startRun(workflow: WorkflowDefinition, launch: WorkflowLaunchSpec) {
        var params = paramValues
        params.removeValue(forKey: "run_id")
        let source: String
        if launch.inputKind == .none {
            // Title the run after the first required field (e.g. the research question).
            let key = launch.fields.first(where: { launch.requiredFieldParams.contains($0.param) })?.param ?? launch.fields.first?.param ?? ""
            source = String((paramValues[key] ?? workflow.title).prefix(80))
        } else {
            guard let selectedFile else { return }
            params[launch.fileParam] = selectedFile.path
            source = selectedFile.path
        }
        reviewedIssueIDs = []
        reviewDecisionComment = ""
        gateDecisionComment = ""
        runner.start(workflow: workflow, params: params, sourceDocument: source, model: model)
    }

    // MARK: Gate (mid-flow attorney decision)

    private var gateCard: some View {
        Group {
            if let run = displayedRun, case .awaitingGate(let gate) = runner.reviewState(for: run) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(gate.title, systemImage: "hand.raised.fill")
                                .font(.headline)
                            Spacer()
                            Text("Workflow paused")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.18))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        Text("An agent is waiting on your direction before the workflow continues. Your decision and note are handed back to the next step verbatim.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if let summary = gate.summaryMarkdown, !summary.isEmpty {
                            ScrollView {
                                StructuredText(markdown: summary)
                                    .textual.structuredTextStyle(.gitHub)
                                    .textual.textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                            }
                            .frame(minHeight: 160, maxHeight: 360)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        TextField("Direction for the next step (optional)…", text: $gateDecisionComment)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("gate.comment")

                        HStack {
                            Button("Approve and continue") {
                                runner.decide(checkpoint: gate, approved: true, comment: gateDecisionComment)
                                gateDecisionComment = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("gate.approve")
                            Button("Request changes and continue") {
                                runner.decide(checkpoint: gate, approved: false, comment: gateDecisionComment)
                                gateDecisionComment = ""
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("gate.request_changes")
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    // MARK: Report

    private var finalMarkdown: String {
        displayedRun?.resultMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var attorneyReviewItems: [AttorneyReviewItem] {
        Self.parseAttorneyItems(from: finalMarkdown)
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
                    .disabled(finalMarkdown.isEmpty)
                    .accessibilityIdentifier("report.save")
                }

                if let run = displayedRun, let state = displayedState {
                    if state == .failed || state == .stopped, finalMarkdown.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "xmark.octagon")
                                .font(.largeTitle)
                                .foregroundStyle(.red)
                            Text(state == .failed ? "Workflow failed" : "Workflow stopped")
                                .font(.headline)
                            Text(run.error ?? "The local workflow stopped without a final report. Check Activity for the failing step, fix the input or model, and re-run. No alternate workflow was launched.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .padding(.horizontal, 12)
                    } else if finalMarkdown.isEmpty {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text(state.label)
                                .font(.headline)
                            Text(runner.events.last?.summary ?? "Waiting for the first agent…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .padding(.horizontal, 12)
                    } else {
                        ScrollView {
                            StructuredText(markdown: finalMarkdown)
                                .textual.structuredTextStyle(.gitHub)
                                .textual.textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                        .frame(minHeight: 260, maxHeight: 430)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    activitySection
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No report yet")
                            .font(.headline)
                        Text("Choose a \(activeWorkflow?.fileLabel ?? "document") (or a demo sample), set context, and start the local workflow. Results and the attorney checklist appear here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.horizontal, 12)
                }
            }
            .padding(8)
        }
    }

    private var attorneyReviewCard: some View {
        let items = attorneyReviewItems
        let reviewedCount = reviewedIssueIDs.intersection(Set(items.map(\.id))).count
        let copy = activeWorkflow?.launch?.review ?? LaunchReviewCopy()
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(copy.focusTitle, systemImage: "exclamationmark.bubble")
                        .font(.headline)
                    Spacer()
                    if !items.isEmpty {
                        Text("\(reviewedCount)/\(items.count) marked reviewed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(copy.focusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let state = displayedState, state.isLive {
                    Label("Workflow running — checklist appears when the report is ready.", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if displayedState == .failed || displayedState == .stopped {
                    Label("No checklist — the workflow ended before a report was produced.", systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if finalMarkdown.isEmpty {
                    Text("After you run a Ready workflow, prioritized issues for counsel appear here as a shared checklist (same HITL path for every workflow).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Report has no attorney-review checklist", systemImage: "questionmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("Expected unchecked items under “Attorney review focus” (`- [ ] SEVERITY — issue; action`). Open the final report below, or re-run if the model omitted the section.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView(value: Double(reviewedCount), total: Double(max(items.count, 1)))
                        .tint(reviewedCount == items.count ? .green : .orange)
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
                                    if let severity = item.severity {
                                        Text(severity)
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(severityTint(severity).opacity(0.18))
                                            .foregroundStyle(severityTint(severity))
                                            .clipShape(Capsule())
                                    }
                                    Text(item.text)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .strikethrough(reviewedIssueIDs.contains(item.id), color: .secondary)
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

    private func severityTint(_ severity: String) -> Color {
        switch severity.uppercased() {
        case "HIGH", "CRITICAL": return .red
        case "MEDIUM": return .orange
        case "LOW": return .blue
        default: return .secondary
        }
    }

    private var humanReviewCard: some View {
        let items = attorneyReviewItems
        let reviewedCount = reviewedIssueIDs.intersection(Set(items.map(\.id))).count
        let allReviewed = items.isEmpty || reviewedCount == items.count
        let copy = activeWorkflow?.launch?.review ?? LaunchReviewCopy()

        return Group {
            if let run = displayedRun, let state = displayedState {
                let pendingFinal = runner.checkpoints(for: run.id).last(where: { $0.kind == "final_review" && $0.isPending })
                if let pendingFinal {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Attorney review required", systemImage: "person.badge.key")
                                    .font(.headline)
                                Spacer()
                                Text("HITL checkpoint")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.18))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }

                            Text(copy.blurb)
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            if !items.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: allReviewed ? "checkmark.seal.fill" : "circle.dashed")
                                        .foregroundStyle(allReviewed ? .green : .orange)
                                    Text(allReviewed
                                         ? "All \(items.count) focus items marked reviewed."
                                         : "\(reviewedCount) of \(items.count) focus items marked reviewed — finish the checklist above before approving when possible.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("No checklist items were parsed from the report. You can still approve or request changes after reading the full report.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Decision note (saved to checkpoint)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                TextField("Optional note for the matter file…", text: $reviewDecisionComment)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("review.comment")
                            }

                            HStack {
                                Button("Approve review") {
                                    runner.decide(checkpoint: pendingFinal, approved: true, comment: reviewDecisionComment)
                                    reviewDecisionComment = ""
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("review.approve")

                                Button("Request changes") {
                                    runner.decide(checkpoint: pendingFinal, approved: false, comment: reviewDecisionComment)
                                    reviewDecisionComment = ""
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("review.request_changes")
                            }

                            if !allReviewed && !items.isEmpty {
                                Text("Approve stays available so demos are not blocked — the progress cue above is guidance, not a hard gate.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(8)
                    }
                } else if state == .approved || state == .changesRequested {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(state == .approved ? "Approved by attorney" : "Changes requested — re-run when ready", systemImage: state == .approved ? "checkmark.seal.fill" : "arrow.uturn.backward.circle")
                                .font(.headline)
                            ForEach(runner.checkpoints(for: run.id).filter { !$0.isPending }) { checkpoint in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: checkpoint.isGate ? "hand.raised" : "person.badge.key")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(checkpoint.title) — \(checkpoint.status.replacingOccurrences(of: "_", with: " "))")
                                            .font(.caption.weight(.semibold))
                                        if let comment = checkpoint.decisionComment, !comment.isEmpty {
                                            Text(comment)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(Self.displayDate(checkpoint.decidedAt ?? checkpoint.requestedAt))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Button("Reopen for review") {
                                runner.reopenReview(runId: run.id)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("review.reopen")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }
            }
        }
    }

    private var sourceDocumentCard: some View {
        Group {
            if activeWorkflow?.launch?.inputKind != LaunchInputKind.none {
                sourceDocumentBox
            }
        }
    }

    private var sourceDocumentBox: some View {
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
                    Text(selectedFile == nil
                         ? "Choose a readable text or Markdown \(activeWorkflow?.fileLabel ?? "document") to preview it here."
                         : "This file could not be previewed as UTF-8 text (binary/PDF previews are not shown). The workflow can still use the path if the runtime supports it.")
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

    private func saveReport() {
        guard !finalMarkdown.isEmpty, let run = displayedRun else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(run.title.replacingOccurrences(of: " — ", with: "-").replacingOccurrences(of: " ", with: "-"))-Report.md"
        let markdown = finalMarkdown
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                runner.errorMessage = "Could not save the report: \(error.localizedDescription)"
            }
        }
    }

    private var activitySection: some View {
        DisclosureGroup(isExpanded: $showingActivity) {
            VStack(alignment: .leading, spacing: 10) {
                if runner.events.isEmpty {
                    Text("No journal entries yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Workflow journal")
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(runner.events) { event in
                            DisclosureGroup {
                                if let detail = event.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(Self.displayTime(event.at))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                    Text(event.summary)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(event.isFailure ? .red : .secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .disclosureGroupStyle(.automatic)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Label("Activity", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text("\(runner.events.count) journal entries · \(displayedRun?.agents.map { "\($0) agent calls" } ?? "on-device store")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Parsing helpers

    static func parseAttorneyItems(from markdown: String) -> [AttorneyReviewItem] {
        var inQueue = false
        var items: [AttorneyReviewItem] = []
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "^#{1,6}\\s+Attorney (review|intake) focus", options: [.regularExpression, .caseInsensitive]) != nil ||
                trimmed.range(of: "^#{1,6}\\s+Issues requiring attorney review", options: [.regularExpression, .caseInsensitive]) != nil {
                inQueue = true
                continue
            }
            if inQueue && trimmed.hasPrefix("#") { break }
            guard inQueue, trimmed.hasPrefix("- [") else { continue }
            let value = trimmed.replacingOccurrences(of: "^- \\[.\\]\\s*", with: "", options: .regularExpression)
            guard !value.isEmpty else { continue }
            let severity = parseSeverity(from: value)
            let display = stripSeverityPrefix(from: value)
            items.append(AttorneyReviewItem(id: "issue-\(items.count)-\(display)", text: display, severity: severity))
        }
        return items
    }

    private static func parseSeverity(from text: String) -> String? {
        let pattern = #"^\**(CRITICAL|HIGH|MEDIUM|LOW|INFO)\**\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swiftRange]).uppercased()
    }

    private static func stripSeverityPrefix(from text: String) -> String {
        var result = text
        if parseSeverity(from: text) != nil,
           let range = result.range(of: #"^\**(CRITICAL|HIGH|MEDIUM|LOW|INFO)\**"#, options: [.regularExpression, .caseInsensitive]) {
            result.removeSubrange(range)
        }
        result = result.trimmingCharacters(in: .whitespaces)
        if result.hasPrefix("—") || result.hasPrefix("-") || result.hasPrefix(":") {
            result = String(result.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return result.isEmpty ? text : result
    }

    static func displayDate(_ value: String) -> String {
        guard let date = parseDate(value) else { return value }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }

    private static func displayTime(_ value: String) -> String {
        guard let date = parseDate(value) else { return value }
        let display = DateFormatter()
        display.dateFormat = "HH:mm:ss"
        return display.string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
