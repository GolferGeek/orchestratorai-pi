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

/// Legal's 14-workflow catalog (Phase 1–2: shared launch UI, honest Ready / Coming soon; DO + CR deepened).
enum LegalWorkflowCatalog {
    static let groups: [WorkflowGroupDefinition] = [
        WorkflowGroupDefinition(id: "document-management", name: "Document Management", sortOrder: 0),
        WorkflowGroupDefinition(id: "transactional", name: "Transactional", sortOrder: 1),
        WorkflowGroupDefinition(id: "litigation", name: "Litigation", sortOrder: 2),
        WorkflowGroupDefinition(id: "compliance-risk", name: "Compliance & Risk", sortOrder: 3),
        WorkflowGroupDefinition(id: "research-knowledge", name: "Research & Knowledge", sortOrder: 4),
    ]

    /// Canonical Legal catalog. Status is resolved against on-disk `.pi/workflows/{id}.yaml`.
    private static let seed: [(id: String, title: String, icon: String, description: String, fileLabel: String, groupId: String)] = [
        ("document-onboarding", "Document Onboarding", "doc.badge.plus",
         "Classify, inventory, check completeness, and hand counsel a prioritized intake checklist.", "document", "document-management"),
        ("contract-review", "Contract Review", "checklist",
         "Red/Blue issue spotting, arbitration, and a shared attorney-review checkpoint.", "contract", "document-management"),
        ("due-diligence", "Due Diligence", "magnifyingglass.circle",
         "Comprehensive due diligence analysis across document sets.", "document set", "transactional"),
        ("deal-memo", "Deal Memo", "doc.richtext",
         "Generate deal memos from due diligence findings.", "deal package", "transactional"),
        ("adversarial-brief", "Brief Stress Test", "flame",
         "Red-team stress testing of legal briefs and arguments.", "brief", "litigation"),
        ("discovery-review", "Discovery Review", "tray.full",
         "Document review and classification for litigation.", "document set", "litigation"),
        ("deposition-prep", "Deposition Prep", "person.wave.2",
         "Prepare witnesses and anticipate cross-examination.", "matter file", "litigation"),
        ("cross-exam-simulation", "Cross-Exam Simulation", "person.2.wave.2",
         "Simulate adversarial cross-examination scenarios.", "witness packet", "litigation"),
        ("monte-carlo-trial-simulator", "Trial Simulator", "chart.line.uptrend.xyaxis",
         "Monte Carlo simulation of trial outcomes.", "case inputs", "litigation"),
        ("persistent-case-team", "Matters", "briefcase",
         "Persistent case teams with ongoing matter management.", "matter", "litigation"),
        ("compliance-audit", "Compliance Audit", "checkmark.shield",
         "Regulatory compliance auditing against GDPR, HIPAA, SOX.", "policy pack", "compliance-risk"),
        ("sentinel", "Portfolio Sentinel", "eye",
         "Continuous monitoring of contract portfolios.", "portfolio", "compliance-risk"),
        ("legal-research", "Legal Research", "books.vertical",
         "Deep legal research with cited sources.", "research question", "research-knowledge"),
        ("kb-query", "Knowledge Base Query", "text.book.closed",
         "Ask questions against the firm knowledge base.", "query", "research-knowledge"),
    ]

    static func workflows(projectDirectory: URL) -> [WorkflowDefinition] {
        seed.map { entry in
            let yamlURL = projectDirectory
                .appendingPathComponent(".pi/workflows")
                .appendingPathComponent("\(entry.id).yaml")
            let installed = FileManager.default.fileExists(atPath: yamlURL.path)
            return WorkflowDefinition(
                id: entry.id,
                title: entry.title,
                icon: entry.icon,
                description: entry.description,
                fileLabel: entry.fileLabel,
                groupId: entry.groupId,
                status: installed ? .ready : .comingSoon
            )
        }
    }

    static func workflow(id: String, projectDirectory: URL) -> WorkflowDefinition? {
        workflows(projectDirectory: projectDirectory).first { $0.id == id }
    }
}
