import SwiftUI

/// What the left column is pointing at: the cross-workflow inbox, or one catalog entry.
enum SidebarSelection: Hashable {
    case inbox
    case workflow(String)

    var workflowId: String? {
        if case .workflow(let id) = self { return id }
        return nil
    }
}

/// Left column: a pinned Inbox row plus the Legal catalog grouped by practice area.
/// The catalog rows carry only a title, icon, and install badge — the detail card
/// already shows the description, so the sidebar stays scannable at 14 entries.
struct SidebarView: View {
    @ObservedObject var runner: PiRunner
    let workflows: [WorkflowDefinition]
    @Binding var selection: SidebarSelection?
    @Binding var expandedGroups: Set<String>
    @AppStorage("showComingSoon") private var showComingSoon = false

    private var inboxCount: Int {
        runner.attentionRuns.count
    }

    private var visibleWorkflows: [WorkflowDefinition] {
        showComingSoon ? workflows : workflows.filter { $0.status == .ready }
    }

    var body: some View {
        // The List must be the column root so it receives the toolbar/title inset;
        // wrapping it in a VStack pushed the Inbox row under the window controls.
        List(selection: $selection) {
            Section {
                inboxRow
            }

            ForEach(LegalWorkflowCatalog.groups) { group in
                let items = visibleWorkflows.filter { $0.groupId == group.id }
                if !items.isEmpty {
                    Section(isExpanded: groupBinding(group.id)) {
                        ForEach(items) { workflow in
                            workflowRow(workflow)
                        }
                    } header: {
                        Text(group.name)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Toggle("Show coming soon", isOn: $showComingSoon)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                    .accessibilityIdentifier("sidebar.show_coming_soon")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.bar)
        }
        .navigationTitle("Workflows")
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
    }

    private var inboxRow: some View {
        HStack(spacing: 6) {
            Label("Inbox", systemImage: "tray.full")
            Spacer(minLength: 0)
            if inboxCount > 0 {
                Text("\(inboxCount)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .frame(minWidth: 26)
                    .background(Color.orange.opacity(0.22))
                    .foregroundStyle(Color.orange)
                    .clipShape(Capsule())
                    .padding(.trailing, 2)
            }
        }
        .tag(SidebarSelection.inbox)
        .accessibilityIdentifier("sidebar.inbox")
    }

    private func workflowRow(_ workflow: WorkflowDefinition) -> some View {
        HStack(spacing: 6) {
            Label(workflow.title, systemImage: workflow.icon)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(workflow.status.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(workflow.isReady ? Color.green.opacity(0.18) : Color.secondary.opacity(0.14))
                .foregroundStyle(workflow.isReady ? Color.green : Color.secondary)
                .clipShape(Capsule())
        }
        .tag(SidebarSelection.workflow(workflow.id))
        .accessibilityIdentifier("sidebar.workflow.\(workflow.id)")
    }

    private func groupBinding(_ groupId: String) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(groupId) },
            set: { expanded in
                if expanded {
                    expandedGroups.insert(groupId)
                } else {
                    expandedGroups.remove(groupId)
                }
            }
        )
    }
}
