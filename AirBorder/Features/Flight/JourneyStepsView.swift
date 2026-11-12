import SwiftUI

/// Figma "Journey steps (Haneda connection)" (1041:16964): the step list behind the progress strip.
struct JourneyStepsView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let checklist = store.checklist
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Journey steps") { dismiss() }
            SectionLabel(text: (store.isAirportTransfer ? "Transfer to Narita · " : "Haneda connection · ") + (checklist.currentIndex.map { "Step \($0 + 1) of \(checklist.steps.count)" } ?? "All steps done"))
                .accessibilityIdentifier("stepCount")
            GroupedList {
                ForEach(Array(checklist.steps.enumerated()), id: \.element.id) { index, step in
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
            StepMarker(state: step.state, number: number, isCurrent: isCurrent, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).outfitText(16, .semibold)
                if step.state == .skipped {
                    Text("Not needed").outfitText(13, .regular, AB.muted)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(checklist.status(of: step))
            Spacer(minLength: 8)
            if checklist.canUndo(step.id) {
                action("Undo", id: "undo-\(step.id)") { store.undoStep() }
            } else {
                if checklist.canSkip(step.id) {
                    action("Not needed", id: "skip-\(step.id)") { store.skipStep(step.id) }
                }
                if checklist.canConfirm(step.id) {
                    action("Done", id: "confirm-\(step.id)") { store.confirmStep(step.id) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isCurrent ? Color(hex: 0xFFF7DE) : .clear)
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

/// Navy tick for done or not-needed steps, yellow number for the current step, grey for upcoming.
struct StepMarker: View {
    let state: StepState
    let number: Int
    let isCurrent: Bool
    let size: CGFloat

    var body: some View {
        let done = state != .pending
        let side = isCurrent ? max(size, 28) : size
        Text(done ? "✓" : "\(number)")
            .outfitText(isCurrent ? 13 : 12, done ? .semibold : .bold, done ? .white : (isCurrent ? AB.gateText : AB.primary))
            .frame(width: side, height: side)
            .background(done ? AB.primary : (isCurrent ? AB.gateYellow : AB.chip), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Figma "Journey progress" (1060:17026): five checkpoints from arrival to the gate.
struct JourneyProgressStrip: View {
    let checklist: JourneyChecklist

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                let count = CGFloat(checklist.steps.count)
                let column = proxy.size.width / count
                let currentX = column * (CGFloat(checklist.currentIndex ?? checklist.steps.count - 1) + 0.5)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(AB.chip).frame(width: proxy.size.width - column, height: 2).offset(x: column / 2, y: 13)
                    Rectangle().fill(AB.primary).frame(width: max(currentX - column / 2, 0), height: 2).offset(x: column / 2, y: 13)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(checklist.steps.enumerated()), id: \.element.id) { index, step in
                    let isCurrent = checklist.currentIndex == index
                    VStack(spacing: 6) {
                        StepMarker(state: step.state, number: index + 1, isCurrent: isCurrent, size: 24)
                            .frame(width: 28, height: 28)
                        Text(step.shortTitle)
                            .outfitText(11, isCurrent ? .semibold : .regular, isCurrent ? AB.navy : AB.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: 300)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("journeyProgress")
    }

    private var accessibilityText: String {
        guard let index = checklist.currentIndex else { return "All steps done" }
        return "Step \(index + 1) of \(checklist.steps.count), \(checklist.steps[index].title)"
    }
}
