import SwiftUI

/// Figma "My plan" (997:30851), empty state (997:30924), suggested change (1040:16965)
/// and applied change with Undo (1040:16935).
struct MyPlanView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.popToRoot) private var popToRoot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let schedule = store.schedule
        ZStack(alignment: .bottom) {
            SubScreen {
                HeaderWithBack(title: "My plan") { dismiss() }
                GateChip()
                Text(schedule.stops.isEmpty ? "No stops added yet" : "Haneda · Terminal 3 · your gate")
                    .outfitText(15, .regular, AB.secondary)
                if schedule.stops.isEmpty {
                    emptyPlan(schedule)
                } else {
                    if let suggestion = store.suggestion {
                        NavyCard(title: suggestion.title, detail: suggestion.detail)
                            .accessibilityIdentifier("suggestion")
                        CTAButton(title: "Apply") { store.applySuggestion() }
                            .accessibilityIdentifier("applySuggestion")
                        CTAButton(title: "Keep my plan", style: .outline) { store.keepPlan() }
                            .accessibilityIdentifier("keepPlan")
                    }
                    ForEach(Array(schedule.stops.enumerated()), id: \.element.stop.id) { index, item in
                        StopCard(number: index + 1, item: item, onOpen: { open(.editStop(item.stop.id)) }) {
                            store.remove(item.stop.id)
                        }
                    }
                    NavyCard(title: PlanText.arrivalTitle(schedule), detail: PlanText.arrivalDetail(schedule))
                        .accessibilityIdentifier("arrivalCard")
                    if store.suggestion == nil {
                        CTAButton(title: "View route through stops") { open(.routeThroughStops) }
                        CTAButton(title: "Add a stop", style: .outline) { open(.addToPlan) }
                        CTAButton(title: "Flight home", style: .plain) { popToRoot() }
                    }
                }
            }
            if store.undoPlan != nil {
                UndoToast(message: "Plan updated") { store.undoSuggestion() }
                    .padding(.bottom, 16)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(8))
                        store.clearUndo()
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.undoPlan != nil)
    }

    @ViewBuilder
    private func emptyPlan(_ schedule: Schedule) -> some View {
        InfoCard(padding: 16, radius: 16, background: AB.ticket) {
            Text("Go straight to your gate").outfitText(18, .bold, AB.card)
            Text("your gate · Terminal \(SampleJourney.outbound.departureTerminal)").outfitText(15, .regular, AB.card)
            Text("Estimated walk \(schedule.walkToGate) min · Arrive by \(schedule.arriveAtGate)").outfitText(15, .regular, AB.card)
        }
        .accessibilityIdentifier("arrivalCard")
        CTAButton(title: "Add a stop", style: .outline) { open(.addToPlan) }
        CTAButton(title: "View gate map") { store.tab = .route }
        CTAButton(title: "Flight home", style: .plain) { popToRoot() }
    }
}

struct GateChip: View {
    var body: some View {
        Text("Gate \(SampleJourney.outbound.departureGate)").outfitText(18, .semibold, AB.gateText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AB.gateYellow, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct NavyCard: View {
    let title: String
    let detail: String

    var body: some View {
        InfoCard(padding: 16, radius: 16, background: AB.ticket) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).outfitText(18, .bold, AB.card)
                Text(detail).outfitText(15, .regular, AB.card)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// White stop card: tap to edit, or remove.
struct StopCard: View {
    let number: Int
    let item: ScheduledStop
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(number). \(item.stop.name)").outfitText(18, .bold)
                    Text(PlanText.timing(item)).outfitText(15, .regular, AB.secondary)
                    if number > 1, let walk = PlanText.walk(item) {
                        Text(walk).outfitText(15, .regular, AB.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit stop")
            .accessibilityIdentifier("stop-\(item.stop.id.rawValue)")
            CTAButton(title: "Remove \(item.stop.shortName)", style: .plain, height: 47, action: onRemove)
                .accessibilityIdentifier("remove-\(item.stop.id.rawValue)")
        }
        .padding(16)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Figma "Edit stop (Curacion Cafe)" (1039:16957).
struct EditStopView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss
    let stopID: PlaceID
    @State private var draft: Plan?

    var body: some View {
        let plan = draft ?? store.plan
        let schedule = PlanEngine.schedule(plan, pace: store.pace)
        SubScreen {
            HeaderWithBack(title: "Edit stop") { dismiss() }
            GateChip()
            if let index = plan.index(of: stopID) {
                let stop = plan.stops[index]
                Text("\(index + 1). \(stop.name) · Terminal \(SampleJourney.outbound.departureTerminal)")
                    .outfitText(15, .regular, AB.secondary)
                OptionCard(title: "Visit length", detail: visitDetail(stop), action: lengthAction(stop)) {
                    edit { $0.stops[index].visitMinutes = lengthTarget(stop) }
                }
                if plan.stops.count > 1 {
                    OptionCard(title: "Order", detail: orderDetail(plan, index), action: orderAction(plan, index)) {
                        edit { plan in
                            let moved = plan.stops.remove(at: index)
                            plan.stops.insert(moved, at: index == 0 ? plan.stops.count : 0)
                        }
                    }
                }
                NavyCard(title: PlanText.arrivalTitle(schedule), detail: PlanText.arrivalDetail(schedule))
                    .accessibilityIdentifier("editArrival")
                CTAButton(title: "Save") {
                    if let draft { store.replacePlan(with: draft) }
                    dismiss()
                }
                .accessibilityIdentifier("saveStop")
                CTAButton(title: "Remove \(stop.shortName)", style: .outline) {
                    store.remove(stopID)
                    dismiss()
                }
            }
        }
    }

    private func edit(_ change: (inout Plan) -> Void) {
        var plan = draft ?? store.plan
        change(&plan)
        draft = plan
    }

    private func visitDetail(_ stop: PlanStop) -> String {
        stop.waitMinutes > 0 ? "\(stop.visitMinutes) min · plus about \(stop.waitMinutes) min wait" : "\(stop.visitMinutes) min"
    }

    private func original(_ stop: PlanStop) -> Int {
        store.plan.stops.first { $0.id == stop.id }?.visitMinutes ?? stop.visitMinutes
    }

    /// Offers 5 minutes shorter, or back to the saved length once shortened.
    private func lengthTarget(_ stop: PlanStop) -> Int {
        stop.visitMinutes < original(stop) ? original(stop) : stop.visitMinutes - 5
    }

    private func lengthAction(_ stop: PlanStop) -> String? {
        let target = lengthTarget(stop)
        if target > stop.visitMinutes { return "Back to \(target) min" }
        return target >= PlanEngine.minimumVisit ? "Shorten to \(target) min" : nil
    }

    private func orderDetail(_ plan: Plan, _ index: Int) -> String {
        let other = plan.stops[index == 0 ? 1 : index - 1].name
        return index == 0 ? "First stop, before \(other)" : "Last stop, after \(other)"
    }

    private func orderAction(_ plan: Plan, _ index: Int) -> String {
        let other = plan.stops[index == 0 ? 1 : index - 1].name
        return index == 0 ? "Move after \(other)" : "Move before \(other)"
    }
}

private struct OptionCard: View {
    let title: String
    let detail: String
    let action: String?
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).outfitText(18, .bold)
            Text(detail).outfitText(15, .regular, AB.secondary)
            if let action {
                CTAButton(title: action, style: .plain, height: 47, action: perform)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
