import SwiftUI
import UIKit

/// Motion and touch feedback shared by AirBorder screens.
extension Animation {
    /// Strong ease-out: starts fast so the screen answers the tap right away.
    static let abOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.25)
    /// Press feedback, shorter than any state change.
    static let abPress = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
}

/// Buttons scale down slightly while pressed, so every tap feels heard.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.abPress, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Light haptics for the few moments that change the trip: steps, plan edits, arrival and gate changes.
@MainActor
enum Haptics {
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
