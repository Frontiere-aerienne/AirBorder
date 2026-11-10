import SwiftUI

/// Figma "Journey steps (Haneda connection)" (1041:16964): departure-to-arrival checkpoints.
struct JourneyStepsView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Journey steps") { dismiss() }
            SectionLabel(text: "Connection at Haneda")
            GroupedList {
                ForEach(Array(store.checklist.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { RowDivider() }
                    row(step, number: index + 1)
                }
            }
        }
    }

    private func row(_ step: JourneyStep, number: Int) -> some View {
        let checklist = store.checklist
        let isCurrent = checklist.current?.id == step.id
        return HStack(spacing: 14) {
            marker(step, number: number, isCurrent: isCurrent)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).outfitText(16, .semibold)
                Text(checklist.status(of: step)).outfitText(13, .regular, AB.muted)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if checklist.canUndo(step.id) {
                action("Undo", id: "undo-\(step.id)") { store.undoStep() }
            } else {
                if checklist.canSkip(step.id) {
                    action("Not needed", id: "skip-\(step.id)") { store.skipStep(step.id) }
                }
                if checklist.canConfirm(step.id) {
                    action("Confirm", id: "confirm-\(step.id)") { store.confirmStep(step.id) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func marker(_ step: JourneyStep, number: Int, isCurrent: Bool) -> some View {
        let done = step.state != .pending
        let background: Color = done ? AB.primary : (isCurrent ? AB.gateYellow : AB.chip)
        let foreground: Color = done ? .white : (isCurrent ? AB.gateText : AB.primary)
        return Text(done ? "✓" : "\(number)")
            .outfitText(13, .bold, foreground)
            .frame(width: 28, height: 28)
            .background(background, in: Circle())
            .accessibilityHidden(true)
    }

    private func action(_ title: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).outfitText(15, .semibold, AB.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
