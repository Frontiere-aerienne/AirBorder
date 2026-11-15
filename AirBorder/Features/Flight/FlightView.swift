import SwiftUI

/// Figma "Flight" (858:10400).
struct FlightView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 8) {
                    titleRow
                    if let condition = store.primaryCondition {
                        TravelUpdateBanner(condition: condition, place: .flight)
                            .padding(.bottom, 16)
                    }
                    TicketCard(flight: store.outbound, previous: SampleJourney.inbound, status: store.flightStatus, gate: store.gate)
                    links
                }
                if store.isAirportTransfer {
                    TransferPlanSection()
                } else if let condition = store.primaryCondition, store.hasTimingSituation {
                    VStack(alignment: .leading, spacing: 16) {
                        ScenarioPlanSection(condition: condition)
                    }
                } else {
                    planSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 49)
            .padding(.bottom, tabBarClearance)
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
            .buttonStyle(.pressable)
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
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var planSection: some View {
        PlanStripCard()
        // ponytail: the T2 deck visit keeps its own card; it is landside and not on the airside strip.
        if store.t2VisitPlanned && store.plan.stops.isEmpty { AddedPlanCard() }
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

/// Figma "Plan (live)" (1195:17606): time to spare, Route, a 15:00–17:30 strip with one row per stop,
/// and that stop's arrive/leave controls opening under its row.
struct PlanStripCard: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @State private var openStop: PlaceID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let stripStart = ClockTime(15, 0)
    static let stripMinutes = 150

    var body: some View {
        let stops = PlaceID.allCases.compactMap { id in store.plan.stops.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 12) {
            header
            if stops.isEmpty {
                addStopButton
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    hours
                    ForEach(stops) { stop in
                        lane(stop)
                        if openStop == stop.id {
                            StopTimesEditor(stop: stop) { openStop = nil }
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)))
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0), value: openStop)
        .animation(.abOut, value: stops.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planCard")
    }

    private var header: some View {
        let spare = (store.outbound.gateCloses ?? SampleJourney.gateArrivalTarget) - store.now
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your plan").outfitText(22, .bold).accessibilityAddTraits(.isHeader)
                HStack(spacing: 5) {
                    Text(durationText(spare)).outfitText(16, .semibold, AB.primary)
                    Text("to spare").outfitText(16, .regular, AB.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Button(action: route) {
                HStack(spacing: 9) {
                    Image("icWalkWhite").resizable().frame(width: 21, height: 21)
                    Text("Route").outfitText(14, .semibold, .white)
                }
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(AB.primary, in: Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("routeButton")
        }
    }

    private var addStopButton: some View {
        Button { store.tab = .layover } label: {
            Text("+  Add a stop").outfitText(18, .bold, AB.primary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AB.primary.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(AB.primary.opacity(0.35), lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("addStop")
    }

    private var hours: some View {
        GeometryReader { proxy in
            ForEach([0, 60, 120], id: \.self) { offset in
                Text((Self.stripStart + offset).description).outfitText(12, .medium, AB.secondary)
                    .offset(x: proxy.size.width * CGFloat(offset) / CGFloat(Self.stripMinutes))
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private func lane(_ stop: PlanStop) -> some View {
        let times = store.times(stop.id)
        let isOpen = openStop == stop.id
        return Button { openStop = isOpen ? nil : stop.id } label: {
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = { (time: ClockTime) in width * CGFloat(time - Self.stripStart) / CGFloat(Self.stripMinutes) }
                ZStack(alignment: .leading) {
                    if let times {
                        Text(stop.id == .anaLounge ? "LOUNGE" : stop.name).outfitText(13, .bold, Self.textColor(stop.id))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .frame(width: max(x(times.leave) - x(times.arrive), 0), height: proxy.size.height, alignment: .leading)
                            .background(Self.color(stop.id), in: RoundedRectangle(cornerRadius: 8))
                            .offset(x: x(times.arrive))
                    }
                    Rectangle().fill(AB.gateYellow).frame(width: 2).offset(x: x(SampleJourney.gateArrivalTarget))
                    Rectangle().fill(AB.alert).frame(width: 2).offset(x: x(store.outbound.gateCloses ?? SampleJourney.gateArrivalTarget))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundStyle(AB.primary)
                        .frame(width: 18, height: 18)
                        .background(AB.screen, in: RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 3)
                }
            }
            .frame(height: 28)
            .animation(.abOut, value: times.map { [$0.arrive.minutes, $0.leave.minutes] })
            .background(AB.screen, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isOpen { RoundedRectangle(cornerRadius: 8).strokeBorder(AB.primary, lineWidth: 2) }
            }
            // ponytail: 28pt row like Figma; the hit area reaches into the 4pt gaps, not a full 44pt.
            .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(stop.name), \(times.map { "\($0.arrive) to \($0.leave)" } ?? "")")
        .accessibilityHint(isOpen ? "Hide times" : "Change times")
        .accessibilityIdentifier("lane-\(stop.id.rawValue)")
    }

    /// Figma home Route: the route through your stops when the plan has some, otherwise the direct route.
    private func route() {
        if store.alerts[.gateChange] != nil { store.acknowledge(.gateChange) }
        if store.plan.stops.isEmpty && store.t2VisitPlanned { return open(.t2Deck) }
        store.routeChoice = RouteChoice.viaStops.resolved(for: store.plan)
        store.routeStep = 1
        store.tab = .route
    }

    static func color(_ id: PlaceID) -> Color {
        switch id {
        case .anaLounge: AB.ticket
        case .skyLounge: AB.sky
        default: AB.primary
        }
    }

    static func textColor(_ id: PlaceID) -> Color { id == .skyLounge ? AB.ticket : .white }
}

/// One stop's details under its strip row: where it is, Arrive/Leave in 15-minute steps, overlaps and Remove.
private struct StopTimesEditor: View {
    @EnvironmentObject private var store: JourneyStore
    let stop: PlanStop
    let close: () -> Void

    var body: some View {
        if let times = store.times(stop.id) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(PlanStripCard.color(stop.id)).frame(width: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.name).outfitText(19, .bold)
                        Text("Terminal 3, \(stop.id == .anaLounge ? "4F" : "3F"). \(store.venueToGateMinutes(stop.id)) min walk to the gate.")
                            .outfitText(15, .regular, AB.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    stepper("Arrive", times.arrive, latest: false,
                            earlier: StopTimes.earlierArrive(times.arrive),
                            later: StopTimes.laterArrive(times.arrive, leave: times.leave)) { store.setTimes(stop.id, arrive: $0) }
                    stepper("Leave", times.leave, latest: times.leave == times.latest,
                            earlier: StopTimes.earlierLeave(times.leave, arrive: times.arrive),
                            later: StopTimes.laterLeave(times.leave, latest: times.latest)) { store.setTimes(stop.id, leave: $0) }
                }
                ForEach(store.overlapping(stop.id)) { other in
                    Text("Overlaps with \(other.name)").outfitText(15, .bold, AB.alert)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AB.alertBackground, in: RoundedRectangle(cornerRadius: 10))
                }
                Button {
                    Haptics.tap()
                    withAnimation(.abOut) {
                        close()
                        store.remove(stop.id)
                    }
                } label: {
                    Text("Remove").outfitText(16, .bold, AB.secondary).frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Remove \(stop.name)")
                .accessibilityIdentifier("remove-\(stop.id.rawValue)")
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .transition(.opacity)
        }
    }

    private func stepper(_ title: String, _ time: ClockTime, latest: Bool, earlier: ClockTime?, later: ClockTime?, set: @escaping (ClockTime) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).outfitText(14, .bold, AB.secondary)
                if latest {
                    Text("latest").outfitText(11, .bold, .white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AB.alert, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.leading, 4)
            HStack {
                stepButton("−", "\(title) earlier", earlier, set)
                Spacer()
                Text(time.description).outfitText(22, .semibold).monospacedDigit().lineLimit(1).fixedSize()
                    .contentTransition(.numericText(value: Double(time.minutes)))
                Spacer()
                stepButton("+", "\(title) later", later, set)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.screen, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(title.lowercased())-\(stop.id.rawValue)")
    }

    private func stepButton(_ symbol: String, _ label: String, _ target: ClockTime?, _ set: @escaping (ClockTime) -> Void) -> some View {
        Button {
            guard let target else { return }
            Haptics.tick()
            withAnimation(.abOut) { set(target) }
        } label: {
            Text(symbol).outfitText(22, .medium)
                .frame(width: 34, height: 34)
                .background(.white, in: Circle())
                .contentShape(Circle().inset(by: -5))
        }
        .buttonStyle(.pressable)
        .disabled(target == nil)
        .opacity(target == nil ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}
