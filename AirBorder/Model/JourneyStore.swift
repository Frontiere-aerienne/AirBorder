// SUBSTANTIVE: Applies journey updates and maintains passenger decisions across views.

import Foundation
import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case flight, layover, route, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .flight: return "Flight"
        case .layover: return "Layover"
        case .route: return "Route"
        case .profile: return "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .flight: "airplane"
        case .layover: "safari"
        case .route: "map"
        case .profile: "person.crop.circle"
        }
    }
}

/// Figma "Choose a route" options. Minutes are the average walking times for each route.
enum RouteChoice: String, CaseIterable, Codable {
    case direct, stepFree, lessCrowded

    /// Shown on the route card's choice button (Figma "Direct route").
    var menuTitle: String { "\(title) route" }

    var title: String {
        switch self {
        case .direct: return "Direct"
        case .stepFree: return "Step-free"
        case .lessCrowded: return "Less crowded"
        }
    }

    var detail: String {
        switch self {
        case .direct: return "Shortest walk, one set of stairs"
        case .stepFree: return "Lift beside the stairs"
        case .lessCrowded: return "Outer concourse by the windows"
        }
    }

    var averageMinutes: Int {
        switch self {
        case .direct: return 12
        case .stepFree: return 16
        case .lessCrowded: return 15
        }
    }
}

enum HealthConnection: String, Codable {
    case notConnected, connected, removed
}

/// App state for the traveller's journey: selected plan, checkpoints, preferences and walking data.
@MainActor
final class JourneyStore: ObservableObject {
    @Published var tab: AppTab = .flight
    @Published private(set) var plan: Plan { didSet { persist() } }
    @Published private(set) var checklist: JourneyChecklist { didSet { persist() } }
    @Published private(set) var suggestion: PlanSuggestion?
    @Published private(set) var undoPlan: Plan?
    @Published var stepFreeRoutes: Bool {
        didSet {
            persist()
            routeChoice = stepFreeRoutes ? .stepFree : .direct
        }
    }
    @Published var routeChoice: RouteChoice = .direct {
        didSet {
            guard routeChoice != oldValue else { return }
            refreshPlanGuidance()
        }
    }
    @Published var onboardingSeen: Bool { didSet { persist() } }
    @Published var firstName: String { didSet { persist() } }
    @Published var lastName: String { didSet { persist() } }
    @Published var baggagePreference: BaggagePreference { didSet { persist() } }
    @Published var profilePhoto: UIImage? { didSet { ProfilePhotoStore.save(profilePhoto) } }
    @Published private(set) var toast: ToastMessage?
    /// The traveller's saved trip flight as they last confirmed it (Edit flight details).
    @Published private(set) var tripFlight: TripFlight { didSet { persist() } }
    /// Edits in progress on Edit flight details, applied on Save flight.
    @Published var flightDraft: TripFlight
    /// Flights the traveller typed in on Add a flight › Add manually.
    @Published private(set) var manualFlights: [ManualFlight] { didSet { persist() } }
    /// "+1 checked bag" declared on Extra baggage.
    @Published var extraBagDeclared: Bool { didSet { persist() } }
    /// A 30-minute visit to the Terminal 2 Observation Deck (landside).
    @Published var t2VisitPlanned: Bool { didSet { persist() } }
    private var toastAction: (() -> Void)?
    @Published private(set) var health: HealthConnection { didSet { persist() } }
    @Published private(set) var walkingSpeedKmh: Double?
    @Published private(set) var lastHealthSync: Date?
    @Published var routeStep = 1
    @Published private(set) var returningDirectly = false
    /// The camera pop-up on Route is showing; `cameraAllowed` ticks when access is granted.
    @Published var asksForCamera = false
    @Published var cameraAllowed = 0

    /// Airport local time the journey is shown at. The sample journey stays at 12:00.
    @Published private(set) var now: ClockTime = SampleJourney.now
    /// Latest departure-flight report from the flight-status feed.
    @Published private(set) var feed: FlightFeed? { didSet { persist() } }
    /// Alerts the traveller has been shown, keyed by kind.
    @Published private(set) var alerts: [AlertKind: AlertRecord] { didSet { persist() } }
    /// Set when a new alert should open the Alerts screen.
    @Published var alertToPresent: AlertKind?

    /// Seeded queue report for Curacion Cafe in the sample journey: the wait is now about 18 min.
    let cafeQueueUpdate = QueueUpdate(stopID: .cafe, waitMinutes: 18)
    private var queueUpdateHandled: Bool { didSet { persist() } }

    private let walkingData: WalkingDataSource
    private let defaults: UserDefaults
    private static let stateKey = "journeyState.v1"

    /// Shared with the plan card's one-time hint ("Tap a stop to change its times").
    static let planHintKey = "planHintSeen"

    init(walkingData: WalkingDataSource, defaults: UserDefaults = .standard, reset: Bool = false) {
        self.walkingData = walkingData
        self.defaults = defaults
        if reset {
            defaults.removeObject(forKey: Self.stateKey)
            defaults.removeObject(forKey: Self.planHintKey)
        }
        let saved = defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(SavedState.self, from: $0) }
        plan = saved?.plan ?? Plan()
        checklist = saved?.checklist ?? .haneda
        stepFreeRoutes = saved?.stepFreeRoutes ?? false
        firstName = saved?.firstName ?? ""
        lastName = saved?.lastName ?? ""
        baggagePreference = saved?.baggagePreference ?? .taggedThrough
        tripFlight = saved?.tripFlight ?? .sample
        flightDraft = saved?.tripFlight ?? .sample
        manualFlights = saved?.manualFlights ?? []
        extraBagDeclared = saved?.extraBagDeclared ?? false
        t2VisitPlanned = saved?.t2VisitPlanned ?? false
        profilePhoto = reset ? nil : ProfilePhotoStore.load()
        health = saved?.health ?? .notConnected
        queueUpdateHandled = saved?.queueUpdateHandled ?? false
        onboardingSeen = saved?.onboardingSeen ?? false
        feed = saved?.feed
        alerts = saved?.alerts ?? [:]
        routeChoice = (saved?.stepFreeRoutes ?? false) ? .stepFree : .direct
        refreshSuggestion()
    }

    // MARK: Flight status and situations

    /// The next flight leaves from Narita (NH 6 chosen on Edit flight details).
    var isAirportTransfer: Bool { tripFlight.number == "NH 6" }

    /// The ticket's departure flight.
    var outbound: FlightLeg { isAirportTransfer ? SampleJourney.naritaOutbound : SampleJourney.outbound }

    /// Time between landing at Haneda and the next departure.
    var layoverMinutes: Int { outbound.departs - SampleJourney.inbound.arrives }

    /// The gate to show everywhere: the feed's latest gate, or the one on the ticket.
    var gate: String {
        if let reported = feed?.gate, !reported.isEmpty { return reported }
        return outbound.departureGate
    }

    var gateAssignmentRevision: Int { feed?.assignmentRevision ?? 0 }

    var conditionInputs: ConditionInputs {
        let schedule = schedule
        let leave = schedule.stops.isEmpty
            ? SampleJourney.gateArrivalTarget - gateWalkMinutes
            : min(schedule.leave, SampleJourney.gateArrivalTarget - schedule.walkToGate)
        return ConditionInputs(
            now: now,
            ticketGate: outbound.departureGate,
            feed: feed,
            gateCloses: outbound.gateCloses,
            walkToGate: gateWalkMinutes,
            leaveBy: leave,
            atGate: checklist.steps.first { $0.id == "gate" }?.state == .confirmed,
            departsFromAnotherAirport: isAirportTransfer
        )
    }

    /// Situations that hold right now, most urgent first.
    var conditions: [JourneyCondition] { JourneyConditions.evaluate(conditionInputs) }
    var primaryCondition: JourneyCondition? { conditions.first }

    /// A gate update can coexist with a time-sensitive return decision.
    var timingCondition: JourneyCondition? {
        conditions.first {
            switch $0 {
            case .returnNow, .boardingAtRisk, .arrivesAfterClosure: true
            default: false
            }
        }
    }

    var hasTimingSituation: Bool { timingCondition != nil }

    /// "Boarding soon" from 30 minutes before boarding.
    var flightStatus: String { now >= SampleJourney.boarding - 30 ? "Boarding soon" : outbound.status }

    /// Sets the airport time the journey is shown at (sample data and tests).
    func setNow(_ time: ClockTime) {
        now = time
        refreshSuggestion()
        refreshAlerts()
    }

    /// A departure-flight report arrived from the feed.
    func receive(_ report: FlightFeed) {
        guard let reportedGate = report.gate, !reportedGate.isEmpty,
              feed.map({ report.receivedAt >= $0.receivedAt }) ?? true else { return }
        if reportedGate == gate {
            if feed == nil { feed = report }
            return
        }
        var update = report
        update.previousGate = gate
        update.assignmentRevision = gateAssignmentRevision + 1
        checklist.reopenGate()
        routeStep = 1
        alerts.removeValue(forKey: .gateChange)
        alerts.removeValue(forKey: .returnNow)
        alerts.removeValue(forKey: .boardingAtRisk)
        feed = update
        refreshAlerts()
        alertToPresent = .gateChange
    }

    /// The sample journey's gate update: Gate 108A, reported a short while after the app opens.
    func startSampleFeed(after delay: Duration) {
        guard feed == nil, !isAirportTransfer else { return refreshAlerts() }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard feed == nil, !isAirportTransfer else { return }
            receive(FlightFeed(gate: "108A", receivedAt: now))
        }
    }

    /// Records alerts for situations that just began and asks to show the most urgent new one.
    func refreshAlerts() {
        var newest: AlertKind?
        for condition in conditions.reversed() {
            guard let kind = condition.alertKind, alerts[kind] == nil else { continue }
            let issued = kind == .gateChange ? (feed?.receivedAt ?? now) : now
            alerts[kind] = AlertRecord(issuedAt: issued)
            newest = kind
        }
        if let newest { alertToPresent = newest }
    }

    func alertSeen(_ kind: AlertKind) {
        guard var record = alerts[kind], record.firstSeen == nil else { return }
        record.firstSeen = Date()
        alerts[kind] = record
    }

    /// "Heading to the gate": the traveller acted on the alert.
    func acknowledge(_ kind: AlertKind) {
        alerts[kind]?.acknowledged = true
    }

    // MARK: Walking

    var pace: WalkingPace {
        WalkingEstimate.pace(walks: SampleJourney.airportWalks, healthKmh: health == .connected ? walkingSpeedKmh : nil)
    }

    var schedule: Schedule { schedule(for: routeChoice) }

    func schedule(for choice: RouteChoice) -> Schedule {
        let timedPlan = queueUpdateHandled ? plan : PlanEngine.applying(cafeQueueUpdate, to: plan)
        return PlanEngine.schedule(timedPlan, pace: pace, directWalk: gateWalkMinutes(for: choice),
                                   gateWalkAdjustment: gateWalkAdjustment(for: choice), notBefore: now)
    }

    var guidesDirectlyToGate: Bool { returningDirectly || hasTimingSituation }

    func guidanceSchedule(for choice: RouteChoice) -> Schedule {
        if guidesDirectlyToGate {
            return PlanEngine.schedule(Plan(), pace: pace, directWalk: gateWalkMinutes(for: choice))
        }
        return schedule(for: choice)
    }

    func openRoute(directToGate: Bool = false) {
        returningDirectly = directToGate
        routeStep = 1
        tab = .route
    }

    func finishRoute() {
        returningDirectly = false
        routeStep = 1
        tab = .flight
    }

    private func gateWalkAdjustment(for choice: RouteChoice) -> Int {
        gateWalkMinutes(for: choice) - gateWalkMinutes(for: .direct)
    }

    func walkMinutes(_ from: PlaceID, _ to: PlaceID) -> Int { WalkMatrix.minutes(from, to, pace: pace) }

    /// Walk from a venue back to the gate, as on the Layover cards and Return to gate screens (4, 6 and 8 min on average).
    func venueToGateMinutes(_ place: PlaceID) -> Int {
        let average: Int = switch place {
        case .anaLounge: 4
        case .cafe: 6
        case .bento: 3
        case .udon: 7
        case .sushi: 6
        default: 8
        }
        return WalkingTimes.minutes(average: average, pace: pace)
    }

    /// Walk from here to the gate on the chosen route.
    var gateWalkMinutes: Int { gateWalkMinutes(for: routeChoice) }

    func gateWalkMinutes(for choice: RouteChoice) -> Int {
        WalkingTimes.minutes(average: choice.averageMinutes, pace: pace)
    }

    var healthAvailable: Bool { walkingData.isAvailable }

    func connectHealth() async {
        do {
            try await walkingData.requestAccess()
            health = .connected
            await refreshWalkingSpeed()
        } catch {
            health = .notConnected
        }
    }

    func refreshWalkingSpeed() async {
        guard health == .connected else { return }
        walkingSpeedKmh = try? await walkingData.averageWalkingSpeedKmh()
        lastHealthSync = Date()
        refreshSuggestion()
    }

    func removeHealth() {
        health = .removed
        walkingSpeedKmh = nil
        lastHealthSync = nil
        refreshSuggestion()
    }

    // MARK: Plan

    func add(_ stop: PlanStop) {
        guard !plan.contains(stop.id) else { return }
        clearUndo()
        plan.stops.append(stop)
        plan.stops.sort { StopTimes.arrive($0) < StopTimes.arrive($1) }
        refreshPlanGuidance()
    }

    func remove(_ id: PlaceID) {
        clearUndo()
        plan.stops.removeAll { $0.id == id }
        refreshPlanGuidance()
    }

    /// Resolve the displayed stop times from the same schedule that drives gate guidance.
    func times(_ id: PlaceID) -> (arrive: ClockTime, leave: ClockTime, latest: ClockTime)? {
        let timed = schedule
        guard let index = timed.stops.firstIndex(where: { $0.stop.id == id }) else { return nil }
        let stop = timed.stops[index]
        let downstream = timed.arriveAtGate - stop.end
        return (stop.start, stop.end, SampleJourney.gateArrivalTarget - downstream)
    }

    func earliestArrival(for id: PlaceID) -> ClockTime? {
        let stops = schedule.stops
        guard let index = stops.firstIndex(where: { $0.stop.id == id }) else { return nil }
        let departure = index == 0 ? now : stops[index - 1].end
        return max(StopTimes.earliest, departure + stops[index].walkFromPrevious)
    }

    func earliestLeave(for id: PlaceID) -> ClockTime? {
        guard let stop = schedule.stops.first(where: { $0.stop.id == id }) else { return nil }
        return stop.start + stop.stop.waitMinutes + PlanEngine.minimumVisit
    }

    func canLeave(_ id: PlaceID, at leave: ClockTime) -> Bool {
        earliestLeave(for: id).map { leave >= $0 } ?? false
    }

    func setTimes(_ id: PlaceID, arrive: ClockTime? = nil, leave: ClockTime? = nil) {
        guard let index = plan.index(of: id), let current = times(id) else { return }
        let wait = id == cafeQueueUpdate.stopID && !queueUpdateHandled
            ? cafeQueueUpdate.waitMinutes : plan.stops[index].waitMinutes
        let newVisit = leave.map { $0 - current.arrive - wait } ?? plan.stops[index].plannedVisitMinutes
        guard newVisit >= PlanEngine.minimumVisit else { return }
        clearUndo()
        if let arrive { plan.stops[index].arrive = arrive }
        plan.stops[index].visitMinutes = newVisit
        plan.stops[index].leave = nil
        plan.stops.sort { StopTimes.arrive($0) < StopTimes.arrive($1) }
        refreshPlanGuidance()
    }

    /// Restore the removed stop without replacing edits to other stops.
    func removeWithUndo(_ id: PlaceID) {
        guard let index = plan.index(of: id) else { return }
        let stop = plan.stops[index]
        remove(id)
        showToast(ToastMessage(text: "Removed \(stop.name)", action: "Undo")) { [weak self] in
            guard let self, !self.plan.contains(id) else { return }
            self.plan.stops.insert(stop, at: min(index, self.plan.stops.count))
            self.plan.stops.sort { StopTimes.arrive($0) < StopTimes.arrive($1) }
            self.refreshPlanGuidance()
        }
    }

    private func refreshPlanGuidance() {
        routeStep = 1
        refreshSuggestion()
        refreshAlerts()
    }

    /// Compare the proposed stop using the same arrival calculation as the plan.
    func fitWarning(for stop: PlanStop) -> (title: String, message: String)? {
        var proposed = plan
        proposed.stops.append(stop)
        if !queueUpdateHandled { proposed = PlanEngine.applying(cafeQueueUpdate, to: proposed) }
        proposed.stops.sort { StopTimes.arrive($0) < StopTimes.arrive($1) }
        let arrival = PlanEngine.schedule(proposed, pace: pace, gateWalkAdjustment: gateWalkAdjustment(for: routeChoice),
                                          notBefore: now).arriveAtGate
        guard arrival > SampleJourney.gateArrivalTarget,
              stop.id.meal?.sitDown == true || plan.stops.count >= 3 else { return nil }
        let message = "Estimated arrival at Gate \(gate) is \(arrival). Aim to be there by \(SampleJourney.gateArrivalTarget)."
        return (stop.id.meal?.sitDown == true ? "A sit-down meal may not fit" : "That's a lot to fit in", message)
    }

    /// Positive slack is measured against the planning target, after the remaining route.
    var minutesToSpare: Int {
        let arrival = plan.stops.isEmpty ? now + gateWalkMinutes : max(now, schedule.leave) + schedule.walkToGate
        return SampleJourney.gateArrivalTarget - arrival
    }

    /// Requested start times can conflict with the preceding walk or stop.
    func overlapping(_ id: PlaceID) -> [PlanStop] {
        let stops = schedule.stops
        guard let index = stops.firstIndex(where: { $0.stop.id == id }) else { return [] }
        if index > 0, let requested = stops[index].stop.arrive, requested < stops[index].start {
            return [stops[index - 1].stop]
        }
        return stops.dropFirst(index + 1).prefix(1).compactMap { following in
            guard let requested = following.stop.arrive, requested < following.start else { return nil }
            return following.stop
        }
    }

    func replacePlan(with edited: Plan) {
        clearUndo()
        plan = edited
        refreshPlanGuidance()
    }

    func applySuggestion() {
        guard let suggestion, suggestion.basePlan == plan else { return refreshSuggestion() }
        undoPlan = plan
        plan = suggestion.proposed
        queueUpdateHandled = true
        refreshPlanGuidance()
        showToast(ToastMessage(text: "Plan updated", action: "Undo")) { [weak self] in
            self?.undoSuggestion()
        }
    }

    /// Keeps the selected stops as they are. The longer queue still counts toward the timing.
    func keepPlan() {
        guard let suggestion, suggestion.basePlan == plan else { return refreshSuggestion() }
        plan = PlanEngine.applying(suggestion.update, to: plan)
        queueUpdateHandled = true
        refreshPlanGuidance()
    }

    func undoSuggestion() {
        guard let previous = undoPlan else { return }
        undoPlan = nil
        plan = previous
        queueUpdateHandled = false
        refreshPlanGuidance()
    }

    func clearUndo() { undoPlan = nil }

    /// Recomputes from the active plan; a suggestion for an older plan is dropped.
    private func refreshSuggestion() {
        guard !queueUpdateHandled, plan.contains(cafeQueueUpdate.stopID) else {
            suggestion = nil
            return
        }
        suggestion = PlanEngine.suggestion(for: plan, update: cafeQueueUpdate, pace: pace,
                                           gateWalkAdjustment: gateWalkAdjustment(for: routeChoice), notBefore: now)
    }

    // MARK: Journey steps

    func confirmStep(_ id: String, assignmentRevision: Int? = nil) {
        guard id != "gate" || assignmentRevision == gateAssignmentRevision else { return }
        checklist.confirm(id)
        refreshAlerts()
    }
    func skipStep(_ id: String) { checklist.skip(id) }
    func undoStep() { checklist.undo() }

    // MARK: Preferences

    func resetPreferences() {
        stepFreeRoutes = false
        baggagePreference = .taggedThrough
        plan = Plan()
        undoPlan = nil
        checklist = isAirportTransfer ? .narita : .haneda
        queueUpdateHandled = false
        routeStep = 1
        UserDefaults.standard.removeObject(forKey: Self.planHintKey)
        refreshSuggestion()
        refreshAlerts()
        showToast(ToastMessage(text: "Trip preferences reset"))
    }

    // MARK: Saved flights

    func beginEditingFlight() { flightDraft = tripFlight }
    func saveFlightDraft() {
        let changedAirport = (flightDraft.number == "NH 6") != isAirportTransfer
        tripFlight = flightDraft
        if changedAirport {
            checklist = isAirportTransfer ? .narita : .haneda
            feed = nil
            alerts = [:]
            alertToPresent = nil
            returningDirectly = false
            routeStep = 1
        }
        refreshAlerts()
    }
    func addManualFlight(_ flight: ManualFlight) { manualFlights.append(flight) }

    // MARK: Toasts (Figma section "Toasts")

    func showToast(_ message: ToastMessage, action: (() -> Void)? = nil) {
        toast = message
        toastAction = action
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if toast == message { toast = nil; toastAction = nil }
        }
    }

    func performToastAction() {
        toastAction?()
        toast = nil
        toastAction = nil
    }

    // MARK: Persistence

    private struct SavedState: Codable {
        var plan: Plan
        var checklist: JourneyChecklist
        var stepFreeRoutes: Bool
        var firstName: String?
        var lastName: String?
        var baggagePreference: BaggagePreference?
        var tripFlight: TripFlight?
        var manualFlights: [ManualFlight]?
        var extraBagDeclared: Bool?
        var t2VisitPlanned: Bool?
        var health: HealthConnection
        var queueUpdateHandled: Bool
        var onboardingSeen: Bool?
        var feed: FlightFeed?
        var alerts: [AlertKind: AlertRecord]?
    }

    private func persist() {
        let state = SavedState(
            plan: plan,
            checklist: checklist,
            stepFreeRoutes: stepFreeRoutes,
            firstName: firstName,
            lastName: lastName,
            baggagePreference: baggagePreference,
            tripFlight: tripFlight,
            manualFlights: manualFlights,
            extraBagDeclared: extraBagDeclared,
            t2VisitPlanned: t2VisitPlanned,
            health: health,
            queueUpdateHandled: queueUpdateHandled,
            onboardingSeen: onboardingSeen,
            feed: feed,
            alerts: alerts
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }
}

/// The traveller's profile photo, kept in the app's Documents folder on this iPhone.
enum ProfilePhotoStore {
    private static var url: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("profile-photo.jpg")
    }

    static func load() -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage?) {
        guard let url else { return }
        if let data = image?.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .completeFileProtection)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Editable details of the saved trip flight (Figma "Edit flight details").
struct TripFlight: Codable, Equatable {
    var number: String
    var date: String
    var purpose: String

    static let sample = TripFlight(number: "NH 106", date: SampleJourney.outbound.date, purpose: "Business meetings")
    static let flights = [("NH 106", "HND → LAX"), ("NH 6", "NRT → LAX")]
    static let dates = ["2026-10-15", "2026-10-16", "2026-10-17"]
    static let purposes = ["Business meetings", "Tourism", "Transit"]

    var route: String { Self.flights.first { $0.0 == number }?.1 ?? "" }
}

/// A flight typed in by the traveller. Only what they entered is stored; no live status is shown.
struct ManualFlight: Codable, Hashable, Identifiable {
    var id = UUID()
    let number: String
    let date: String
}

enum TripDate {
    private static func parse(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: iso)
    }

    static func isValid(_ iso: String) -> Bool { parse(iso) != nil }

    /// "15 Oct", "15 Oct 2026", "15 October 2026", "15 OCT".
    static func format(_ iso: String, _ pattern: String) -> String {
        guard let date = parse(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
