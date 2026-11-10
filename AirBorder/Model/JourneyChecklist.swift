import Foundation

enum StepState: String, Codable {
    case pending, confirmed, skipped
}

struct JourneyStep: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    /// Steps that may not apply to every traveller offer "Not needed".
    let canSkip: Bool
    var state: StepState = .pending
}

/// Departure-to-arrival checkpoints for the Haneda connection.
///
/// "Now" is the first step the traveller has not confirmed or marked not needed. It is never
/// inferred from location.
struct JourneyChecklist: Codable, Equatable {
    var steps: [JourneyStep]
    private(set) var lastChange: Change?

    struct Change: Codable, Equatable {
        let stepID: String
        let previous: StepState
    }

    static let haneda = JourneyChecklist(steps: [
        JourneyStep(id: "arrival", title: "Arrival", canSkip: false, state: .confirmed),
        JourneyStep(id: "connection", title: "Connection", canSkip: false, state: .confirmed),
        JourneyStep(id: "security", title: "Security", canSkip: false),
        JourneyStep(id: "passport", title: "Passport control", canSkip: true),
        JourneyStep(id: "gate", title: "Gate and boarding", canSkip: false),
    ])

    var currentIndex: Int? { steps.firstIndex { $0.state == .pending } }

    var nextIndex: Int? {
        guard let current = currentIndex else { return nil }
        return steps.indices.first { $0 > current && steps[$0].state == .pending }
    }

    var current: JourneyStep? { currentIndex.map { steps[$0] } }
    var next: JourneyStep? { nextIndex.map { steps[$0] } }
    var isComplete: Bool { currentIndex == nil }

    func canConfirm(_ id: String) -> Bool { current?.id == id }

    func canSkip(_ id: String) -> Bool {
        guard let step = steps.first(where: { $0.id == id }) else { return false }
        return step.canSkip && step.state == .pending
    }

    func canUndo(_ id: String) -> Bool { lastChange?.stepID == id }

    mutating func confirm(_ id: String) {
        guard canConfirm(id) else { return }
        set(id, .confirmed)
    }

    mutating func skip(_ id: String) {
        guard canSkip(id) else { return }
        set(id, .skipped)
    }

    mutating func undo() {
        guard let change = lastChange, let index = steps.firstIndex(where: { $0.id == change.stepID }) else { return }
        steps[index].state = change.previous
        lastChange = nil
    }

    private mutating func set(_ id: String, _ state: StepState) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        lastChange = Change(stepID: id, previous: steps[index].state)
        steps[index].state = state
    }

    func status(of step: JourneyStep) -> String {
        switch step.state {
        case .confirmed: return "Confirmed"
        case .skipped: return "Not needed"
        case .pending: return step.id == current?.id ? "Now" : "Next"
        }
    }
}
