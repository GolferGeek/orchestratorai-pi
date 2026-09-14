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
    let severity: String?

    var displayText: String { text }
}

struct WorkflowDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let description: String
    let fileLabel: String
    let groupId: String
    let status: WorkflowInstallStatus

    var isReady: Bool { status == .ready }
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
    @State private var reviewDecisionComment = ""
    @State private var runPendingDeletion: PiRunRecord?
    @State private var showingDeleteConfirmation = false
    @State private var legalWorkflowsExpanded = true
    @State private var expandedGroups: Set<String> = Set(LegalWorkflowCatalog.groups.map(\.id))
    @State private var projectDirectory = ContentView.findProjectDirectory()

    private let sides = ["Receiving party", "Disclosing party", "Both parties", "Not specified"]

    private var workflows: [WorkflowDefinition] {
        LegalWorkflowCatalog.workflows(projectDirectory: projectDirectory)
    }

    private var activeWorkflow: WorkflowDefinition {
        workflows.first(where: { $0.id == selectedWorkflow })
            ?? workflows.first(where: { $0.id == "contract-review" })
            ?? workflows[0]
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
                        if activeWorkflow.isReady || !runner.markdownReport.isEmpty {
                            contextCard
                            sourceDocumentCard
                            attorneyReviewCard
                            resultCard
                            humanReviewCard
                        }
                    }
                    .padding(28)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            projectDirectory = Self.findProjectDirectory()
            runner.loadRuns(projectDirectory: projectDirectory)
            if workflows.contains(where: { $0.id == runner.currentWorkflow }) {
                selectedWorkflow = runner.currentWorkflow
            } else if let firstReady = workflows.first(where: \.isReady) {
                selectedWorkflow = firstReady.id
            }
        }
        .onChange(of: selectedWorkflow) { _, newValue in
            reviewedIssueIDs = []
            reviewDecisionComment = ""
            reviewContext = Self.defaultContext(for: newValue)
            if newValue == "contract-review" && !sides.contains(reviewerSide) {
                reviewerSide = "Receiving party"
            }
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
                            Spacer(minLength: 0)
                            Text("\(workflows.filter(\.isReady).count)/\(workflows.count) ready")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if legalWorkflowsExpanded {
                        ForEach(LegalWorkflowCatalog.groups) { group in
                            let items = workflows.filter { $0.groupId == group.id }
                            if !items.isEmpty {
                                Button {
                                    if expandedGroups.contains(group.id) {
                                        expandedGroups.remove(group.id)
                                    } else {
                                        expandedGroups.insert(group.id)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: expandedGroups.contains(group.id) ? "chevron.down" : "chevron.right")
                                            .font(.caption.weight(.bold))
                                        Text(group.name)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .padding(.leading, 18)
                                }
                                .buttonStyle(.plain)

                                if expandedGroups.contains(group.id) {
                                    ForEach(items) { workflow in
                                        Button {
                                            selectedWorkflow = workflow.id
                                        } label: {
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack(spacing: 6) {
                                                    Label(workflow.title, systemImage: workflow.icon)
                                                        .font(.callout)
                                                    Spacer(minLength: 0)
                                                    Text(workflow.status.label)
                                                        .font(.caption2.weight(.semibold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(workflow.isReady ? Color.green.opacity(0.18) : Color.secondary.opacity(0.14))
                                                        .foregroundStyle(workflow.isReady ? Color.green : Color.secondary)
                                                        .clipShape(Capsule())
                                                }
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
        .frame(minWidth: 260)
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
        reviewedIssueIDs = []
        reviewDecisionComment = ""
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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(activeWorkflow.title)
                                .font(.title3.weight(.semibold))
                            Text(activeWorkflow.status.label)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(activeWorkflow.isReady ? Color.green.opacity(0.18) : Color.secondary.opacity(0.14))
                                .foregroundStyle(activeWorkflow.isReady ? Color.green : Color.secondary)
                                .clipShape(Capsule())
                        }
                        Text(activeWorkflow.description)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: activeWorkflow.icon)
                        .font(.largeTitle)
                        .foregroundStyle(.blue.opacity(0.75))
                }

                if activeWorkflow.isReady {
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

                    if !sampleDocuments(for: activeWorkflow.id).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Demo samples")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            // Keep sample picks on the shared launch card — not a per-workflow screen.
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(sampleDocuments(for: activeWorkflow.id)) { sample in
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
                                }
                            }
                        }
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
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Not installed yet", systemImage: "hourglass")
                            .font(.subheadline.weight(.semibold))
                        Text("No `.pi/workflows/\(activeWorkflow.id).yaml` in this project. The Legal catalog lists every offering honestly — this entry uses the shared launch UI once its workflow YAML and agents are added.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Document Onboarding and Contract Review are Ready. Remaining workflows share this same launch path when installed.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button {
                        // Intentionally disabled — do not fake a run.
                    } label: {
                        Label("Start local workflow", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                }
            }
            .padding(8)
        }
    }

    private var contextCard: some View {
        Group {
            if activeWorkflow.isReady {
                GroupBox(contextCardTitle) {
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
                            Text(contextObjectiveLabel)
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
        }
    }

    private var contextCardTitle: String {
        switch activeWorkflow.id {
        case "contract-review": return "Review context"
        case "document-onboarding": return "Onboarding context"
        default: return "Workflow context"
        }
    }

    private var contextObjectiveLabel: String {
        switch activeWorkflow.id {
        case "contract-review": return "Objective"
        case "document-onboarding": return "Intake goal"
        default: return "Goal"
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

                if runner.workflowFailed && runner.finalMarkdown.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "xmark.octagon")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("Workflow failed")
                            .font(.headline)
                        Text(runner.failureMessage ?? "The local workflow stopped without a final report. Check Activity for the failing step, fix the input or model, and re-run. No alternate workflow was launched.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.horizontal, 12)
                } else if runner.markdownReport.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(activeWorkflow.isReady ? "No report yet" : "Workflow not installed")
                            .font(.headline)
                        Text(activeWorkflow.isReady
                             ? "Choose a \(activeWorkflow.fileLabel) (or a demo sample), set context, and start the local workflow. Results and the attorney checklist appear here."
                             : "This catalog entry is Coming soon — Start stays disabled until its YAML is installed.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.horizontal, 12)
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
        let reviewedCount = reviewedIssueIDs.intersection(Set(items.map(\.id))).count
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(attorneyFocusTitle, systemImage: "exclamationmark.bubble")
                        .font(.headline)
                    Spacer()
                    if !items.isEmpty {
                        Text("\(reviewedCount)/\(items.count) marked reviewed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(attorneyFocusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if runner.isRunning {
                    Label("Workflow running — checklist appears when the report is ready.", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if runner.workflowFailed {
                    Label("No checklist — the workflow failed before a report was produced.", systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if runner.finalMarkdown.isEmpty {
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
                    if !items.isEmpty {
                        ProgressView(value: Double(reviewedCount), total: Double(max(items.count, 1)))
                            .tint(reviewedCount == items.count ? .green : .orange)
                    }
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
                                    Text(item.displayText)
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

    private var attorneyFocusTitle: String {
        switch activeWorkflow.id {
        case "document-onboarding": return "Attorney intake focus"
        case "contract-review": return "Attorney review focus"
        default: return "Attorney review focus"
        }
    }

    private var attorneyFocusSubtitle: String {
        switch activeWorkflow.id {
        case "document-onboarding":
            return "Mark each intake blocker or question as you verify it. Decisions are recorded on the shared attorney-review checkpoint."
        case "contract-review":
            return "Work the Red/Blue standout issues before approving. Same shared HITL checkpoint as other Ready workflows."
        default:
            return "Prioritized questions for counsel. Same shared human-review checkpoint for every Ready workflow."
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
        let awaiting = runner.currentStatus == "awaiting_human_review" || runner.currentStatus == "revision_requested"
        let items = runner.attorneyReviewItems
        let reviewedCount = reviewedIssueIDs.intersection(Set(items.map(\.id))).count
        let allReviewed = items.isEmpty || reviewedCount == items.count

        return Group {
            if awaiting {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(
                                runner.currentStatus == "revision_requested"
                                    ? "Changes requested — re-review when ready"
                                    : "Attorney review required",
                                systemImage: "person.badge.key"
                            )
                            .font(.headline)
                            Spacer()
                            Text(runner.currentStatus == "revision_requested" ? "Revision" : "HITL checkpoint")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.18))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }

                        Text(humanReviewBlurb)
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
                            TextField(
                                runner.currentStatus == "revision_requested"
                                    ? "What still needs attention…"
                                    : "Optional note for the matter file…",
                                text: $reviewDecisionComment
                            )
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Button("Approve review") {
                                runner.approveCurrentRun(comment: reviewDecisionComment)
                                reviewDecisionComment = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(runner.isRunning)

                            Button("Request changes") {
                                runner.requestChangesForCurrentRun(comment: reviewDecisionComment)
                                reviewDecisionComment = ""
                            }
                            .buttonStyle(.bordered)
                            .disabled(runner.isRunning)
                        }

                        if !allReviewed && !items.isEmpty {
                            Text("Approve stays available so demos are not blocked — the progress cue above is guidance, not a hard gate.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var humanReviewBlurb: String {
        switch activeWorkflow.id {
        case "document-onboarding":
            return "Confirm intake findings, missing materials, and the recommended next workflow. Recording Approve or Request changes writes the shared attorney-review checkpoint for this run."
        case "contract-review":
            return "Confirm Red/Blue findings and judgment calls in the report. Recording Approve or Request changes completes the shared attorney-review checkpoint — not a legal opinion."
        default:
            return "Review the report above and record a decision before this run is marked complete."
        }
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
                    Text(selectedFile == nil
                         ? "Choose a readable text or Markdown \(activeWorkflow.fileLabel) to preview it here."
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

    private func startReview() {
        guard activeWorkflow.isReady else {
            runner.errorMessage = "\(activeWorkflow.title) is not installed yet (no workflow YAML)."
            return
        }
        guard let selectedFile else { return }
        let projectDirectory = Self.findProjectDirectory()
        self.projectDirectory = projectDirectory
        let documentTitle = selectedFile.deletingPathExtension().lastPathComponent
        let runTitle = "\(activeWorkflow.title) — \(documentTitle)"
        let prompt: String
        switch activeWorkflow.id {
        case "contract-review":
            prompt = """
            Run the saved contract-review workflow.

            Target document: \(selectedFile.path)
            Reviewer side: \(reviewerSide)
            Review context: \(reviewContext)

            Execute the complete text-first composed workflow: independent Red and Blue contract reviews, arbitration of their natural-language findings, and summary generation. Do not edit the source document. Preserve source references. Use severity HIGH/MEDIUM/LOW. Include an ## Attorney review focus section with unchecked tasks (`- [ ] SEVERITY — issue; action`). Clearly identify limitations and issues requiring human attorney judgment. This is issue spotting, not a legal opinion. Do not launch a retry or an alternate workflow if the composed workflow fails; report the failure instead.
            """
        case "document-onboarding":
            prompt = """
            Run the saved document-onboarding workflow.

            Target document: \(selectedFile.path)
            Intake goal: \(reviewContext)

            Classify and inventory the document, check completeness, identify metadata and initial issues, and recommend exactly one next legal workflow. Do not edit the source document. Return a readable Markdown intake report titled "# Document onboarding — …" with an ## Attorney review focus checklist using `- [ ] SEVERITY — issue; action`, source references, and explicit uncertainties. Do not relabel the report as a contract review.
            """
        default:
            // Shared launch path for future Ready workflows: invoke saved YAML by id.
            prompt = """
            Run the saved \(activeWorkflow.id) workflow.

            Target document: \(selectedFile.path)
            Context: \(reviewContext)

            Execute the complete saved workflow. Do not edit the source document. Preserve source references and clearly identify limitations and issues requiring human attorney judgment. Do not launch a retry or an alternate workflow if the composed workflow fails; report the failure instead.
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

    private struct DemoSample: Identifiable {
        let id: String
        let title: String
        let relativePath: String
    }

    private func sampleDocuments(for workflowId: String) -> [DemoSample] {
        switch workflowId {
        case "document-onboarding":
            return [
                DemoSample(id: "do-incomplete", title: "Incomplete services draft", relativePath: "fixtures/onboarding/incomplete-services-agreement.md"),
                DemoSample(id: "do-lease", title: "Complete short lease", relativePath: "fixtures/onboarding/complete-short-lease.md"),
                DemoSample(id: "do-memo", title: "Routing memo", relativePath: "fixtures/onboarding/routing-memo.md"),
                DemoSample(id: "do-conflict", title: "Conflicting NDA versions", relativePath: "fixtures/onboarding/conflicting-version-nda.md"),
            ]
        case "contract-review":
            return [
                DemoSample(id: "cr-nda", title: "Mutual NDA", relativePath: "matters/contract-review/nda/example-mutual-nda.md"),
                DemoSample(id: "cr-services", title: "Services agreement", relativePath: "matters/contract-review/services-agreement/example-services-agreement.md"),
                DemoSample(id: "cr-fixture", title: "Fixture NDA", relativePath: "fixtures/example-nda.md"),
            ]
        default:
            return []
        }
    }

    private static func defaultContext(for workflowId: String) -> String {
        switch workflowId {
        case "document-onboarding":
            return "Prepare this document for legal intake. Flag blockers, missing materials, and recommend the next workflow."
        case "contract-review":
            return "Issue spotting and negotiation preparation. Identify assumptions and questions for attorney review."
        default:
            return "Identify assumptions and questions for attorney review."
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
            if trimmed.range(of: "^#{1,6}\\s+Attorney (review|intake) focus", options: [.regularExpression, .caseInsensitive]) != nil ||
                trimmed.range(of: "^#{1,6}\\s+Issues requiring attorney review", options: [.regularExpression, .caseInsensitive]) != nil {
                inQueue = true
                continue
            }
            if inQueue && trimmed.hasPrefix("#") { break }
            guard inQueue, trimmed.hasPrefix("- [") else { continue }
            let value = trimmed.replacingOccurrences(of: "^- \\[.\\]\\s*", with: "", options: .regularExpression)
            guard !value.isEmpty else { continue }
            let severity = Self.parseSeverity(from: value)
            let display = Self.stripSeverityPrefix(from: value)
            items.append(AttorneyReviewItem(id: "issue-\(items.count)-\(display)", text: display, severity: severity))
        }
        return items
    }

    private static func parseSeverity(from text: String) -> String? {
        let pattern = #"^(CRITICAL|HIGH|MEDIUM|LOW|INFO)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swiftRange]).uppercased()
    }

    private static func stripSeverityPrefix(from text: String) -> String {
        var result = text
        if let severity = parseSeverity(from: text) {
            result = String(result.dropFirst(severity.count))
        }
        result = result.trimmingCharacters(in: .whitespaces)
        if result.hasPrefix("—") || result.hasPrefix("-") || result.hasPrefix(":") {
            result = String(result.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return result.isEmpty ? text : result
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
                failureMessage = (event["error"] as? String) ?? (event["message"] as? String) ?? "The workflow failed."
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

    func approveCurrentRun(comment: String = "") {
        let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = note.isEmpty ? "Approved by human reviewer." : "Approved by human reviewer. \(note)"
        transitionCurrentRun(to: "completed", checkpointStatus: "approved", comment: full)
    }

    func requestChangesForCurrentRun(comment: String = "") {
        let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = note.isEmpty ? "Changes requested by human reviewer." : "Changes requested by human reviewer. \(note)"
        transitionCurrentRun(to: "revision_requested", checkpointStatus: "changes_requested", comment: full)
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
        let workflowId = currentRun?.workflow ?? currentWorkflow
        let escaped = comment.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\"", with: "'")
        let yaml = """
        status: \(status)
        type: attorney_review
        workflow: \(workflowId)
        updated_at: \(timestamp)
        comment: "\(escaped)"
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
