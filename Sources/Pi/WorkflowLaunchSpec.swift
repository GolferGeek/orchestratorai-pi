import Foundation
import Yams

/// One launch field bound to a workflow param. Defaults come from the
/// workflow's own `params` list, so the YAML file stays the single source.
struct LaunchField: Identifiable, Hashable {
    enum Kind: String { case text, choice, line }
    let param: String
    let label: String
    let kind: Kind
    let options: [String]
    let defaultValue: String

    var id: String { param }
}

struct LaunchSample: Identifiable, Hashable {
    let id: String
    let title: String
    let relativePath: String
}

struct LaunchReviewCopy: Hashable {
    var focusTitle = "Attorney review focus"
    var focusSubtitle = "Prioritized questions for counsel. Same shared human-review checkpoint for every Ready workflow."
    var blurb = "Review the report above and record a decision before this run is marked complete."
}

/// The `orchestrator-launch` fenced block inside a saved workflow's `doc:`.
/// pi-agents ignores it (free-form documentation); the app renders it.
/// What the launch card asks for before Start: one file, a folder, or nothing
/// (the workflow is driven entirely by typed fields).
enum LaunchInputKind: String, Hashable {
    case file, folder, none
}

struct WorkflowLaunchSpec: Hashable {
    let workflowName: String
    let description: String
    var title: String
    var icon: String
    var groupId: String
    var inputKind: LaunchInputKind
    var fileLabel: String
    var fileParam: String
    var fields: [LaunchField]
    var samples: [LaunchSample]
    var review: LaunchReviewCopy
    var params: [String: String]        // declared param defaults
    var requiredParams: Set<String>

    static let fenceName = "orchestrator-launch"

    static func load(from yamlURL: URL) -> WorkflowLaunchSpec? {
        guard let text = try? String(contentsOf: yamlURL, encoding: .utf8),
              let root = try? Yams.load(yaml: text) as? [String: Any],
              let name = root["name"] as? String else { return nil }

        var defaults: [String: String] = [:]
        var required: Set<String> = []
        var order: [String] = []
        for entry in root["params"] as? [Any] ?? [] {
            if let dict = entry as? [String: Any], let param = dict["name"] as? String {
                defaults[param] = (dict["default"]).map { "\($0)" } ?? ""
                if dict["required"] as? Bool == true && dict["default"] == nil { required.insert(param) }
                order.append(param)
            } else if let param = entry as? String {
                defaults[param] = ""
                order.append(param)
            }
        }

        var spec = WorkflowLaunchSpec(
            workflowName: name,
            description: root["description"] as? String ?? "",
            title: name,
            icon: "doc.text",
            groupId: "",
            inputKind: .file,
            fileLabel: "document",
            fileParam: order.first ?? "target",
            fields: [],
            samples: [],
            review: LaunchReviewCopy(),
            params: defaults,
            requiredParams: required
        )

        guard let doc = root["doc"] as? String,
              let block = fencedBlock(named: fenceName, in: doc),
              let launch = try? Yams.load(yaml: block) as? [String: Any] else {
            return spec
        }

        if let title = launch["title"] as? String { spec.title = title }
        if let icon = launch["icon"] as? String { spec.icon = icon }
        if let group = launch["group"] as? String { spec.groupId = group }
        if let file = launch["file"] as? [String: Any] {
            if let kind = (file["kind"] as? String).flatMap(LaunchInputKind.init(rawValue:)) { spec.inputKind = kind }
            if let label = file["label"] as? String { spec.fileLabel = label }
            if let param = file["param"] as? String { spec.fileParam = param }
        } else if let none = launch["file"] as? String, none == "none" {
            spec.inputKind = .none
        }
        spec.fields = (launch["fields"] as? [Any] ?? []).compactMap { raw in
            guard let dict = raw as? [String: Any], let param = dict["param"] as? String else { return nil }
            let kind = LaunchField.Kind(rawValue: dict["kind"] as? String ?? "text") ?? .text
            return LaunchField(
                param: param,
                label: dict["label"] as? String ?? param,
                kind: kind,
                options: (dict["options"] as? [Any] ?? []).map { "\($0)" },
                defaultValue: (dict["default"]).map { "\($0)" } ?? defaults[param] ?? ""
            )
        }
        spec.samples = (launch["samples"] as? [Any] ?? []).enumerated().compactMap { index, raw in
            guard let dict = raw as? [String: Any], let path = dict["path"] as? String else { return nil }
            return LaunchSample(id: "\(name)-sample-\(index)", title: dict["title"] as? String ?? path, relativePath: path)
        }
        if let review = launch["review"] as? [String: Any] {
            if let value = review["focusTitle"] as? String { spec.review.focusTitle = value }
            if let value = review["focusSubtitle"] as? String { spec.review.focusSubtitle = value }
            if let value = review["blurb"] as? String { spec.review.blurb = value }
        }
        return spec
    }

    /// Fields that must be non-empty before Start (required workflow params bound to fields).
    var requiredFieldParams: Set<String> {
        Set(fields.map(\.param)).intersection(requiredParams)
    }

    /// Initial param values for a launch: every declared default, overlaid by field defaults.
    func initialValues() -> [String: String] {
        var values = params
        for field in fields { values[field.param] = field.defaultValue }
        return values
    }

    private static func fencedBlock(named fence: String, in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var collecting = false
        var body: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !collecting {
                if trimmed == "```\(fence)" { collecting = true }
            } else if trimmed == "```" {
                return body.joined(separator: "\n")
            } else {
                body.append(line)
            }
        }
        return nil
    }
}
