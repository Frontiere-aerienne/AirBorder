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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openStop: PlaceID?
    /// The hint teaches the rows once; it goes away after the first stop is opened.
    @AppStorage(JourneyStore.planHintKey) private var hintSeen = false

    static let stripStart = ClockTime(15, 0)
    static let stripMinutes = 150

    var body: some View {
        let stops = PlaceID.allCases.compactMap { id in store.plan.stops.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 20) {
            header
            if stops.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    addStopButton
                    Text("Add a café or lounge, then set your times").outfitText(15, .regular, AB.secondary)
                        .frame(maxWidth: .infinity)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !hintSeen {
                        Text("Tap a stop to change its times").outfitText(15, .regular, AB.secondary)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                    hours
                    ForEach(stops) { stop in
                        lane(stop)
                            .transition(.opacity.combined(with: .offset(y: -8)))
                        if openStop == stop.id {
                            StopTimesEditor(stop: stop) { openStop = nil }
                                .transition(reduceMotion ? .opacity : .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -10)),
                                    removal: .opacity.animation(.easeOut(duration: 0.12))))
                        }
                    }
                    legend.padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.38, bounce: 0.12), value: openStop)
        .animation(.abOut, value: stops.map(\.id))
        .animation(.abOut, value: hintSeen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planCard")
    }

    private var header: some View {
        let spare = store.minutesToSpare
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your plan").outfitText(22, .bold).accessibilityAddTraits(.isHeader)
                HStack(spacing: 5) {
                    Text(durationText(spare)).outfitText(16, .semibold, AB.primary)
                        .contentTransition(.numericText(value: Double(spare)))
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
                Text((Self.stripStart + offset).description).outfitText(13, .medium, AB.secondary)
                    .offset(x: proxy.size.width * CGFloat(offset) / CGFloat(Self.stripMinutes))
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    /// Figma "Legend": what the yellow and red lines mean.
    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(AB.gateYellow, "Be at gate \(SampleJourney.gateArrivalTarget)")
            legendItem(AB.alert, "Gate closes \(store.outbound.gateCloses ?? SampleJourney.gateArrivalTarget)")
        }
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 14)
            Text(text).outfitText(14, .medium, AB.secondary)
        }
    }

    private func lane(_ stop: PlanStop) -> some View {
        let times = store.times(stop.id)
        let isOpen = openStop == stop.id
        return Button {
            Haptics.tick()
            openStop = isOpen ? nil : stop.id
            hintSeen = true
        } label: {
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = { (time: ClockTime) in width * CGFloat(time - Self.stripStart) / CGFloat(Self.stripMinutes) }
                ZStack(alignment: .leading) {
                    if let times {
                        Text(stop.id == .anaLounge ? "LOUNGE" : stop.name).outfitText(13, .bold, Self.textColor(stop.id))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .frame(width: max(x(times.leave) - x(times.arrive), 0), height: proxy.size.height, alignment: .leading)
                            .background(Self.color(stop.id), in: RoundedRectangle(cornerRadius: 10))
                            .shadow(color: Self.color(stop.id).opacity(isOpen ? 0.35 : 0), radius: 6, y: 2)
                            .offset(x: x(times.arrive))
                    }
                    Rectangle().fill(AB.gateYellow).frame(width: 2).offset(x: x(SampleJourney.gateArrivalTarget))
                    Rectangle().fill(AB.alert).frame(width: 2).offset(x: x(store.outbound.gateCloses ?? SampleJourney.gateArrivalTarget))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundStyle(AB.primary)
                        .frame(width: 20, height: 20)
                        .background(AB.screen, in: RoundedRectangle(cornerRadius: 5))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 4)
                }
            }
            .frame(height: 36)
            .animation(.abOut, value: times.map { [$0.arrive.minutes, $0.leave.minutes] })
            .background(AB.screen, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(AB.primary, lineWidth: 2).opacity(isOpen ? 1 : 0)
            }
            .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(stop.name), \(times.map { "\($0.arrive) to \($0.leave)" } ?? "")")
        .accessibilityHint(isOpen ? "Hide times" : "Change times")
        .accessibilityIdentifier("lane-\(stop.id.rawValue)")
    }

    /// Figma home Route: opens the route, which passes every stop in the plan.
    private func route() {
        if store.alerts[.gateChange] != nil { store.acknowledge(.gateChange) }
        if store.plan.stops.isEmpty && store.t2VisitPlanned { return open(.t2Deck) }
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
    @State private var shakes: [String: CGFloat] = [:]

    var body: some View {
        if let times = store.times(stop.id) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(PlanStripCard.color(stop.id)).frame(width: 4)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            Text(stop.name).outfitText(19, .bold)
                            Spacer(minLength: 8)
                            removeButton
                        }
                        HStack(spacing: 6) {
                            fact("building.2", "Terminal 3, \(stop.id == .anaLounge ? "4F" : "3F")")
                            fact("figure.walk", "\(store.venueToGateMinutes(stop.id)) min to gate")
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .staggered(0)
                HStack(spacing: 12) {
                    stepper("Arrive", times.arrive, latest: false,
                            earlier: StopTimes.earlierArrive(times.arrive),
                            later: StopTimes.laterArrive(times.arrive, leave: times.latest)) { store.setTimes(stop.id, arrive: $0) }
                    stepper("Leave", times.leave, latest: times.leave == times.latest,
                            earlier: StopTimes.earlierLeave(times.leave, arrive: times.arrive),
                            later: StopTimes.laterLeave(times.leave, latest: times.latest)) { store.setTimes(stop.id, leave: $0) }
                }
                .staggered(1)
                ForEach(store.overlapping(stop.id)) { other in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(AB.alert)
                        Text("Overlaps \(other.id == .anaLounge ? "LOUNGE" : other.name)").outfitText(15, .bold, AB.alert)
                            .lineLimit(1).minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Overlaps with \(other.name)")
                        if let fix = fix(for: times, other: other) {
                            Button {
                                Haptics.tick()
                                withAnimation(.abOut) { fix.apply() }
                            } label: {
                                Text(fix.title).outfitText(14, .bold, .white)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 34)
                                    .background(AB.alert, in: Capsule())
                                    .contentShape(Capsule().inset(by: -5))
                            }
                            .buttonStyle(.pressable)
                            .accessibilityIdentifier("fixOverlap-\(stop.id.rawValue)")
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .background(AB.alertBackground, in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
                .staggered(2)
            }
            .padding(.top, 18)
            .padding(.bottom, 22)
            .overlay(alignment: .top) { Rectangle().fill(AB.screen).frame(height: 1).padding(.top, 8) }
        }
    }

    private var removeButton: some View {
        Button {
            Haptics.tap()
            withAnimation(.abOut) {
                close()
                store.removeWithUndo(stop.id)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                Text("Remove").outfitText(14, .semibold)
            }
            .foregroundStyle(AB.removeRed)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color(hex: 0xFCEDED), in: Capsule())
            .contentShape(Capsule().inset(by: -5))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Remove \(stop.name)")
        .accessibilityIdentifier("remove-\(stop.id.rawValue)")
    }

    private func fact(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            Text(text).outfitText(14, .medium)
        }
        .foregroundStyle(AB.secondary)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(AB.screen, in: Capsule())
    }

    /// One tap to end the overlap: leave when the other stop starts, or arrive when it ends.
    private func fix(for mine: (arrive: ClockTime, leave: ClockTime, latest: ClockTime), other: PlanStop) -> (title: String, apply: () -> Void)? {
        guard let theirs = store.times(other.id) else { return nil }
        if mine.arrive <= theirs.arrive, theirs.arrive >= mine.arrive + StopTimes.minimumStay {
            return ("Leave \(theirs.arrive)", { store.setTimes(stop.id, leave: theirs.arrive) })
        }
        if mine.arrive > theirs.arrive, theirs.leave + StopTimes.minimumStay <= mine.latest {
            return ("Arrive \(theirs.leave)", { store.setTimes(stop.id, arrive: theirs.leave) })
        }
        return nil
    }

    private func stepper(_ title: String, _ time: ClockTime, latest: Bool, earlier: ClockTime?, later: ClockTime?, set: @escaping (ClockTime) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: title == "Arrive" ? "figure.walk.arrival" : "figure.walk.departure")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(AB.secondary)
                Text(title).outfitText(14, .bold, AB.secondary)
                if latest {
                    Text("latest").outfitText(11, .bold, .white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AB.alert, in: RoundedRectangle(cornerRadius: 6))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.leading, 4)
            HStack(spacing: 0) {
                stepButton("−", "\(title) earlier", earlier, key: title, set)
                Spacer(minLength: 2)
                Text(time.description).outfitText(22, .semibold).monospacedDigit().lineLimit(1).fixedSize()
                    .contentTransition(.numericText(value: Double(time.minutes)))
                    .modifier(Shake(shakes: shakes[title] ?? 0))
                Spacer(minLength: 2)
                stepButton("+", "\(title) later", later, key: title, set)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.screen, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(title.lowercased())-\(stop.id.rawValue)")
    }

    /// At a limit the button stays tappable: the time shakes and a firm tap explains why nothing changed.
    private func stepButton(_ symbol: String, _ label: String, _ target: ClockTime?, key: String, _ set: @escaping (ClockTime) -> Void) -> some View {
        Button {
            guard let target else {
                Haptics.limit()
                withAnimation(.linear(duration: 0.35)) { shakes[key, default: 0] += 1 }
                return
            }
            Haptics.tick()
            withAnimation(.abOut) { set(target) }
        } label: {
            Text(symbol).outfitText(22, .medium)
                .frame(width: 38, height: 38)
                .background(.white, in: Circle())
                .contentShape(Circle().inset(by: -5))
        }
        .buttonStyle(.pressable)
        .opacity(target == nil ? 0.35 : 1)
        .accessibilityLabel(label)
        .accessibilityValue(target == nil ? "Not available" : "")
    }
}
