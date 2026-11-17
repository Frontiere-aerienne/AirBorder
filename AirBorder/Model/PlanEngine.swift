// SUBSTANTIVE: Computes the connection schedule and constrained stop changes.

import Foundation

// MARK: - Walking

/// Where walking speed comes from. Personal pace is read from the connected Apple Health account;
/// without it, the app uses the airport's average walking times.
enum WalkingPace: Equatable {
    case average
    case personal(kmh: Double)
}

enum WalkingTimes {
    /// Metres covered per minute by the average walking times used below (4.2 km/h).
    static let averageMetresPerMinute = 70

    static func minutes(average baseMinutes: Int, pace: WalkingPace) -> Int {
        guard case let .personal(kmh) = pace, kmh >= 1, kmh <= 9 else { return baseMinutes }
        let metres = Double(baseMinutes * averageMetresPerMinute)
        let metresPerMinute = kmh * 1000 / 60
        return Int((metres / metresPerMinute - 1e-6).rounded(.up))
    }
}

/// A walk recorded at the airport on an earlier trip (Profile › Previous trips).
struct AirportWalk: Equatable {
    let metres: Int
    let minutes: Int
}

/// Walking estimates start from the traveller's airport walks and are refined by the walking speed
/// in their connected Apple Health account (equal weight). Without either, average walking times apply.
enum WalkingEstimate {
    static func kmh(walks: [AirportWalk]) -> Double? {
        let minutes = walks.map(\.minutes).reduce(0, +)
        guard minutes > 0 else { return nil }
        return Double(walks.map(\.metres).reduce(0, +)) * 60 / Double(minutes) / 1000
    }

    static func pace(walks: [AirportWalk], healthKmh: Double?) -> WalkingPace {
        switch (kmh(walks: walks), healthKmh) {
        case let (airport?, health?): return .personal(kmh: (airport + health) / 2)
        case let (airport?, nil): return .personal(kmh: airport)
        case let (nil, health?): return .personal(kmh: health)
        default: return .average
        }
    }
}

/// Stable routing identifiers. Reserved endpoints are independent of any airport.
struct PlaceID: RawRepresentable, Codable, Hashable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(rawValue)
    }

    static let start = PlaceID(rawValue: "start")
    static let gate = PlaceID(rawValue: "gate")
}

// Legacy identifiers retained for the bundled Haneda fixture and existing saves.
extension PlaceID {
    static let cafe = PlaceID(rawValue: "cafe")
    static let anaLounge = PlaceID(rawValue: "anaLounge")
    static let skyLounge = PlaceID(rawValue: "skyLounge")
    static let bento = PlaceID(rawValue: "bento")
    static let udon = PlaceID(rawValue: "udon")
    static let sushi = PlaceID(rawValue: "sushi")

    /// How long a meal usually takes here, and whether it is a sit-down meal (sample estimates).
    var meal: (minutes: Int, sitDown: Bool)? {
        switch self {
        case .cafe: (20, false)
        case .bento: (10, false)
        case .udon: (15, false)
        case .sushi: (45, true)
        default: nil
        }
    }

    /// 4F places are reached by lift from the 3F concourse.
    var requiresLift: Bool { self == .anaLounge || self == .skyLounge || self == .sushi }
    var floor: String { requiresLift ? "4F" : "3F" }

    /// Short label for the plan strip and the map.
    var shortLabel: String {
        switch self {
        case .anaLounge: "LOUNGE"
        case .skyLounge: "SKY LOUNGE"
        case .cafe: "Curacion Cafe"
        case .bento: "Bento"
        case .udon: "Udon"
        case .sushi: "Sushi"
        default: rawValue
        }
    }
}

/// The timing inputs for a particular journey. A missing path is not an estimate.
struct PlanningContext {
    let planStart: ClockTime
    let gateArrivalTarget: ClockTime
    let gateCloses: ClockTime?
    let timelineStart: ClockTime
    let timelineMinutes: Int
    let preferredArrivals: [PlaceID: ClockTime]
    /// Minutes at the reference walking pace, or nil without coverage.
    let averageWalkMinutes: (PlaceID, PlaceID) -> Int?

    init(planStart: ClockTime, gateArrivalTarget: ClockTime, gateCloses: ClockTime?,
         timelineStart: ClockTime? = nil, timelineMinutes: Int? = nil,
         preferredArrivals: [PlaceID: ClockTime] = [:],
         averageWalkMinutes: @escaping (PlaceID, PlaceID) -> Int?) {
        self.planStart = planStart
        self.gateArrivalTarget = gateArrivalTarget
        self.gateCloses = gateCloses
        self.timelineStart = timelineStart ?? planStart
        self.timelineMinutes = min(1440, max(1, timelineMinutes ?? (gateCloses ?? gateArrivalTarget) - self.timelineStart))
        self.preferredArrivals = preferredArrivals
        self.averageWalkMinutes = averageWalkMinutes
    }

    func walkMinutes(_ from: PlaceID, _ to: PlaceID, pace: WalkingPace) -> Int? {
        if from == to { return 0 }
        guard let average = averageWalkMinutes(from, to), (0...1440).contains(average) else { return nil }
        return WalkingTimes.minutes(average: average, pace: pace)
    }
}

// MARK: - Plan

struct PlanStop: Identifiable, Equatable, Codable {
    let id: PlaceID
    let name: String
    /// Used in "Remove café", "5 min walk from the café".
    let shortName: String
    var waitMinutes: Int
    var visitMinutes: Int
    /// The wait came from a queue update rather than the usual estimate.
    var queueUpdated = false
    /// Times the traveller chose on the Flight plan card; nil leaves the start to the journey’s timing plan.
    var arrive: ClockTime?
    var leave: ClockTime?

    /// Older saves may contain both chosen times. Recovery uses their original visit duration.
    var plannedVisitMinutes: Int {
        guard let arrive, let leave else { return visitMinutes }
        return max(0, leave - arrive - waitMinutes)
    }

    static let cafe = PlanStop(id: .cafe, name: "Curacion Cafe", shortName: "café", waitMinutes: 8, visitMinutes: 20)
    static let anaLounge = PlanStop(id: .anaLounge, name: "ANA LOUNGE", shortName: "lounge", waitMinutes: 0, visitMinutes: 28)
    static let skyLounge = PlanStop(id: .skyLounge, name: "SKY LOUNGE", shortName: "SKY LOUNGE", waitMinutes: 0, visitMinutes: 30)
    static let bento = PlanStop(id: .bento, name: "Bento & Onigiri To Go", shortName: "bento", waitMinutes: 0, visitMinutes: 10)
    static let udon = PlanStop(id: .udon, name: "Udon Noodle Counter", shortName: "udon", waitMinutes: 0, visitMinutes: 15)
    static let sushi = PlanStop(id: .sushi, name: "Sushi Restaurant", shortName: "sushi", waitMinutes: 0, visitMinutes: 45)
}

struct Plan: Equatable, Codable {
    var stops: [PlanStop] = []

    func contains(_ id: PlaceID) -> Bool { stops.contains { $0.id == id } }
    func index(of id: PlaceID) -> Int? { stops.firstIndex { $0.id == id } }
}

struct ScheduledStop: Equatable {
    let stop: PlanStop
    let walkFromPrevious: Int
    let previous: PlanStop?
    let start: ClockTime
    var end: ClockTime { start + stop.waitMinutes + stop.plannedVisitMinutes }
}

struct Schedule: Equatable {
    let stops: [ScheduledStop]
    /// When the traveller leaves for the gate (from the last stop, or from where they are).
    let leave: ClockTime
    let walkToGate: Int
    let arriveAtGate: ClockTime
    let gateCloses: ClockTime?
}

struct QueueUpdate: Equatable, Codable {
    let stopID: PlaceID
    let waitMinutes: Int
}

/// A proposed change computed from the active plan. Only applied after the traveller taps Apply.
struct PlanSuggestion: Equatable {
    let basePlan: Plan
    let update: QueueUpdate
    let proposed: Plan
    let extraMinutes: Int
    let delayedStop: PlanStop
    let shortenedStop: PlanStop
    let gateArrivalTarget: ClockTime

    var title: String { "Allow \(extraMinutes) more minutes for the \(delayedStop.shortName) queue" }
    var detail: String {
        "Shorten \(shortenedStop.name) to \(shortenedStop.visitMinutes) min to still arrive by \(gateArrivalTarget)."
    }
}

enum PlanEngine {
    static let minimumVisit = 10

    static func schedule(
        _ plan: Plan,
        pace: WalkingPace,
        context: PlanningContext,
        directWalk: Int? = nil,
        gateWalkAdjustment: Int = 0,
        notBefore: ClockTime? = nil
    ) -> Schedule? {
        let target = context.gateArrivalTarget
        guard context.gateCloses.map({ target <= $0 }) ?? true,
              plan.stops.allSatisfy({
                  $0.id != .start && $0.id != .gate
                    && (0...1440).contains($0.waitMinutes)
                    && (0...1440).contains($0.plannedVisitMinutes)
              }),
              Set(plan.stops.map(\.id)).count == plan.stops.count else { return nil }
        let start = context.planStart
        guard let first = plan.stops.first else {
            guard let walk = directWalk ?? context.walkMinutes(.start, .gate, pace: pace),
                  (0...1440).contains(walk) else { return nil }
            return Schedule(stops: [], leave: target - walk, walkToGate: walk,
                            arriveAtGate: target, gateCloses: context.gateCloses)
        }
        guard let firstWalk = context.walkMinutes(.start, first.id, pace: pace) else { return nil }
        let requestedStart = min(start, first.arrive.map { $0 - firstWalk } ?? start)
        var time = max(requestedStart, notBefore ?? requestedStart)
        var previousPlace = PlaceID.start
        var previousStop: PlanStop?
        var items: [ScheduledStop] = []
        for stop in plan.stops {
            guard let walk = context.walkMinutes(previousPlace, stop.id, pace: pace) else { return nil }
            time = max(time + walk, stop.arrive ?? time)
            let item = ScheduledStop(stop: stop, walkFromPrevious: walk, previous: previousStop, start: time)
            items.append(item)
            time = item.end
            previousPlace = stop.id
            previousStop = stop
        }
        guard let lastWalk = context.walkMinutes(previousPlace, .gate, pace: pace) else { return nil }
        let walk = max(1, lastWalk + gateWalkAdjustment)
        return Schedule(stops: items, leave: time, walkToGate: walk, arriveAtGate: time + walk, gateCloses: context.gateCloses)
    }

    /// Applies a queue update to a stop's wait without changing anything else.
    static func applying(_ update: QueueUpdate, to plan: Plan) -> Plan {
        var plan = plan
        guard (0...1440).contains(update.waitMinutes),
              let index = plan.index(of: update.stopID) else { return plan }
        plan.stops[index].visitMinutes = plan.stops[index].plannedVisitMinutes
        plan.stops[index].leave = nil
        plan.stops[index].waitMinutes = update.waitMinutes
        plan.stops[index].queueUpdated = true
        return plan
    }

    /// Recomputes timing with the update and, if the gate arrival would slip past the target,
    /// proposes shortening a later stop in the selected plan. Returns nil when no change is needed
    /// or no later stop can absorb the delay.
    static func suggestion(
        for plan: Plan, update: QueueUpdate, pace: WalkingPace, context: PlanningContext,
        gateWalkAdjustment: Int = 0, notBefore: ClockTime? = nil
    ) -> PlanSuggestion? {
        guard (0...1440).contains(update.waitMinutes),
              let index = plan.index(of: update.stopID) else { return nil }
        let extra = update.waitMinutes - plan.stops[index].waitMinutes
        guard extra > 0 else { return nil }
        let updated = applying(update, to: plan)
        guard let updatedSchedule = schedule(updated, pace: pace, context: context,
                                             gateWalkAdjustment: gateWalkAdjustment, notBefore: notBefore) else { return nil }
        let overrun = updatedSchedule.arriveAtGate - context.gateArrivalTarget
        guard overrun > 0 else { return nil }
        for candidate in plan.stops.indices.reversed() where candidate > index {
            let shortened = updated.stops[candidate].plannedVisitMinutes - overrun
            guard shortened >= minimumVisit else { continue }
            var proposed = updated
            proposed.stops[candidate].visitMinutes = shortened
            proposed.stops[candidate].leave = nil
            guard let revised = schedule(proposed, pace: pace, context: context,
                                         gateWalkAdjustment: gateWalkAdjustment, notBefore: notBefore),
                  revised.arriveAtGate <= context.gateArrivalTarget else { continue }
            return PlanSuggestion(
                basePlan: plan,
                update: update,
                proposed: proposed,
                extraMinutes: extra,
                delayedStop: updated.stops[index],
                shortenedStop: proposed.stops[candidate],
                gateArrivalTarget: context.gateArrivalTarget
            )
        }
        return nil
    }
}

// MARK: - Stop times (Flight plan card)

/// Arrive and leave times for each stop, changed in 15-minute steps. A stop never ends after the
/// latest time that still reaches the gate by the arrival target.
enum StopTimes {
    static let step = 15
    private static let gridOrigin = ClockTime(minutes: 0)

    /// The previous point on the 15-minute grid strictly before `time`.
    static func stepBefore(_ time: ClockTime) -> ClockTime {
        let offset = time - gridOrigin
        let steps = offset > 0 ? (offset - 1) / step : (offset - step) / step
        return gridOrigin + steps * step
    }

    /// The next point on the 15-minute grid strictly after `time`.
    static func stepAfter(_ time: ClockTime) -> ClockTime {
        let offset = time - gridOrigin
        let steps = offset >= 0 ? offset / step + 1 : -((-offset - 1) / step)
        return gridOrigin + steps * step
    }

    static func earlierArrive(_ arrive: ClockTime, earliestAllowed: ClockTime) -> ClockTime? {
        guard earliestAllowed < arrive else { return nil }
        return max(stepBefore(arrive), earliestAllowed)
    }

    static func laterArrive(_ arrive: ClockTime, latestAllowed: ClockTime) -> ClockTime? {
        let value = stepAfter(arrive)
        return value <= latestAllowed ? value : nil
    }

    static func earlierLeave(_ leave: ClockTime, earliestAllowed: ClockTime) -> ClockTime? {
        let value = stepBefore(leave)
        return value >= earliestAllowed ? value : nil
    }

    /// Later leave time, ending at `latest` exactly; nil once already there.
    static func laterLeave(_ leave: ClockTime, latest: ClockTime) -> ClockTime? {
        guard leave < latest else { return nil }
        return min(stepAfter(leave), latest)
    }


}

// MARK: - Text used by plan cards

enum PlanText {
    static func timing(_ item: ScheduledStop) -> String {
        var parts: [String] = []
        if item.stop.waitMinutes > 0 {
            parts.append(item.stop.queueUpdated ? "\(item.stop.waitMinutes) min for the queue" : "\(item.stop.waitMinutes) min wait")
        }
        parts.append("\(item.stop.visitMinutes) min visit")
        return "\(item.start)–\(item.end), " + parts.joined(separator: " + ")
    }

    static func walk(_ item: ScheduledStop) -> String? {
        guard item.walkFromPrevious > 0 else { return nil }
        guard let previous = item.previous else { return "\(item.walkFromPrevious) min walk" }
        let from = previous.shortName == "café" ? "the café" : previous.name
        return "\(item.walkFromPrevious) min walk from \(from)"
    }

    static func arrivalTitle(_ schedule: Schedule) -> String {
        "Arrive at your gate by \(schedule.arriveAtGate)"
    }

    static func arrivalDetail(_ schedule: Schedule) -> String {
        let closes = schedule.gateCloses.map { "Gate closes at \($0)." } ?? "Gate closing time unavailable."
        guard let last = schedule.stops.last else { return closes }
        return "Leave \(last.stop.name) at \(schedule.leave). \(closes)"
    }
}
