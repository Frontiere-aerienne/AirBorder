import SwiftUI

/// Figma "Flight" (858:10400).
struct FlightView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(spacing: 8) {
                    titleRow
                    TicketCard(flight: SampleJourney.outbound, previous: SampleJourney.inbound)
                    links
                }
                planSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 49)
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var titleRow: some View {
        HStack {
            Text("Your flight").outfitText(30, .bold).tracking(-1).accessibilityAddTraits(.isHeader)
            Spacer()
            Button { open(.addFlight) } label: {
                Image("icPlusDark").resizable().frame(width: 20, height: 20)
                    .frame(width: 44, height: 44)
                    .background(AB.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a flight")
            .accessibilityIdentifier("addFlight")
        }
        .frame(height: 44)
        .padding(.bottom, 24)
    }

    private var links: some View {
        HStack(spacing: 24) {
            TextLink(title: "Journey details") { open(.journeyDetails) }
                .accessibilityIdentifier("journeyDetailsLink")
            TextLink(title: "My plan") { open(.myPlan) }
                .accessibilityIdentifier("myPlanLink")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var planSection: some View {
        let schedule = store.schedule
        let gate = SampleJourney.outbound
        let untilClose = (gate.gateCloses ?? SampleJourney.gateArrivalTarget) - SampleJourney.now
        let firstLeave = schedule.stops.first.map { $0.start - $0.walkFromPrevious } ?? schedule.leave
        return VStack(alignment: .leading, spacing: 16) {
            Text("Your plan").outfitText(30, .bold).tracking(-1).accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                TimeChip(text: durationText(untilClose))
                Text("before").outfitText(22, .regular, AB.muted)
                GateSign(gate: gate.departureGate, size: 18)
                Text("closes.").outfitText(22, .regular, AB.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(durationText(untilClose)) before Gate \(gate.departureGate) closes.")
            Button { store.tab = .route } label: {
                HStack(spacing: 9) {
                    Image("icWalkWhite").resizable().frame(width: 21, height: 21)
                    Text("Route").outfitText(14, .semibold, .white)
                }
                .frame(width: 280, height: 48)
                .background(AB.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityIdentifier("routeButton")
            PlanCard(spare: firstLeave - SampleJourney.now, leave: firstLeave, arrive: schedule.arriveAtGate, closes: schedule.gateCloses) {
                store.tab = .layover
            }
        }
    }
}

/// Countdown shown like a departure board (Figma "Time chip").
struct TimeChip: View {
    let text: String
    var body: some View {
        Text(text).outfitText(20, .semibold, AB.ice)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Figma "Plan card": time to spare and the timeline to the gate.
struct PlanCard: View {
    let spare: Int
    let leave: ClockTime
    let arrive: ClockTime
    let closes: ClockTime
    let addStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(durationText(spare)).outfitText(28, .bold)
                Text("to spare").outfitText(17, .light)
            }
            .accessibilityElement(children: .combine)
            timeline
            Button(action: addStop) {
                HStack(spacing: 4) {
                    Image("icPlusWhite").resizable().frame(width: 21, height: 21)
                    Text("Add a stop").outfitText(14, .semibold, .white)
                }
                .padding(.horizontal, 12)
                .frame(height: 47)
                .background(AB.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("addStop")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 199 / 255, green: 206 / 255, blue: 212 / 255).opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AB.primary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private var timeline: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 320
            ZStack(alignment: .topLeading) {
                Rectangle().fill(AB.primary).frame(width: 170 * scale, height: 3).offset(y: 3)
                Rectangle().fill(AB.primary.opacity(0.3)).frame(width: 126 * scale, height: 3).offset(x: 170 * scale, y: 3)
                point("Now", SampleJourney.now, x: 0, gate: false)
                point("Leave", leave, x: 165 * scale, gate: false)
                point("At gate", arrive, x: 227 * scale, gate: false)
                Image("icGate").resizable().frame(width: 24, height: 24).offset(x: 300 * scale, y: -4)
                Text(closes.description).outfitText(13, .semibold)
                    .offset(x: 296 * scale, y: 18)
                    .accessibilityLabel("Gate closes \(closes)")
            }
        }
        .frame(height: 48)
    }

    private func point(_ label: String, _ time: ClockTime, x: CGFloat, gate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image("timelinePoint").resizable().frame(width: 10, height: 10)
            VStack(alignment: .center, spacing: 0) {
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
