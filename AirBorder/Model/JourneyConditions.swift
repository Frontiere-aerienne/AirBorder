import Foundation

/// What the flight-status feed reports for the departure flight.
///
/// Today the sample journey supplies it. Once the app talks to the AirBorder backend
/// (`/v1/flights/:id`), the same values come from the airline data feed instead.
struct FlightFeed: Codable, Equatable {
    /// Departure gate reported by the feed, e.g. "108A". Nil when the feed has not reported one.
    var gate: String?
    /// When the update was received, in airport local time.
    var receivedAt: ClockTime
    /// Previous displayed assignment for the latest actual gate change.
    var previousGate: String? = nil
}

/// A situation the traveller needs to know about. Each one appears only while its condition holds.
enum JourneyCondition: Hashable {
    /// Under 10 minutes to spare after the walk to the gate.
    case boardingAtRisk(closesIn: Int, walk: Int)
    /// Past the time to leave for the gate, with 10 minutes or more to spare.
    case returnNow(closesIn: Int, walk: Int)
    /// The departure gate differs from the previous assignment.
    case gateChanged(from: String, to: String)
    /// The walk would end after the gate closes.
    case arrivesAfterClosure(arrival: ClockTime, minutesLate: Int)
    /// The next flight leaves from another airport (Haneda → Narita).
    case airportTransfer

    /// Timing constraints take priority over gate information.
    var priority: Int {
        switch self {
        case .arrivesAfterClosure: 0
        case .boardingAtRisk: 1
        case .returnNow: 2
        case .gateChanged: 3
        case .airportTransfer: 4
        }
    }

    var alertKind: AlertKind? {
        switch self {
        case .gateChanged: .gateChange
        case .returnNow: .returnNow
        case .boardingAtRisk: .boardingAtRisk
        case .arrivesAfterClosure, .airportTransfer: nil
        }
    }
}

/// Alerts that open the Figma "Alerts" screen.
enum AlertKind: String, Codable, Hashable, CaseIterable {
    case gateChange, returnNow, boardingAtRisk
}

struct AlertPresentation: Hashable {
    let kind: AlertKind
    let recordID: UUID?
}

struct ConditionInputs {
    var now: ClockTime
    var ticketGate: String
    var feed: FlightFeed?
    /// Nil when the gate-closing time is not known; timing situations are then not worked out.
    var gateCloses: ClockTime?
    var walkToGate: Int
    /// When the traveller needs to leave for the gate (after any stops in their plan).
    var leaveBy: ClockTime
    /// The traveller confirmed they are at the gate (Journey steps › Gate).
    var atGate: Bool
    /// The next flight leaves from a different airport than the one the traveller landed at.
    var departsFromAnotherAirport: Bool
}

enum JourneyConditions {
    /// Minutes to spare below which boarding is at risk.
    static let tightMargin = 10

    static func evaluate(_ input: ConditionInputs) -> [JourneyCondition] {
        if input.departsFromAnotherAirport { return [.airportTransfer] }
        var found: [JourneyCondition] = []
        let previousGate = input.feed?.previousGate ?? input.ticketGate
        if let gate = input.feed?.gate, !gate.isEmpty, gate != previousGate {
            found.append(.gateChanged(from: previousGate, to: gate))
        }
        if !input.atGate, let closes = input.gateCloses {
            let arrival = input.now + input.walkToGate
            let spare = closes - arrival
            let closesIn = closes - input.now
            if spare < 0 {
                found.append(.arrivesAfterClosure(arrival: arrival, minutesLate: -spare))
            } else if spare < tightMargin {
                found.append(.boardingAtRisk(closesIn: closesIn, walk: input.walkToGate))
            } else if input.now >= input.leaveBy {
                found.append(.returnNow(closesIn: closesIn, walk: input.walkToGate))
            }
        }
        return found.sorted { $0.priority < $1.priority }
    }
}

/// Whether the traveller has seen and acted on an alert.
struct AlertRecord: Codable, Equatable {
    /// Optional so alerts saved before this field was introduced can still be restored.
    var id: UUID? = UUID()
    /// Airport time the situation began, shown as "15 Oct, 12:00".
    var issuedAt: ClockTime
    /// When the Alerts screen first showed it.
    var firstSeen: Date?
    /// The traveller tapped Route ("Heading to the gate").
    var acknowledged = false

    /// Seen at least once, not acted on, and seen long enough ago to repeat as a reminder.
    func isReminder(at date: Date, after interval: TimeInterval = AlertRecord.reminderInterval) -> Bool {
        guard !acknowledged, let firstSeen else { return false }
        return date.timeIntervalSince(firstSeen) >= interval
    }

    static let reminderInterval: TimeInterval = 5 * 60
}
