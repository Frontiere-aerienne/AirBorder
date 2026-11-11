import SwiftUI

/// Figma "Add to my plan" (997:30942).
struct AddToPlanView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.popTo) private var popTo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen {
            HeaderWithBack(title: "Add to my plan") { dismiss() }
            GateChip()
            Text("Terminal 3 · Near your gate").outfitText(15, .regular, AB.secondary)
            stopCard(.cafe, detail: "Airside · \(WalkingTimes.minutes(average: 5, pace: store.pace)) min walk\nBusy · Estimated wait \(PlanStop.cafe.waitMinutes) min", extra: nil)
            stopCard(.anaLounge, detail: "Terminal 3 · 4F · Check access with your ticket", extra: ("Lounge details", { open(.anaLounge) }))
            CTAButton(title: "View my plan") { popTo(.myPlan) }
            CTAButton(title: "Check café availability", style: .outline) { open(.cafeAvailability) }
        }
    }

    private func stopCard(_ id: PlaceID, detail: String, extra: (String, () -> Void)?) -> some View {
        let stop = id == .cafe ? PlanStop.cafe : PlanStop.anaLounge
        let added = store.plan.contains(id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(stop.name).outfitText(18, .bold)
            Text(detail).outfitText(15, .regular, AB.secondary)
            CTAButton(title: added ? "Remove \(stop.shortName)" : "Add \(stop.shortName)", style: .plain, height: 47) {
                if added { store.remove(id) } else { store.add(stop) }
            }
            .accessibilityIdentifier("plan-\(id.rawValue)")
            if let extra {
                CTAButton(title: extra.0, style: .plain, height: 47, action: extra.1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Figma "Café availability" (997:31100).
struct CafeAvailabilityView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.popTo) private var popTo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen {
            HeaderWithBack(title: "Café availability") { dismiss() }
            GateChip()
            Text("Curacion Cafe · Terminal 3").outfitText(15, .regular, AB.secondary)
            NavyCard(title: "Busy now", detail: "Estimated wait \(PlanStop.cafe.waitMinutes) min")
            InfoCard(padding: 16, radius: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check your plan timing").outfitText(18, .bold)
                    Text("Allow \(PlanStop.cafe.waitMinutes) min waiting and a \(PlanStop.cafe.visitMinutes)-minute visit, plus walking time. Review your gate-arrival time before adding this stop.")
                        .outfitText(15, .regular, AB.secondary)
                }
            }
            CTAButton(title: store.plan.contains(.cafe) ? "Café is in your plan" : "Add café to plan") {
                store.add(.cafe)
                popTo(.myPlan)
            }
            CTAButton(title: "Check another option", style: .outline) { dismiss() }
        }
    }
}

/// Figma "Route through your stops" (997:30967), "Route via Curacion Cafe" (997:30988), "Route via ANA LOUNGE" (997:31009).
struct RouteThroughStopsView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.popToRoot) private var popToRoot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let schedule = store.schedule
        let title = schedule.stops.count == 1 ? "Route via \(schedule.stops[0].stop.name)" : "Route through your stops"
        var lines = ["You are at T3, 3F"]
        for (index, item) in schedule.stops.enumerated() {
            lines.append("\(index + 1). \(item.stop.name) · \(item.walkFromPrevious) min walk")
        }
        lines.append("\(schedule.stops.count + 1). your gate · \(schedule.walkToGate) min walk")
        return SubScreen {
            HeaderWithBack(title: title) { dismiss() }
            GateChip()
            Text("Haneda · Terminal 3").outfitText(15, .regular, AB.secondary)
            InfoCard(padding: 16, radius: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your route").outfitText(18, .bold)
                    Text(lines.joined(separator: "\n")).outfitText(15, .regular, AB.secondary)
                }
            }
            .accessibilityIdentifier("stopsRoute")
            NavyCard(title: "Gate arrival", detail: "Arrive by \(schedule.arriveAtGate). Gate closes at \(schedule.gateCloses).")
            CTAButton(title: "Open terminal map") {
                popToRoot()
                store.tab = .route
            }
            CTAButton(title: "Compare routes", style: .outline) { open(.routeOptions) }
            CTAButton(title: "My plan", style: .plain) { dismiss() }
        }
    }
}

/// Figma "Step-free route" (997:31058) and "Less crowded route" (997:31079).
struct RouteDetailView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.popToRoot) private var popToRoot
    @Environment(\.dismiss) private var dismiss
    let choice: RouteChoice

    var body: some View {
        let minutes = store.gateWalkMinutes(for: choice)
        let extra = minutes - store.gateWalkMinutes(for: .direct)
        SubScreen {
            HeaderWithBack(title: "\(choice.title) route") { dismiss() }
            GateChip()
            Text("your gate · Estimated \(minutes) min").outfitText(15, .regular, AB.secondary)
            InfoCard(padding: 16, radius: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(choice == .stepFree ? "Follow the level route" : "Avoid the central corridor").outfitText(18, .bold)
                    Text(choice == .stepFree ? "Use the lift at the terminal junction. Continue toward Gates 105–109." : "Follow the outer concourse toward Gates 105–109.")
                        .outfitText(15, .regular, AB.secondary)
                }
            }
            if choice == .stepFree {
                NavyCard(title: "Before you leave", detail: "Lift availability may change. Check airport signs if access is blocked.")
            } else {
                NavyCard(title: "Timing updated", detail: "Allow \(extra) extra minutes. Leave by \(SampleJourney.gateArrivalTarget - minutes) to arrive by \(SampleJourney.gateArrivalTarget).")
            }
            CTAButton(title: "View terminal map") {
                store.routeChoice = choice
                store.routeStep = 1
                popToRoot()
                store.tab = .route
            }
            CTAButton(title: "Compare routes", style: .outline) { dismiss() }
            CTAButton(title: "My plan", style: .plain) { open(.myPlan) }
        }
    }
}

/// Figma "Open another map" (997:31156).
struct OpenAnotherMapView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.openURL) private var openURL
    @Environment(\.popToRoot) private var popToRoot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen {
            HeaderWithBack(title: "Open another map") { dismiss() }
            GateChip()
            Text("Keep your gate route in AirBorder").outfitText(15, .regular, AB.secondary)
            NavyCard(title: "Indoor directions", detail: "Other map apps may not show every gate or indoor passage. AirBorder keeps your plan available.")
            CTAButton(title: "Google Maps", style: .outline) {
                if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=Haneda+Airport+Terminal+3") { openURL(url) }
            }
            CTAButton(title: "Apple Maps", style: .outline) {
                if let url = URL(string: "https://maps.apple.com/?q=Haneda+Airport+Terminal+3") { openURL(url) }
            }
            CTAButton(title: "Continue in AirBorder") {
                popToRoot()
                store.tab = .route
            }
            CTAButton(title: "My plan", style: .plain) { open(.myPlan) }
        }
    }
}

/// Flight tab plan card once stops are added (Figma "Flight (Plan: …)", 858:8502).
struct AddedPlanCard: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open

    var body: some View {
        let schedule = store.schedule
        let stops = schedule.stops
        let leave = stops.isEmpty ? TerminalTwo.leaveBy(gateWalk: store.gateWalkMinutes) : schedule.leave
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if stops.count == 1, stops[0].stop.id == .anaLounge {
                    AirlineBadge(airline: .ana)
                    Text("LOUNGE").outfitText(17, .semibold)
                } else {
                    Text(stops.isEmpty ? "T2 Observation Deck" : stops.map(\.stop.name).joined(separator: " · "))
                        .outfitText(17, .semibold).lineLimit(2)
                }
                Spacer()
                circle(image: nil, label: "Edit plan") { open(.myPlan) }
                circle(image: "icClosePlan", label: "Remove plan") {
                    for item in stops { store.remove(item.stop.id) }
                    store.t2VisitPlanned = false
                }
            }
            timeline(leave: leave, arrive: stops.isEmpty ? SampleJourney.gateArrivalTarget : schedule.arriveAtGate, closes: schedule.gateCloses)
        }
        .padding(24)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AB.border, lineWidth: 1))
        .accessibilityIdentifier("addedPlanCard")
    }

    private func circle(image: String?, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let image {
                    Image(image).resizable().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(AB.ticket)
                }
            }
            .frame(width: 36, height: 36)
            .background(AB.chip, in: Circle())
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func timeline(leave: ClockTime, arrive: ClockTime, closes: ClockTime) -> some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 320
            ZStack(alignment: .topLeading) {
                Rectangle().fill(AB.primary).frame(width: 180 * scale, height: 3).offset(y: 3)
                Rectangle().fill(AB.primary.opacity(0.3)).frame(width: 116 * scale, height: 3).offset(x: 180 * scale, y: 3)
                point("Now", SampleJourney.now, x: 0, filled: true)
                point("Leave", leave, x: 175 * scale, filled: true)
                point("At gate", arrive, x: 233 * scale, filled: false)
                Image("icGate").resizable().frame(width: 24, height: 24).offset(x: 300 * scale, y: -4)
                Text(closes.description).outfitText(13, .semibold).offset(x: 296 * scale, y: 18)
            }
        }
        .frame(height: 48)
    }

    private func point(_ label: String, _ time: ClockTime, x: CGFloat, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle().fill(filled ? AB.primary : .white).overlay(Circle().strokeBorder(AB.primary, lineWidth: 1.5)).frame(width: 10, height: 10)
            VStack(spacing: 0) {
                Text(time.description).outfitText(13, .semibold)
                Text(label).outfitText(11, .regular, AB.muted)
            }
            .offset(x: x == 0 ? 0 : -11)
        }
        .offset(x: x)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(time)")
    }
}
