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
    /// A firm, short bump when a control is already at its limit.
    static func limit() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7) }
}

/// A short horizontal shake; bump `shakes` by 1 inside an animation to play it once.
struct Shake: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(shakes * .pi * 4), y: 0))
    }
}

/// Children of a newly shown group arrive one after another, 40 ms apart.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear { withAnimation(.abOut.delay(Double(index) * 0.04)) { shown = true } }
    }
}

extension View {
    func staggered(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}
