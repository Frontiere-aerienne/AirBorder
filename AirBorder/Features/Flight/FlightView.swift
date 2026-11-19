import SwiftUI

/// Figma "Flight" (858:10400).
struct FlightView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var airportProvider: AirportProviderReplay
    @Environment(\.openDestination) private var open

    var body: some View {
        let gateAction: (() -> Void)? = store.canOpenGateMap ? { store.openGateMap() } : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 8) {
                    titleRow
                    if let condition = store.primaryCondition {
                        TravelUpdateBanner(condition: condition, place: .flight)
                            .padding(.bottom, 16)
                    }
                    TicketCard(flight: store.outbound, previous: SampleJourney.inbound, status: store.flightStatus,
                               gate: store.gate, openGateMap: gateAction)
                    links
                }
                if store.isAirportTransfer {
                    TransferPlanSection()
                } else if let condition = store.timingCondition {
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
                HStack(spacing: 7) {
                    Image("icPlusDark").resizable().frame(width: 17, height: 17)
                    Text("Add flight").outfitText(15, .semibold)
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(AB.chip, in: Capsule())
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
            if airportProvider.supports(store.tripFlight) {
                TextLink(title: "Airport updates") { open(.airportUpdates) }
                    .accessibilityIdentifier("airportUpdatesLink")
            }
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

struct AirportUpdatesView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var airportProvider: AirportProviderReplay
    @Environment(\.dismiss) private var dismiss

    private static let airportTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var checked: Date? { airportProvider.planningLastChecked }

    private var checkSummary: String {
        let prefix = if airportProvider.planningOffline {
            "Offline"
        } else if !airportProvider.planningReachable {
            "Updates unavailable"
        } else {
            ""
        }
        guard let checked else { return prefix }
        let stamp = "Last checked \(Self.airportTime.string(from: checked)) JST"
        return prefix.isEmpty ? stamp : "\(prefix) · \(stamp)"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let snapshot = airportProvider.currentPlanning(for: store)
            let now = max(timeline.date, Date.now)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        StackedHeader(title: "Airport updates") { dismiss() }
                        Text(checkSummary).outfitText(15, .regular, AB.secondary)
                            .accessibilityIdentifier("airportUpdatesChecked")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        let onTime = snapshot?.status.value == .onSchedule
                        observation("Flight", id: "flight", value: onTime ? "On schedule" : "Delayed · Check boarding time",
                                    timestamp: snapshot?.status.observedAt, at: now)
                        Divider()
                        observation("Gate", id: "gate", value: store.gate, timestamp: snapshot?.gateCheckedAt,
                                    at: now, unavailable: "Last known: \(store.gate)")
                        Divider()
                        waitRow("Security", id: "security", wait: snapshot?.security, at: now)
                        Divider()
                        waitRow("Café wait", id: "cafe", wait: snapshot?.cafe, at: now)
                        Divider()
                        observation("Crowding", id: "crowd", value: snapshot?.crowd.level == .busy ? "Busy" : "Moderate",
                                    timestamp: snapshot?.crowd.observedAt, at: now)
                    }
                    .padding(.horizontal, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func observation(_ label: String, id: String, value: String, timestamp: TimeInterval?, at now: Date,
                             unavailable: String = "Updates unavailable") -> some View {
        let fresh = isCurrent(timestamp, at: now)
        return updateRow(label, id: id, value: fresh ? value : unavailable, detail: reportedDetail(timestamp, at: now))
    }

    private func waitRow(_ label: String, id: String, wait: DriverPlanningSnapshot.Wait?, at now: Date) -> some View {
        let fresh = isCurrent(wait?.observedAt, at: now)
        let value = fresh ? wait.map { "\($0.minutes) min" } ?? "Current wait unknown" : "Current wait unknown"
        let detail: String?
        if !fresh, airportProvider.planningReachable, let wait, wait.observedAt <= now.timeIntervalSince1970 {
            let report = Self.airportTime.string(from: Date(timeIntervalSince1970: wait.observedAt))
            detail = "Last estimate \(wait.minutes) min at \(report)"
        } else {
            detail = reportedDetail(wait?.observedAt, at: now)
        }
        return updateRow(label, id: id, value: value, detail: detail)
    }

    private func isCurrent(_ timestamp: TimeInterval?, at now: Date) -> Bool {
        guard airportProvider.planningReachable, let timestamp else { return false }
        return DriverPlanningSnapshot.isFresh(timestamp, at: now)
    }

    private func reportedDetail(_ timestamp: TimeInterval?, at now: Date) -> String? {
        guard airportProvider.planningReachable, let checked, let timestamp, timestamp <= now.timeIntervalSince1970,
              floor(timestamp / 60) != floor(checked.timeIntervalSince1970 / 60) else { return nil }
        let time = Self.airportTime.string(from: Date(timeIntervalSince1970: timestamp))
        return "Reported \(time)"
    }

    private func updateRow(_ label: String, id: String, value: String, detail: String?) -> some View {
        let tag = Text(label).outfitText(14, .bold, AB.gateText)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(AB.gateYellow, in: RoundedRectangle(cornerRadius: 8))
        let reading = VStack(alignment: .leading, spacing: 2) {
            Text(value).outfitText(16, .semibold)
            if let detail { Text(detail).outfitText(13, .regular, AB.secondary) }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                tag.frame(width: 92, alignment: .leading)
                reading.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 5) {
                tag
                reading
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("airportUpdate-\(id)")
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
    @Environment(\.gateAlertPresented) private var gateAlertPresented
    @State private var openStop: PlaceID?
    var usesTimeline = true
    var chooseStop: (() -> Void)?
    /// The hint teaches the rows once; it goes away after the first stop is opened.
    @AppStorage(JourneyStore.planHintKey) private var hintSeen = false

    static let stripStart = ClockTime(15, 0)
    static let stripMinutes = 150

    var body: some View {
        let stops = store.schedule.stops.map(\.stop)
        let showsTimeline = usesTimeline && !store.planTimingUnavailable
        VStack(alignment: .leading, spacing: 20) {
            header
            if let suggestion = store.suggestion {
                cafeNotice(suggestion)
            }
            if stops.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    addStopButton
                    Text("Add a café or lounge, then set your times").outfitText(15, .regular, AB.secondary)
                        .frame(maxWidth: .infinity)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !hintSeen && !store.planTimingUnavailable {
                        Text("Tap a stop to change its times").outfitText(15, .regular, AB.secondary)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                    if showsTimeline { hours }
                    ForEach(stops) { stop in
                        Group {
                            if showsTimeline { lane(stop) } else { stopRow(stop) }
                        }
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
        .accessibilityHidden(gateAlertPresented)
        .allowsHitTesting(!gateAlertPresented)
    }

    private var header: some View {
        let timed = store.schedule
        let timingLabel = store.planTimingUnavailable ? "Gate arrival —" :
            (timed.stops.isEmpty ? "Leave by \(timed.leave)" : "Estimated gate arrival \(timed.arriveAtGate)")
        let timingColor = store.planTimingUnavailable ? AB.secondary : (store.minutesToSpare < 0 ? AB.alert : AB.primary)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your plan").outfitText(22, .bold).accessibilityAddTraits(.isHeader)
                Text(timingLabel)
                    .outfitText(15, .semibold, timingColor)
                    .accessibilityLabel(store.planTimingUnavailable ? "Estimated gate arrival unavailable" : timingLabel)
                    .accessibilityIdentifier("planGateTiming")
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

    private func cafeNotice(_ suggestion: PlanSuggestion) -> some View {
        InfoCard(padding: 14, radius: 16, background: AB.ticket) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Café wait increased by \(suggestion.extraMinutes) min").outfitText(17, .bold, .white)
                    Text("Gate arrival \(store.schedule.arriveAtGate). \(suggestion.detail)")
                        .outfitText(14, .regular, AB.ice)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cafeWaitSuggestion")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { cafeActions }
                    VStack(spacing: 8) { cafeActions }
                }
            }
        }
    }

    @ViewBuilder
    private var cafeActions: some View {
        CTAButton(title: "Keep my plan", style: .outline) { store.keepPlan() }
            .accessibilityIdentifier("keepSuggestion")
        CTAButton(title: "Apply") { store.applySuggestion() }
            .accessibilityIdentifier("applySuggestion")
    }

    private var addStopButton: some View {
        Button {
            if let chooseStop { chooseStop() } else { store.tab = .layover }
        } label: {
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
            toggleEditor(stop.id)
        } label: {
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = { (time: ClockTime) in width * CGFloat(time - Self.stripStart) / CGFloat(Self.stripMinutes) }
                ZStack(alignment: .leading) {
                    if let times {
                        Text(stop.id == .cafe ? "Café" : stop.id.shortLabel.capitalized)
                            .outfitText(13, .bold, Self.textColor(stop.id))
                            .minimumScaleFactor(0.75)
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

    private func stopRow(_ stop: PlanStop) -> some View {
        let isOpen = openStop == stop.id
        return Button { toggleEditor(stop.id) } label: {
            HStack(spacing: 12) {
                Circle().stroke(AB.primary, lineWidth: 2).frame(width: 13, height: 13)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(stop.name).outfitText(17, .bold)
                    if store.planTimingUnavailable {
                        Text(stop.id == .cafe ? "Wait unavailable" : "\(stop.plannedVisitMinutes) min visit")
                            .outfitText(14, .regular, AB.secondary)
                    } else if let times = store.times(stop.id) {
                        Text("Arrive \(times.arrive) · Leave \(times.leave)").outfitText(14, .regular, AB.secondary)
                    }
                }
                Spacer(minLength: 5)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AB.primary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityHint(isOpen ? "Hide stop details" : store.planTimingUnavailable ? "Review stop" : "Change times")
        .accessibilityIdentifier("plan-stop-\(stop.id.rawValue)")
    }

    private func toggleEditor(_ id: PlaceID) {
        Haptics.tick()
        openStop = openStop == id ? nil : id
        hintSeen = true
    }

    /// Figma home Route: opens the route, which passes every stop in the plan.
    private func route() {
        if store.alerts[.gateChange] != nil { store.acknowledge(.gateChange) }
        if store.plan.stops.isEmpty && store.t2VisitPlanned { return open(.t2Deck) }
        store.openRoute()
    }

    static func color(_ id: PlaceID) -> Color {
        switch id {
        case .anaLounge: AB.ticket
        case .skyLounge: AB.sky
        case .bento: Color(hex: 0xED9E38)
        case .udon: AB.green
        case .sushi: Color(hex: 0x6B5CA5)
        default: AB.primary
        }
    }

    static func textColor(_ id: PlaceID) -> Color { [.skyLounge, .bento, .udon].contains(id) ? AB.ticket : .white }
}

struct PlanDetailView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BackButton(showsText: true) { dismiss() }
                if let condition = store.primaryCondition {
                    TravelUpdateBanner(condition: condition, place: .layover)
                }
                if let condition = store.timingCondition {
                    ScenarioPlanSection(condition: condition)
                } else {
                    PlanStripCard(usesTimeline: false) {
                        dismiss()
                        store.tab = .layover
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("planDetails")
    }
}

/// One stop's details under its strip row: where it is, Arrive/Leave in 15-minute steps, overlaps and Remove.
private struct StopTimesEditor: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.gateAlertPresented) private var gateAlertPresented
    @AccessibilityFocusState(for: .voiceOver) private var focusedTimeControl: String?
    let stop: PlanStop
    let close: () -> Void
    @State private var shakes: [String: CGFloat] = [:]
    @State private var lastFocusedTimeControl: String?

    var body: some View {
        if let times = store.times(stop.id) {
            VStack(alignment: .leading, spacing: 16) {
                detailsHeader.staggered(0)
                HStack(spacing: 12) {
                    stepper("Arrive", times.arrive, latest: false,
                            earlier: store.earliestArrival(for: stop.id).flatMap {
                                StopTimes.earlierArrive(times.arrive, earliestAllowed: $0)
                            },
                            later: StopTimes.laterArrive(times.arrive, latestAllowed: times.latest - (times.leave - times.arrive))) { store.setTimes(stop.id, arrive: $0) }
                    stepper("Leave", times.leave, latest: times.leave == times.latest,
                            earlier: store.earliestLeave(for: stop.id).flatMap {
                                StopTimes.earlierLeave(times.leave, earliestAllowed: $0)
                            },
                            later: StopTimes.laterLeave(times.leave, latest: times.latest)) { store.setTimes(stop.id, leave: $0) }
                }
                .staggered(1)
                ForEach(store.overlapping(stop.id)) { other in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(AB.alert)
                        Text("Overlaps \(other.id.shortLabel)").outfitText(15, .bold, AB.alert)
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
            .onChange(of: focusedTimeControl) { _, newFocus in
                if let newFocus { lastFocusedTimeControl = newFocus }
            }
            .task(id: gateAlertPresented) {
                guard !gateAlertPresented, let lastFocusedTimeControl, store.tab == .flight else { return }
                // Wait until the modal's accessibility tree has been removed before restoring focus.
                await Task.yield()
                if !Task.isCancelled { focusedTimeControl = lastFocusedTimeControl }
            }
        } else if store.planTimingUnavailable {
            detailsHeader
                .padding(.top, 18)
                .padding(.bottom, 22)
                .overlay(alignment: .top) { Rectangle().fill(AB.screen).frame(height: 1).padding(.top, 8) }
        }
    }

    private var detailsHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(PlanStripCard.color(stop.id)).frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text(stop.name).outfitText(19, .bold)
                    Spacer(minLength: 8)
                    removeButton
                }
                HStack(spacing: 6) {
                    fact("building.2", "Terminal 3, \(stop.id.floor)")
                    fact("figure.walk", "\(store.walkMinutes(stop.id, .gate)) min to gate")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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

    /// Leave enough room for the walk as well as the next stop.
    private func fix(for mine: (arrive: ClockTime, leave: ClockTime, latest: ClockTime), other: PlanStop) -> (title: String, apply: () -> Void)? {
        guard let theirs = store.times(other.id) else { return nil }
        let requested = other.arrive ?? theirs.arrive
        let leave = requested - store.walkMinutes(stop.id, other.id)
        if mine.arrive <= requested && store.canLeave(stop.id, at: leave) {
            return ("Leave \(leave)", { store.setTimes(stop.id, leave: leave) })
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
        .accessibilityFocused($focusedTimeControl, equals: label)
        .accessibilityValue(target == nil ? "Not available" : "")
    }
}
