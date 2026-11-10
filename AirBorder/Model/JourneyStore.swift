import Foundation
import SwiftUI

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
}

/// Figma "Choose a route" options. Minutes are the average walking times for each route.
enum RouteChoice: String, CaseIterable, Codable {
    case direct, stepFree, lessCrowded

    var title: String {
        switch self {
        case .direct: return "Direct"
        case .stepFree: return "Step-free"
        case .lessCrowded: return "Less crowded"
        }
    }

    var detail: String {
        switch self {
        case .direct: return "Shortest walking route"
        case .stepFree: return "Use lifts and level corridors"
        case .lessCrowded: return "Avoid the busy central corridor"
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
    @Published var routeChoice: RouteChoice = .direct
    @Published var onboardingSeen: Bool { didSet { persist() } }
    @Published var travellerName: String { didSet { persist() } }
    @Published private(set) var health: HealthConnection { didSet { persist() } }
    @Published private(set) var walkingSpeedKmh: Double?
    @Published private(set) var lastHealthSync: Date?
    @Published var routeStep = 1

    /// Seeded queue report for Curacion Cafe in the sample journey: the wait is now about 18 min.
    let cafeQueueUpdate = QueueUpdate(stopID: .cafe, waitMinutes: 18)
    private var queueUpdateHandled: Bool { didSet { persist() } }

    private let walkingData: WalkingDataSource
    private let defaults: UserDefaults
    private static let stateKey = "journeyState.v1"

    init(walkingData: WalkingDataSource, defaults: UserDefaults = .standard, reset: Bool = false) {
        self.walkingData = walkingData
        self.defaults = defaults
        if reset { defaults.removeObject(forKey: Self.stateKey) }
        let saved = defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(SavedState.self, from: $0) }
        plan = saved?.plan ?? Plan()
        checklist = saved?.checklist ?? .haneda
        stepFreeRoutes = saved?.stepFreeRoutes ?? false
        travellerName = saved?.travellerName ?? ""
        health = saved?.health ?? .notConnected
        queueUpdateHandled = saved?.queueUpdateHandled ?? false
        onboardingSeen = saved?.onboardingSeen ?? false
        routeChoice = (saved?.stepFreeRoutes ?? false) ? .stepFree : .direct
        refreshSuggestion()
    }

    // MARK: Walking

    var pace: WalkingPace {
        if health == .connected, let walkingSpeedKmh { return .personal(kmh: walkingSpeedKmh) }
        return .average
    }

    var schedule: Schedule { PlanEngine.schedule(plan, pace: pace) }

    func walkMinutes(_ from: PlaceID, _ to: PlaceID) -> Int { WalkMatrix.minutes(from, to, pace: pace) }

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
        refreshSuggestion()
    }

    func remove(_ id: PlaceID) {
        clearUndo()
        plan.stops.removeAll { $0.id == id }
        refreshSuggestion()
    }

    func replacePlan(with edited: Plan) {
        clearUndo()
        plan = edited
        refreshSuggestion()
    }

    func applySuggestion() {
        guard let suggestion, suggestion.basePlan == plan else { return refreshSuggestion() }
        undoPlan = plan
        plan = suggestion.proposed
        queueUpdateHandled = true
        self.suggestion = nil
    }

    /// Keeps the selected stops as they are. The longer queue still counts toward the timing.
    func keepPlan() {
        guard let suggestion, suggestion.basePlan == plan else { return refreshSuggestion() }
        plan = PlanEngine.applying(suggestion.update, to: plan)
        queueUpdateHandled = true
        self.suggestion = nil
    }

    func undoSuggestion() {
        guard let previous = undoPlan else { return }
        undoPlan = nil
        plan = previous
        queueUpdateHandled = false
        refreshSuggestion()
    }

    func clearUndo() { undoPlan = nil }

    /// Recomputes from the active plan; a suggestion for an older plan is dropped.
    private func refreshSuggestion() {
        guard !queueUpdateHandled, plan.contains(cafeQueueUpdate.stopID) else {
            suggestion = nil
            return
        }
        suggestion = PlanEngine.suggestion(for: plan, update: cafeQueueUpdate, pace: pace)
    }

    // MARK: Journey steps

    func confirmStep(_ id: String) { checklist.confirm(id) }
    func skipStep(_ id: String) { checklist.skip(id) }
    func undoStep() { checklist.undo() }

    // MARK: Preferences

    func resetPreferences() {
        stepFreeRoutes = false
        travellerName = ""
        plan = Plan()
        undoPlan = nil
        checklist = .haneda
        queueUpdateHandled = false
        routeStep = 1
        refreshSuggestion()
    }

    // MARK: Persistence

    private struct SavedState: Codable {
        var plan: Plan
        var checklist: JourneyChecklist
        var stepFreeRoutes: Bool
        var travellerName: String
        var health: HealthConnection
        var queueUpdateHandled: Bool
        var onboardingSeen: Bool?
    }

    private func persist() {
        let state = SavedState(
            plan: plan,
            checklist: checklist,
            stepFreeRoutes: stepFreeRoutes,
            travellerName: travellerName,
            health: health,
            queueUpdateHandled: queueUpdateHandled,
            onboardingSeen: onboardingSeen
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }
}
