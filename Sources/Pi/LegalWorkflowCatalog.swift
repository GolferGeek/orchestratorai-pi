import Foundation

/// Honest install status for Legal catalog entries.
enum WorkflowInstallStatus: String, Hashable {
    case ready
    case comingSoon

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .comingSoon: return "Coming soon"
        }
    }
}

struct WorkflowGroupDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let sortOrder: Int
}

struct WorkflowDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let description: String
    let groupId: String
    let status: WorkflowInstallStatus
    /// Present only when `.pi/workflows/{id}.yaml` exists; carries the launch UI.
    let launch: WorkflowLaunchSpec?

    var isReady: Bool { status == .ready && launch != nil }
    var fileLabel: String { launch?.fileLabel ?? "document" }
}

/// Legal's 14-workflow product registry. Titles, icons, and descriptions for
/// Ready entries are overridden by the workflow YAML's own launch block, so the
/// registry only has to be right about *what we offer*, not how each launches.
enum LegalWorkflowCatalog {
    static let groups: [WorkflowGroupDefinition] = [
        WorkflowGroupDefinition(id: "document-management", name: "Document Management", sortOrder: 0),
        WorkflowGroupDefinition(id: "transactional", name: "Transactional", sortOrder: 1),
        WorkflowGroupDefinition(id: "litigation", name: "Litigation", sortOrder: 2),
        WorkflowGroupDefinition(id: "compliance-risk", name: "Compliance & Risk", sortOrder: 3),
        WorkflowGroupDefinition(id: "research-knowledge", name: "Research & Knowledge", sortOrder: 4),
    ]

    private static let seed: [(id: String, title: String, icon: String, description: String, groupId: String)] = [
        ("document-onboarding", "Document Onboarding", "doc.badge.plus",
         "Classify, inventory, check completeness, and hand counsel a prioritized intake checklist.", "document-management"),
        ("contract-review", "Contract Review", "checklist",
         "Red/Blue issue spotting, arbitration, and a shared attorney-review checkpoint.", "document-management"),
        ("due-diligence", "Due Diligence", "magnifyingglass.circle",
         "Comprehensive due diligence analysis across document sets.", "transactional"),
        ("deal-memo", "Deal Memo", "doc.richtext",
         "Generate deal memos from due diligence findings.", "transactional"),
        ("adversarial-brief", "Brief Stress Test", "flame",
         "Red-team stress testing of legal briefs and arguments.", "litigation"),
        ("discovery-review", "Discovery Review", "tray.full",
         "Document review and classification for litigation.", "litigation"),
        ("deposition-prep", "Deposition Prep", "person.wave.2",
         "Prepare witnesses and anticipate cross-examination.", "litigation"),
        ("cross-exam-simulation", "Cross-Exam Simulation", "person.2.wave.2",
         "Simulate adversarial cross-examination scenarios.", "litigation"),
        ("monte-carlo-trial-simulator", "Trial Simulator", "chart.line.uptrend.xyaxis",
         "Monte Carlo simulation of trial outcomes.", "litigation"),
        ("persistent-case-team", "Matters", "briefcase",
         "Persistent case teams with ongoing matter management.", "litigation"),
        ("compliance-audit", "Compliance Audit", "checkmark.shield",
         "Regulatory compliance auditing against GDPR, HIPAA, SOX.", "compliance-risk"),
        ("sentinel", "Portfolio Sentinel", "eye",
         "Continuous monitoring of contract portfolios.", "compliance-risk"),
        ("legal-research", "Legal Research", "books.vertical",
         "Deep legal research with cited sources.", "research-knowledge"),
        ("kb-query", "Knowledge Base Query", "text.book.closed",
         "Ask questions against the firm knowledge base.", "research-knowledge"),
    ]

    static func workflows(projectDirectory: URL) -> [WorkflowDefinition] {
        let workflowsDir = projectDirectory.appendingPathComponent(".pi/workflows")
        var definitions = seed.map { entry -> WorkflowDefinition in
            let yamlURL = workflowsDir.appendingPathComponent("\(entry.id).yaml")
            let launch = FileManager.default.fileExists(atPath: yamlURL.path) ? WorkflowLaunchSpec.load(from: yamlURL) : nil
            return WorkflowDefinition(
                id: entry.id,
                title: launch?.title ?? entry.title,
                icon: launch?.icon ?? entry.icon,
                description: launch.map { $0.description.isEmpty ? entry.description : $0.description } ?? entry.description,
                groupId: launch.flatMap { $0.groupId.isEmpty ? nil : $0.groupId } ?? entry.groupId,
                status: launch == nil ? .comingSoon : .ready,
                launch: launch
            )
        }

        // Any additional project workflow that carries a launch block is offered too,
        // so a Mac user who authors their own YAML sees it without touching the app.
        let known = Set(definitions.map(\.id))
        let extra = ((try? FileManager.default.contentsOfDirectory(at: workflowsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "yaml" || $0.pathExtension == "yml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in extra {
            let id = url.deletingPathExtension().lastPathComponent
            guard !known.contains(id), let launch = WorkflowLaunchSpec.load(from: url), !launch.groupId.isEmpty else { continue }
            definitions.append(WorkflowDefinition(
                id: id, title: launch.title, icon: launch.icon, description: launch.description,
                groupId: launch.groupId, status: .ready, launch: launch
            ))
        }
        return definitions
    }

    static func workflow(id: String, projectDirectory: URL) -> WorkflowDefinition? {
        workflows(projectDirectory: projectDirectory).first { $0.id == id }
    }
}
