// SUBSTANTIVE: Renders confirmed replay positions without advancing the passenger's actual route.
import RealityKit
import SwiftUI
import UIKit

struct DrivenCameraGuidanceView<Actions: View>: View {
    let guidance: TerminalGuidance
    var passageBlocked = false
    var pedestrians: [DriverPedestrian] = []
    let end: () -> Void
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                TerminalInterior(reading: guidance.position, passageBlocked: passageBlocked,
                                 pedestrians: pedestrians)
                    .accessibilityHidden(true)
                if let location = guidance.location {
                    Text(location)
                        .outfitText(15, .bold, AB.ticket)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(AB.ice, in: Capsule())
                        .padding(12)
                        .accessibilityIdentifier("guidanceLocation")
                }
            }
            .frame(height: guidance.checkpoint == nil ? 320 : 248)
            .clipShape(RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let turn = guidance.turn {
                        Image(systemName: turn.symbol)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(AB.ice)
                            .accessibilityHidden(true)
                    }
                    Text(guidance.instruction)
                        .outfitText(22, .bold, AB.gateYellow)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("routeInstruction")
                        .drivenPoseValue(guidance.position)
                }
                if let floor = guidance.lastConfirmedFloor {
                    Text("Last confirmed floor \(floor)F").outfitText(15, .medium, AB.ice)
                }
                if guidance.canFinish {
                    CTAButton(title: "End", action: end).accessibilityIdentifier("endRoute")
                }
                actions
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct TerminalCheckpointOverview: View {
    let reading: TerminalReading
    let pedestrians: [DriverPedestrian]

    var body: some View {
        TerminalInterior(reading: reading, passageBlocked: false, pedestrians: pedestrians, distantOverview: true)
            .frame(height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Checkpoint entrance")
            .accessibilityIdentifier("checkpointApproachOverview")
            .allowsHitTesting(false)
    }
}

private struct TerminalInterior: UIViewRepresentable {
    let reading: TerminalReading?
    let passageBlocked: Bool
    let pedestrians: [DriverPedestrian]
    var distantOverview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> InteriorScene { InteriorScene() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.scene.addAnchor(context.coordinator.anchor)
        updateBackground(view)
        context.coordinator.render(reading, passageBlocked: passageBlocked, pedestrians: pedestrians,
                                   distantOverview: distantOverview, animated: false)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        updateBackground(view)
        context.coordinator.render(reading, passageBlocked: passageBlocked, pedestrians: pedestrians,
                                   distantOverview: distantOverview, animated: !reduceMotion)
    }

    private func updateBackground(_ view: ARView) {
        let color = reading?.landmark?.scene?.isOutdoors == true
            ? UIColor(red: 0.65, green: 0.78, blue: 0.87, alpha: 1)
            : UIColor(red: 0.75, green: 0.79, blue: 0.81, alpha: 1)
        view.environment.background = .color(color)
    }
}

@MainActor
private final class InteriorScene {
    let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private let lowerFloor = Entity()
    private let upperFloor = Entity()
    private var hanedaScenes: HanedaReplayScenes?
    private var rendered: TerminalReading?
    private var renderedClosure = false

    init() {
        camera.camera.fieldOfViewInDegrees = 61
        anchor.addChild(camera)
        anchor.addChild(lowerFloor)
        anchor.addChild(upperFloor)
        buildFloor(lowerFloor, upper: false)
        buildFloor(upperFloor, upper: true)
        lowerFloor.isEnabled = true
        upperFloor.isEnabled = false
        camera.position = SIMD3<Float>(0, 1.48, 2.7)
    }

    func render(_ reading: TerminalReading?, passageBlocked: Bool, pedestrians: [DriverPedestrian],
                distantOverview: Bool, animated: Bool) {
        guard let reading, let point = reading.point else { return }
        if reading == rendered, passageBlocked == renderedClosure {
            hanedaScenes?.updatePedestrians(pedestrians, animated: animated)
            return
        }
        renderedClosure = passageBlocked
        let scene: HanedaReplayScene? = switch reading.mapFrameID {
        case OfficialGateWalkPath.gateWing: .gateWing
        case OfficialGateWalkPath.cafeConcourse: .cafeConcourse
        default: reading.landmark?.scene
        }
        if let scene {
            lowerFloor.isEnabled = false
            upperFloor.isEnabled = false
            if hanedaScenes == nil { hanedaScenes = HanedaReplayScenes(anchor: anchor) }
            hanedaScenes?.show(scene, passageBlocked: passageBlocked)
            hanedaScenes?.updatePedestrians(pedestrians, animated: animated)
            var pose = scene.cameraPose(point, headingDegrees: reading.headingDegrees ?? 0)
            if distantOverview {
                // A fixed view of authored geometry from farther back. No device camera is active.
                pose.translation += [0, 0.24, 2.0]
            }
            let sameScene = animated && (scene.usesGateWingCoordinates
                ? rendered?.mapFrameID == reading.mapFrameID : rendered?.landmark?.scene == scene)
            if reading != rendered {
                hanedaScenes?.moveShuttle(for: scene, to: pose.translation.z, animated: sameScene)
                moveCamera(to: pose, animated: sameScene)
            }
            rendered = reading
            return
        }
        guard reading.landmark != nil else { return }
        hanedaScenes?.hide()
        let upper = reading.level == 4
        let sameFloor = rendered?.level == reading.level
        lowerFloor.isEnabled = !upper
        upperFloor.isEnabled = upper

        // These fixture coordinates map to this scene's scale in metres. The accepted x
        // coordinate advances down the corridor; y supplies lateral position.
        let lateral = upper ? (point.y - 0.55) * 2 : (point.y - 0.72) * 2
        let depth = upper ? 2.0 - (point.x - 0.65) * 18 : 2.7 - (point.x - 0.46) * 6
        let pose = Transform(rotation: simd_quatf(angle: -.pi / 42, axis: SIMD3<Float>(1, 0, 0)),
                             translation: SIMD3<Float>(lateral, 1.48, depth))
        moveCamera(to: pose, animated: animated && sameFloor)
        rendered = reading
    }

    private func moveCamera(to pose: Transform, animated: Bool) {
        camera.stopAllAnimations()
        if animated {
            camera.move(to: pose, relativeTo: anchor, duration: 0.28, timingFunction: .linear)
        } else {
            camera.transform = pose
        }
    }

    private func buildFloor(_ floor: Entity, upper: Bool) {
        let stone = UIColor(red: 0.80, green: 0.73, blue: 0.63, alpha: 1)
        let seam = UIColor(red: 0.66, green: 0.59, blue: 0.51, alpha: 1)
        let wood = UIColor(red: 0.66, green: 0.47, blue: 0.31, alpha: 1)
        let ceiling = UIColor(red: 0.91, green: 0.87, blue: 0.79, alpha: 1)
        let trim = UIColor(red: 0.20, green: 0.22, blue: 0.22, alpha: 1)
        let glass = UIColor(red: 0.64, green: 0.81, blue: 0.86, alpha: 1)
        let yellow = UIColor(red: 0.98, green: 0.80, blue: 0.25, alpha: 1)
        addBox(to: floor, centre: [0, -0.07, -4], size: [5.6, 0.14, 16], color: stone)
        addBox(to: floor, centre: [0, 3.05, -4], size: [5.6, 0.10, 16], color: ceiling)
        addBox(to: floor, centre: [2.75, 1.5, -4], size: [0.12, 3, 16], color: wood)
        addBox(to: floor, centre: [-2.75, 1.5, -4], size: [0.12, 2.8, 16], color: glass)
        addBox(to: floor, centre: [0, 1.5, -11.9], size: [5.6, 3, 0.12], color: ceiling)
        addBox(to: floor, centre: [-2.67, 0.9, -4], size: [0.07, 0.06, 16], color: trim)
        for z in stride(from: Float(-10), through: 3, by: 1.0) {
            addBox(to: floor, centre: [0, 0.003, z], size: [5.55, 0.004, 0.016], color: seam)
        }
        for z in stride(from: Float(-10), through: 2, by: 2.0) {
            addBox(to: floor, centre: [-2.66, 1.5, z], size: [0.08, 3, 0.07], color: trim)
            addBox(to: floor, centre: [0, 2.98, z], size: [1.15, 0.03, 0.11], color: .white)
        }
        for x in stride(from: Float(-2), through: 2, by: 1.0) {
            addBox(to: floor, centre: [x, 0.002, -4], size: [0.015, 0.004, 15.9], color: seam)
        }
        addBox(to: floor, centre: [-0.96, 1.35, -1.7], size: [0.12, 2.7, 0.2], color: trim)
        addBox(to: floor, centre: [0.96, 1.35, -1.7], size: [0.12, 2.7, 0.2], color: trim)
        addBox(to: floor, centre: [0, 2.73, -1.7], size: [2.04, 0.11, 0.2], color: trim)
        if upper {
            addBox(to: floor, centre: [0, 2.42, -5.8], size: [1.7, 0.34, 0.08], color: yellow)
            let text = ModelEntity(mesh: .generateText("105–109", extrusionDepth: 0.005,
                                                       font: .systemFont(ofSize: 0.24, weight: .bold)),
                                   materials: [UnlitMaterial(color: trim)])
            text.position = [-0.51, 2.35, -5.75]
            floor.addChild(text)
            addBox(to: floor, centre: [0, 0.034, -3.8], size: [0.12, 0.035, 0.70], color: yellow)
            for side: Float in [-1, 1] {
                let arm = addBox(to: floor, centre: [side * 0.14, 0.034, -4.16],
                                 size: [0.12, 0.035, 0.37], color: yellow)
                arm.orientation = simd_quatf(angle: side * .pi / 4, axis: SIMD3<Float>(0, 1, 0))
            }
        } else {
            let metal = UIColor(red: 0.48, green: 0.46, blue: 0.43, alpha: 1)
            addBox(to: floor, centre: [-0.46, 1.32, -1.73], size: [0.91, 2.64, 0.12], color: metal)
            addBox(to: floor, centre: [0.46, 1.32, -1.73], size: [0.91, 2.64, 0.12], color: metal)
            addBox(to: floor, centre: [1.22, 0.91, -1.73], size: [0.14, 0.27, 0.10], color: trim)
        }
    }

    @discardableResult
    private func addBox(to parent: Entity, centre: SIMD3<Float>, size: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let box = ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: color)])
        box.position = centre
        parent.addChild(box)
        return box
    }
}
