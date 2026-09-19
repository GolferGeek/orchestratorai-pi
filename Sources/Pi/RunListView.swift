import SwiftUI

/// Middle column: the runs for the sidebar's current selection, searchable and
/// grouped by what the attorney needs to do with them.
struct RunListView: View {
    @ObservedObject var runner: PiRunner
    let selection: SidebarSelection?
    /// The catalog entry behind `selection` when it is a workflow (nil for Inbox).
    let workflow: WorkflowDefinition?
    let onOpen: (RunRecord) -> Void
    let onNewRun: () -> Void
    let onDelete: (RunRecord) -> Void
    let onClearApproved: ([RunRecord]) -> Void

    @State private var searchText = ""

    private struct RunSection: Identifiable {
        let id: String
        let title: String
        let runs: [RunRecord]
    }

    // MARK: Data

    /// Runs in scope before the search box is applied.
    private var scopedRuns: [RunRecord] {
        switch selection {
        case .workflow(let id):
            return runner.runs.filter { $0.workflow == id }
        case .inbox, nil:
            return runner.runs
        }
    }

    private var filteredRuns: [RunRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return scopedRuns }
        return scopedRuns.filter { run in
            run.title.lowercased().contains(query)
                || run.workflow.lowercased().contains(query)
                || runner.reviewState(for: run).label.lowercased().contains(query)
        }
    }

    private var sections: [RunSection] {
        var attention: [RunRecord] = []
        var approved: [RunRecord] = []
        var other: [RunRecord] = []
        for run in filteredRuns {
            let state = runner.reviewState(for: run)
            if state.needsAttention || state.isLive {
                attention.append(run)
            } else if state == .approved {
                approved.append(run)
            } else {
                other.append(run)
            }
        }
        return [
            RunSection(id: "attention", title: "Needs attention", runs: attention),
            RunSection(id: "approved", title: "Approved", runs: approved),
            RunSection(id: "other", title: "Other", runs: other),
        ].filter { !$0.runs.isEmpty }
    }

    private var approvedInScope: [RunRecord] {
        filteredRuns.filter { runner.reviewState(for: $0) == .approved }
    }

    private var listSelection: Binding<String?> {
        Binding(
            get: { runner.selectedRunId },
            set: { id in
                guard let id, let run = runner.runs.first(where: { $0.id == id }) else { return }
                onOpen(run)
            }
        )
    }

    private var title: String {
        switch selection {
        case .inbox, nil: return "Inbox"
        case .workflow: return workflow?.title ?? "Runs"
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search runs", text: $searchText)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("runs.search")
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("runs.search.clear")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

                if let workflow, selection?.workflowId != nil, workflow.isReady {
                    Button {
                        onNewRun()
                    } label: {
                        Label("New run", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("runs.new_run")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if scopedRuns.isEmpty {
                emptyState("No runs yet", systemImage: "tray")
            } else if filteredRuns.isEmpty {
                emptyState("No matches", systemImage: "magnifyingglass")
            } else {
                List(selection: listSelection) {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.runs) { run in
                                runRow(run)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text("\(filteredRuns.count) of \(scopedRuns.count) runs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onClearApproved(approvedInScope)
                } label: {
                    Label("Clear approved", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(approvedInScope.isEmpty)
                .help("Delete every approved run in this list")
                .accessibilityIdentifier("runs.clear_approved")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle(title)
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 440)
    }

    private func runRow(_ run: RunRecord) -> some View {
        let state = runner.reviewState(for: run)
        return HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(dotColor(for: state))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.title)
                    .font(.callout.weight(run.id == runner.selectedRunId ? .semibold : .regular))
                    .lineLimit(1)
                Text("\(state.label) · \(ContentView.displayDate(run.completedAt ?? run.createdAt))")
                    .font(.caption2)
                    .foregroundStyle(state.isLive ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // Worst Jev guard decision on this run, if any rubric ran.
            if let decision = runner.worstDecision(for: run.id) {
                DecisionBadge(decision: decision)
            }
            Button {
                onDelete(run)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete this run and its journal")
            .accessibilityIdentifier("runs.row.\(run.id).delete")
        }
        .padding(.vertical, 2)
        .tag(run.id)
        .accessibilityIdentifier("runs.row.\(run.id)")
    }

    private func dotColor(for state: ReviewState) -> Color {
        if state.isLive { return .orange }
        if state.needsAttention { return state == .failed ? .red : .orange }
        if state == .approved { return .green }
        return .secondary
    }

    private func emptyState(_ message: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
