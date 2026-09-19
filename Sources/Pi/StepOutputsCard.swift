import SwiftUI

/// Completed top-level steps of an interrupted run. This is the "edit state at a
/// checkpoint" surface: an attorney can replace a step's output before resuming,
/// and the extension re-binds the edited value instead of the stored one.
struct StepOutputsCard: View {
    let run: RunRecord
    let steps: [RunStore.StepOutput]
    let onResume: () -> Void
    let onOverride: (Int, String) -> Void
    let onClearOverride: (Int) -> Void

    @State private var editing: RunStore.StepOutput?
    @State private var draft = ""

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Resume from checkpoint", systemImage: "arrow.clockwise.circle")
                        .font(.headline)
                    Spacer()
                    Text(run.resumes > 0 ? "resumed \(run.resumes)×" : "\(steps.count) step\(steps.count == 1 ? "" : "s") completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("The completed steps below are kept in the store. Resume re-binds them and runs the rest of the workflow; a step that was mid-way (a loop, a waiting gate) re-runs, and a gate the attorney already decided is picked back up. Edit a step's output first to steer the remainder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if steps.isEmpty {
                    Text("No step finished before the run stopped; resume restarts from the first step.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: step.isOverridden ? "pencil.circle.fill" : "checkmark.circle")
                                .foregroundStyle(step.isOverridden ? Color.orange : Color.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Step \(step.stepIndex + 1) · \(step.label)")
                                    .font(.caption.weight(.semibold))
                                Text(step.valueText.prefix(160).replacingOccurrences(of: "\n", with: " ") + (step.valueText.count > 160 ? "…" : ""))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Button("Edit") {
                                draft = step.valueText
                                editing = step
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .accessibilityIdentifier("resume.step.\(step.stepIndex).edit")
                            if step.isOverridden {
                                Button("Revert") { onClearOverride(step.stepIndex) }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                    .accessibilityIdentifier("resume.step.\(step.stepIndex).revert")
                            }
                        }
                    }
                }

                Button {
                    onResume()
                } label: {
                    Label("Resume workflow", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("run.resume")
            }
            .padding(8)
        }
        .accessibilityIdentifier("resume.card")
        .sheet(item: $editing) { step in
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit output of step \(step.stepIndex + 1) · \(step.label)")
                    .font(.headline)
                Text("Resume will hand this text to the remaining steps instead of the stored output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 640, minHeight: 360)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .accessibilityIdentifier("resume.step.editor")
                HStack {
                    Spacer()
                    Button("Cancel") { editing = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Save override") {
                        onOverride(step.stepIndex, draft)
                        editing = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("resume.step.save")
                }
            }
            .padding(20)
        }
    }
}
