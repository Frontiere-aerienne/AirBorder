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

/// Places in Haneda Terminal 3 a plan can visit.
enum PlaceID: String, Codable, Hashable, CaseIterable {
    case start, cafe, anaLounge, skyLounge, gate
}

/// Average walking minutes between places (Terminal 3, airside, 3F–4F).
enum WalkMatrix {
    static func averageMinutes(_ a: PlaceID, _ b: PlaceID) -> Int {
        if a == b { return 0 }
        switch Set([a, b]) {
        case [.start, .cafe]: return 0
        case [.start, .anaLounge]: return 5
        case [.start, .skyLounge]: return 8
        case [.start, .gate]: return 12
        case [.cafe, .anaLounge]: return 5
        case [.cafe, .gate]: return 8
        case [.anaLounge, .gate]: return 4
        default: return 8 // SKY LOUNGE legs use its 8 min card estimate
        }
    }

    static func minutes(_ a: PlaceID, _ b: PlaceID, pace: WalkingPace) -> Int {
        WalkingTimes.minutes(average: averageMinutes(a, b), pace: pace)
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

    static let cafe = PlanStop(id: .cafe, name: "Curacion Cafe", shortName: "café", waitMinutes: 8, visitMinutes: 20)
    static let anaLounge = PlanStop(id: .anaLounge, name: "ANA LOUNGE", shortName: "lounge", waitMinutes: 0, visitMinutes: 28)
    static let skyLounge = PlanStop(id: .skyLounge, name: "SKY LOUNGE", shortName: "SKY LOUNGE", waitMinutes: 0, visitMinutes: 30)
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
    var end: ClockTime { start + stop.waitMinutes + stop.visitMinutes }
}

struct Schedule: Equatable {
    let stops: [ScheduledStop]
    /// When the traveller leaves for the gate (from the last stop, or from where they are).
    let leave: ClockTime
    let walkToGate: Int
    let arriveAtGate: ClockTime
    let gateCloses: ClockTime
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

    var title: String { "Allow \(extraMinutes) more minutes for the \(delayedStop.shortName) queue" }
    var detail: String {
        "Shorten \(shortenedStop.name) to \(shortenedStop.visitMinutes) min to still arrive by \(SampleJourney.gateArrivalTarget)."
    }
}

enum PlanEngine {
    static let minimumVisit = 10

    static func schedule(
        _ plan: Plan,
        pace: WalkingPace,
        start: ClockTime = SampleJourney.planStart,
        target: ClockTime = SampleJourney.gateArrivalTarget,
        gateCloses: ClockTime = SampleJourney.outbound.gateCloses ?? SampleJourney.gateArrivalTarget
    ) -> Schedule {
        guard !plan.stops.isEmpty else {
            let walk = WalkMatrix.minutes(.start, .gate, pace: pace)
            return Schedule(stops: [], leave: target - walk, walkToGate: walk, arriveAtGate: target, gateCloses: gateCloses)
        }
        var time = start
        var previousPlace = PlaceID.start
        var previousStop: PlanStop?
        var items: [ScheduledStop] = []
        for stop in plan.stops {
            let walk = WalkMatrix.minutes(previousPlace, stop.id, pace: pace)
            time = time + walk
            let item = ScheduledStop(stop: stop, walkFromPrevious: walk, previous: previousStop, start: time)
            items.append(item)
            time = item.end
            previousPlace = stop.id
            previousStop = stop
        }
        let walk = WalkMatrix.minutes(previousPlace, .gate, pace: pace)
        return Schedule(stops: items, leave: time, walkToGate: walk, arriveAtGate: time + walk, gateCloses: gateCloses)
    }

    /// Applies a queue update to a stop's wait without changing anything else.
    static func applying(_ update: QueueUpdate, to plan: Plan) -> Plan {
        var plan = plan
        guard let index = plan.index(of: update.stopID) else { return plan }
        plan.stops[index].waitMinutes = update.waitMinutes
        plan.stops[index].queueUpdated = true
        return plan
    }

    /// Recomputes timing with the update and, if the gate arrival would slip past the target,
    /// proposes shortening a later stop in the selected plan. Returns nil when no change is needed
    /// or no later stop can absorb the delay.
    static func suggestion(for plan: Plan, update: QueueUpdate, pace: WalkingPace) -> PlanSuggestion? {
        guard let index = plan.index(of: update.stopID) else { return nil }
        let extra = update.waitMinutes - plan.stops[index].waitMinutes
        guard extra > 0 else { return nil }
        let updated = applying(update, to: plan)
        let overrun = schedule(updated, pace: pace).arriveAtGate - SampleJourney.gateArrivalTarget
        guard overrun > 0 else { return nil }
        for candidate in plan.stops.indices.reversed() where candidate > index {
            let shortened = updated.stops[candidate].visitMinutes - overrun
            guard shortened >= minimumVisit else { continue }
            var proposed = updated
            proposed.stops[candidate].visitMinutes = shortened
            return PlanSuggestion(
                basePlan: plan,
                update: update,
                proposed: proposed,
                extraMinutes: extra,
                delayedStop: updated.stops[index],
                shortenedStop: proposed.stops[candidate]
            )
        }
        return nil
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
        return "\(item.start)–\(item.end) · " + parts.joined(separator: " + ")
    }

    static func walk(_ item: ScheduledStop) -> String? {
        guard item.walkFromPrevious > 0 else { return nil }
        guard let previous = item.previous else { return "\(item.walkFromPrevious) min walk" }
        let from = previous.id == .cafe ? "the café" : previous.name
        return "\(item.walkFromPrevious) min walk from \(from)"
    }

    static func arrivalTitle(_ schedule: Schedule) -> String {
        "Arrive at your gate by \(schedule.arriveAtGate)"
    }

    static func arrivalDetail(_ schedule: Schedule) -> String {
        let closes = "Gate closes at \(schedule.gateCloses)."
        guard let last = schedule.stops.last else { return closes }
        return "Leave \(last.stop.name) at \(schedule.leave). \(closes)"
    }
}
