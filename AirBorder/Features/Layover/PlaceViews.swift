import SwiftUI

// MARK: - Shared pieces (Figma "Facilities" and "Return to gate" frames)

struct FloorBadge: View {
    let floor: String
    var body: some View {
        Text(floor).outfitText(13, .bold, AB.ice)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(AB.navy, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Small icon + text chip. `dark` sits on navy cards.
struct IconChip: View {
    let icon: String
    let text: String
    var dark = false
    var tinted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(icon).renderingMode(.template).resizable().frame(width: 14, height: 14)
                .foregroundStyle(dark ? AB.sky : AB.primary)
            Text(text).outfitText(13, .semibold, dark ? AB.chipText : AB.navy)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(dark ? AB.ice.opacity(0.1) : (tinted ? AB.sky.opacity(0.2) : AB.card), in: Capsule())
    }
}

/// Numbered steps on a white card (Figma "Steps").
struct StepList: View {
    let steps: [(String, String?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Text("\(index + 1)").outfitText(13, .bold)
                            .frame(width: 26, height: 26)
                            .background(AB.sky.opacity(0.35), in: Circle())
                        if index < steps.count - 1 {
                            Rectangle().fill(AB.primary.opacity(0.25)).frame(width: 2, height: step.1 == nil ? 12 : 30)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.0).outfitText(15, .semibold)
                        if let detail = step.1 { Text(detail).outfitText(13, .regular, AB.muted) }
                    }
                    .padding(.top, 3)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct LightTimeChip: View {
    let text: String
    var body: some View {
        Text(text).outfitText(20, .semibold, AB.ice)
            .padding(.horizontal, 10).padding(.vertical, 2)
            .background(AB.ice.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// "Gate 105 closes 17:25" on a navy card.
struct GateClosesRow: View {
    @EnvironmentObject private var store: JourneyStore
    var body: some View {
        HStack(spacing: 8) {
            GateSign(gate: store.gate)
            Text("closes").outfitText(15, .regular, AB.ice.opacity(0.75))
            LightTimeChip(text: (SampleJourney.outbound.gateCloses ?? SampleJourney.gateArrivalTarget).description)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gate \(store.gate) closes \(SampleJourney.outbound.gateCloses?.description ?? "")")
    }
}

struct NavyPanel<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Back icon, 28 pt title (the Facilities / Return to gate frames).
struct PlaceScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: title) { dismiss() }
            content
        }
    }
}

// MARK: - Return to gate from a venue (858:12183, 858:12228, 858:12275)

struct ReturnToGateView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openURL) private var openURL
    let place: PlaceID

    private var venue: (name: String, floor: String, first: String, phone: String?) {
        switch place {
        case .cafe: return ("Curacion Cafe", "3F", "Head to the 3F departure concourse", "+81364280687")
        case .skyLounge: return ("SKY LOUNGE", "4F", "Leave the lounge, lift to 3F", "+81364280752")
        default: return ("ANA LOUNGE", "4F", "Leave the lounge, lift to 3F", nil)
        }
    }

    var body: some View {
        let walk = store.venueToGateMinutes(place)
        PlaceScreen(title: "Gate \(store.gate)") {
            HStack(spacing: 6) {
                Text("From \(venue.name)").outfitText(15, .regular, AB.muted)
                TerminalSign(terminal: SampleJourney.outbound.departureTerminal)
                FloorBadge(floor: venue.floor)
            }
            HStack(spacing: 8) {
                Image("icWalkNavy").resizable().frame(width: 22, height: 22)
                ZStack {
                    Image("routeDots").resizable().frame(height: 2)
                    TimeChip(text: "\(walk) min")
                }
                GateSign(gate: store.gate)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(walk) minute walk to Gate \(store.gate)")
            NavyPanel {
                HStack(spacing: 8) {
                    Text("Leave by").outfitText(18, .semibold, AB.ice)
                    LightTimeChip(text: (SampleJourney.gateArrivalTarget - walk).description)
                }
                .accessibilityElement(children: .combine)
                GateClosesRow()
            }
            StepList(steps: [(venue.first, nil), ("Follow the overhead signs to Gate \(store.gate)", nil), ("Check \(SampleJourney.outbound.number) on the gate display", nil)])
            if let phone = venue.phone {
                Button { if let url = URL(string: "tel:\(phone)") { openURL(url) } } label: {
                    HStack(spacing: 8) {
                        Image("icPhone").resizable().frame(width: 18, height: 18)
                        Text("Call \(venue.name)").outfitText(14, .semibold, AB.primary)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - ANA LOUNGE (858:13161) and lounge map (858:13185)

struct ANALoungeView: View {
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BackButton { dismiss() }
                HStack(spacing: 8) {
                    AirlineBadge(airline: .ana)
                    Text("LOUNGE").outfitText(22, .bold).accessibilityAddTraits(.isHeader)
                }
                .padding(.top, 12)
                HStack(spacing: 6) {
                    TerminalSign(terminal: "3")
                    FloorBadge(floor: "4F")
                }
                VStack(spacing: 0) {
                    row("tileClock", "Open 05:00", "Until the last ANA departure")
                    RowDivider()
                    row("tileShield", "Business Class boarding pass", "Show it at the entrance")
                }
                CTAButton(title: "Directions") { open(.loungeMap) }
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(AB.card.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(icon).resizable().frame(width: 18, height: 18)
                .frame(width: 36, height: 36)
                .background(AB.sky.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).outfitText(16, .semibold)
                Text(detail).outfitText(13, .regular, AB.muted)
            }
            Spacer()
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

struct LoungeMapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var camera = false
    @State private var cameraCovers = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BackButton { dismiss() }
                if !(camera && cameraCovers) {
                    Text("Route to ANA LOUNGE").outfitText(30, .bold).tracking(-1.1).accessibilityAddTraits(.isHeader)
                    HStack(spacing: 4) {
                        segment("Map", !camera) { camera = false }
                        segment("Camera", camera) { camera = true }
                    }
                    .padding(4)
                    .background(.white.opacity(0.7), in: Capsule())
                }
                if camera {
                    if !cameraCovers {
                        HStack(spacing: 6) {
                            FloorBadge(floor: "3F")
                            Text("→").outfitText(15, .regular)
                            FloorBadge(floor: "4F")
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("From 3F to 4F")
                    }
                    // Figma "Camera (airline lounge right turn)" (858:11417) and scan (858:11469).
                    CameraGuide(sign: .lounges, arrow: "camArrowRight", readAgainTitle: "Read lounge sign again", readAgainFullWidth: true, exit: { camera = false }, covers: $cameraCovers) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Turn right for airline lounges").outfitText(17, .bold, AB.gateYellow)
                            Text("航空会社ラウンジ / Airline lounges").outfitText(13, .regular, AB.ice.opacity(0.75))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AB.ticket, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Turn right for airline lounges").outfitText(22, .bold, AB.gateYellow)
                        Text("航空会社ラウンジ / Airline lounges").outfitText(13, .regular, AB.ice.opacity(0.75))
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AB.ticket, in: RoundedRectangle(cornerRadius: 18))
                }
                if !camera {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image("icWalkNavy").resizable().frame(width: 22, height: 22)
                            FloorBadge(floor: "3F")
                            Image("liftPill").resizable().frame(width: 44, height: 26)
                            FloorBadge(floor: "4F")
                            HStack(spacing: 6) {
                                Image("tileRest").resizable().frame(width: 14, height: 14)
                                AirlineBadge(airline: .ana).scaleEffect(0.8)
                                Text("LOUNGE").outfitText(13, .bold)
                            }
                            .padding(.horizontal, 8).frame(height: 32)
                            .background(AB.sky.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                        }
                        HStack(spacing: 8) {
                            TerminalSign(terminal: "3")
                            Text("From the airside 3F concourse").outfitText(13, .regular, AB.muted)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Walk from 3F, take the lift to 4F, ANA LOUNGE. From the airside 3F concourse in Terminal 3.")
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func segment(_ title: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).outfitText(14, .semibold, selected ? .white : AB.primary)
                .frame(maxWidth: .infinity, minHeight: 47)
                .background(selected ? AB.primary : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Landside routes (858:12101, 858:12142) and facility symbols (858:12083)

struct LandsideRouteView: View {
    @EnvironmentObject private var store: JourneyStore
    @State private var showsLeaving = false
    let observationDeck: Bool

    var body: some View {
        PlaceScreen(title: observationDeck ? "Observation Deck" : "Air BicCamera") {
            HStack(spacing: 6) {
                TerminalSign(terminal: "3")
                FloorBadge(floor: observationDeck ? "5F" : "2F")
                IconChip(icon: "tileWalk", text: "Walk + lift")
            }
            StepList(steps: [("Ask airport staff for the landside exit", nil), ("Complete Japan arrival, then lift to \(observationDeck ? "5F" : "2F")", nil)])
            NavyPanel {
                Text("Coming back").outfitText(14, .semibold, AB.sky)
                HStack(spacing: 6) {
                    IconChip(icon: "tileShield", text: "30 min security", dark: true)
                    IconChip(icon: "tileWalk", text: "\(store.gateWalkMinutes) min walk", dark: true)
                }
                GateClosesRow()
            }
            Text("Be at the gate by \(SampleJourney.gateArrivalTarget).").outfitText(13, .regular, AB.muted)
            CenteredButton(title: "View entry & baggage") { showsLeaving = true }
        }
        .sheet(isPresented: $showsLeaving) { Sheets.beforeLeavingAirside(walk: store.gateWalkMinutes) }
    }
}

struct FacilityGuideView: View {
    var body: some View {
        PlaceScreen(title: "Facility symbols") {
            GroupedList {
                row("icWifi", "Wi-Fi")
                RowDivider()
                row("icPower", "Power outlets")
                RowDivider()
                row("icSeating", "Seating")
            }
        }
    }

    private func row(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 14) {
            Image(icon).renderingMode(.template).resizable().frame(width: 24, height: 24).foregroundStyle(AB.primary)
            Text(title).outfitText(16, .semibold)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }
}

// MARK: - Terminal 2 visit (858:12323, 858:12372, 858:12465, 858:12420, 997:31135)

enum TerminalTwo {
    static let walkToShuttle = 11
    static let shuttleWait = 4
    static let shuttle = 15
    static let backToT3 = 30
    static let security = 30
    static let fullShuttleExtra = 10

    /// Leave Terminal 2 by: gate arrival target minus the gate walk, security and the trip back.
    static func leaveBy(gateWalk: Int) -> ClockTime {
        SampleJourney.gateArrivalTarget - gateWalk - security - backToT3
    }

    static let visitMinutes = 30
    static var oneWay: Int { walkToShuttle + shuttleWait + shuttle }

    /// Enough time to get to Terminal 2, spend the 30-minute visit and still leave by the leave-by time.
    static func hasTime(now: ClockTime, gateWalk: Int) -> Bool {
        now + oneWay + visitMinutes <= leaveBy(gateWalk: gateWalk)
    }
}

/// Figma "Return to your gate" (858:12494): not enough time left for the Terminal 2 visit.
struct T2NotEnoughTimeView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.popToRoot) private var popToRoot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BackButton { dismiss() }.offset(x: -9)
            Text("Return to your gate").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                Text("Not enough time for Terminal 2").outfitText(12, .semibold, .white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(AB.riskTag, in: Capsule())
                Text("Head to your gate").outfitText(22, .bold, AB.ice)
                HStack(spacing: 6) {
                    IconChip(icon: "tileBus", text: "Shuttle", dark: true)
                    IconChip(icon: "tileClock", text: "Security", dark: true)
                    IconChip(icon: "tileWalk", text: "Gate walk", dark: true)
                }
                HStack(spacing: 8) {
                    GateSign(gate: store.gate)
                    Text("closes").outfitText(15, .regular, AB.ice.opacity(0.75))
                    LightTimeChip(text: store.outbound.gateCloses?.description ?? "–")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("notEnoughTime")
            Button {
                popToRoot()
                store.tab = .route
            } label: {
                HStack(spacing: 9) {
                    Image("icWalkWhite").resizable().frame(width: 21, height: 21)
                    Text("Route").outfitText(15, .semibold, .white)
                }
                .frame(width: 200, height: 52)
                .background(AB.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct T2DeckView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.openURL) private var openURL

    var body: some View {
        let oneWay = TerminalTwo.walkToShuttle + TerminalTwo.shuttleWait + TerminalTwo.shuttle
        PlaceScreen(title: "T2 Observation Deck") {
            HStack(spacing: 6) {
                TerminalSign(terminal: "2")
                FloorBadge(floor: "5F")
                IconChip(icon: "tileClock", text: "06:30–22:00")
            }
            NavyPanel {
                HStack(spacing: 8) {
                    TerminalSign(terminal: "3")
                    ZStack {
                        Image("routeDots").resizable().frame(height: 2).opacity(0.6)
                        LightTimeChip(text: "\(oneWay) min")
                    }
                    TerminalSign(terminal: "2")
                }
                FlowRow {
                    IconChip(icon: "tileWalk", text: "\(TerminalTwo.walkToShuttle) min", dark: true)
                    IconChip(icon: "tileClock", text: "\(TerminalTwo.shuttleWait) min wait", dark: true)
                    IconChip(icon: "tileBus", text: "\(TerminalTwo.shuttle) min free shuttle", dark: true)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Leave Terminal 2 by").outfitText(16, .semibold)
                    TimeChip(text: TerminalTwo.leaveBy(gateWalk: store.gateWalkMinutes).description)
                }
                FlowRow {
                    IconChip(icon: "tileBus", text: "\(TerminalTwo.backToT3) min to T3", tinted: true)
                    IconChip(icon: "tileClock", text: "\(TerminalTwo.security) min security", tinted: true)
                    IconChip(icon: "tileWalk", text: "\(store.gateWalkMinutes) min to gate", tinted: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
            CenteredButton(title: store.t2VisitPlanned ? "Remove the visit" : "Add a 30-minute visit", identifier: "addT2Visit") {
                store.t2VisitPlanned.toggle()
                if store.t2VisitPlanned {
                    store.showToast(ToastMessage(text: "Added to your plan", action: "View on Flight")) { store.tab = .flight }
                }
            }
            CenteredButton(title: "View shuttle route", filled: false) { open(.toTerminal2) }
            CenteredButton(title: "Airport transport guide", filled: false) {
                if let url = URL(string: "https://tokyo-haneda.com/en/access/travel_between_terminals/index.html") { openURL(url) }
            }
            Text("From airside, ask staff for the landside exit first").outfitText(14, .regular, AB.secondary)
        }
    }
}

struct ToTerminal2View: View {
    @Environment(\.openDestination) private var open

    var body: some View {
        PlaceScreen(title: "To Terminal 2") {
            HStack(spacing: 6) {
                Text("From").outfitText(15, .regular, AB.muted)
                TerminalSign(terminal: "3")
                FloorBadge(floor: "2F")
            }
            FlowRow {
                IconChip(icon: "tileWalk", text: "\(TerminalTwo.walkToShuttle) min")
                IconChip(icon: "tileClock", text: "\(TerminalTwo.shuttleWait) min wait")
                IconChip(icon: "tileBus", text: "\(TerminalTwo.shuttle) min shuttle")
            }
            StepList(steps: [
                ("Walk to the shuttle", "Lift to T3 1F, Bus Stop 0"),
                ("Take the free shuttle", "T3 to T1 to T2, about 15 min"),
                ("Walk to the deck", "T2 1F, lift to 5F"),
            ])
            CenteredButton(title: "Arrived at Terminal 2") { open(.atTerminal2) }
            CenteredButton(title: "View return route", filled: false) { open(.returnFromT2) }
            Text("From airside, ask staff for the landside exit first").outfitText(14, .regular, AB.secondary)
            Button { open(.shuttleFull) } label: {
                Text("Transfer updates").outfitText(13, .regular, AB.primary).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }
}

struct AtTerminal2View: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.popToRoot) private var popToRoot

    var body: some View {
        PlaceScreen(title: "At T2 Observation Deck") {
            HStack(spacing: 6) {
                TerminalSign(terminal: "2")
                FloorBadge(floor: "5F")
            }
            NavyPanel {
                IconChip(icon: "tileClock", text: "30-minute visit", dark: true)
                HStack(spacing: 8) {
                    Text("Leave by").outfitText(18, .semibold, AB.ice)
                    LightTimeChip(text: TerminalTwo.leaveBy(gateWalk: store.gateWalkMinutes).description)
                }
                HStack(spacing: 6) {
                    IconChip(icon: "tileBus", text: "Shuttle", dark: true)
                    IconChip(icon: "tileClock", text: "Security", dark: true)
                    IconChip(icon: "tileWalk", text: "Gate walk", dark: true)
                }
            }
            CenteredButton(title: "Return to Terminal 3") { open(.returnFromT2) }
            CenteredButton(title: "View Journey", filled: false) {
                popToRoot()
                store.tab = .flight
            }
        }
    }
}

struct ReturnFromT2View: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.popToRoot) private var popToRoot

    var body: some View {
        PlaceScreen(title: "Return to Gate \(store.gate)") {
            HStack(spacing: 6) {
                TerminalSign(terminal: "3")
                GateSign(gate: store.gate)
            }
            HStack(spacing: 8) {
                Text("Leave Terminal 2 by").outfitText(16, .semibold)
                TimeChip(text: TerminalTwo.leaveBy(gateWalk: store.gateWalkMinutes).description)
            }
            StepList(steps: [
                ("T2 bus stop 9", "Lift to 1F arrivals"),
                ("Free shuttle to T3", "About 15 min"),
                ("T3 departures, 3F", "Security and passport control, about 30 min"),
                ("Follow Gates 105–109", "Continue to Gate 105"),
            ])
            CenteredButton(title: "Open gate directions") {
                popToRoot()
                store.tab = .route
            }
        }
    }
}

struct ShuttleFullView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.popToRoot) private var popToRoot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen {
            HeaderWithBack(title: "Shuttle is full") { dismiss() }
            GateChip()
            Text("Terminal transfer update").outfitText(15, .regular, AB.secondary)
            NavyCard(title: "Allow \(TerminalTwo.fullShuttleExtra) extra minutes",
                     detail: "Wait for the next shuttle. Your transfer now takes about \(TerminalTwo.shuttle + TerminalTwo.fullShuttleExtra) min.")
            InfoCard(padding: 16, radius: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review your stops").outfitText(18, .bold)
                    Text(store.plan.stops.isEmpty ? "Check your gate-arrival time with the longer transfer." : "\(store.plan.stops.map(\.name).joined(separator: " and ")) \(store.plan.stops.count == 1 ? "is" : "are") in your plan. Review the updated transfer timing.")
                        .outfitText(15, .regular, AB.secondary)
                }
            }
            CTAButton(title: "Review my plan") { open(.myPlan) }
            CTAButton(title: "Terminal transfer route", style: .outline) { dismiss() }
            CTAButton(title: "Go to gate", style: .plain) {
                popToRoot()
                store.tab = .route
            }
        }
    }
}
