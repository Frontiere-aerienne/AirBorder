// SUBSTANTIVE: Resolves spoken route questions against the current journey state.
import Foundation

struct RouteVoiceConversation {
    enum Question { case gate, instruction }

    struct Guidance {
        let gate: String
        let instruction: String
    }

    private var lastQuestion: Question?

    mutating func answer(_ phrase: String, using guidance: Guidance) -> String {
        let words = phrase.lowercased().split { !$0.isLetter && !$0.isNumber }
        let question: Question
        if words.contains("repeat") || words == ["what", "about", "now"] || words == ["say", "that", "again"] {
            question = lastQuestion ?? .instruction
        } else if words.contains("next") || words.contains("directions") || words.contains("instruction")
                    || words.contains("where") && !words.contains("gate") {
            question = .instruction
        } else if words.contains("gate") {
            question = .gate
        } else {
            return "You can ask which gate, or what’s next."
        }
        lastQuestion = question
        switch question {
        case .gate: return "Gate \(guidance.gate)."
        case .instruction: return guidance.instruction
        }
    }
}
