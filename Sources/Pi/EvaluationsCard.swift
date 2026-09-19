import SwiftUI

/// Card listing the Jev rubric checks ("guards") recorded against the displayed run.
/// Visual conventions mirror `attorneyReviewCard` in PiApp.swift.
struct EvaluationsCard: View {
    let evaluations: [EvaluationRecord]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Guards", systemImage: "checkmark.shield")
                        .font(.headline)
                    Spacer()
                    if !evaluations.isEmpty {
                        Text("\(evaluations.count) rubric check\(evaluations.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if evaluations.isEmpty {
                    Text("No rubric checks ran on this run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(evaluations) { evaluation in
                            EvaluationRow(evaluation: evaluation)
                                .accessibilityIdentifier("evaluations.row.\(evaluation.id)")
                            if evaluation.id != evaluations.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
        .accessibilityIdentifier("evaluations.card")
    }
}

private struct EvaluationRow: View {
    let evaluation: EvaluationRecord
    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DecisionBadge(decision: evaluation.decision)
                Text(evaluation.rubric)
                    .font(.callout.weight(.semibold))
                Text("v\(evaluation.rubricVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.displayTime(evaluation.at))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let reason = evaluation.reason, !reason.isEmpty {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }

            if !evaluation.answers.isEmpty {
                Text(evaluation.answers.map(\.headline).joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let model = evaluation.model, !model.isEmpty {
                Text(model + tokenSuffix)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let preview = evaluation.statePreview, !preview.isEmpty {
                DisclosureGroup(isExpanded: $showPreview) {
                    ScrollView([.vertical, .horizontal]) {
                        Text(preview)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 160)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } label: {
                    Text("Evaluated text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var tokenSuffix: String {
        guard let input = evaluation.inputTokens, let output = evaluation.outputTokens else { return "" }
        return " · \(input) in / \(output) out"
    }

    private static func displayTime(_ value: String) -> String {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = withFraction.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return value }
        let display = DateFormatter()
        display.dateFormat = "HH:mm:ss"
        return display.string(from: date)
    }
}

/// Capsule for a Jev decision (`block` / `review` / `pass`); reusable in run lists.
struct DecisionBadge: View {
    let decision: String

    var body: some View {
        Text(decision.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18))
            .foregroundStyle(tint)
            .clipShape(Capsule())
            .accessibilityIdentifier("evaluations.badge.\(decision)")
    }

    private var tint: Color {
        switch decision.lowercased() {
        case "block": return .red
        case "review": return .orange
        case "pass": return .green
        default: return .secondary
        }
    }
}
