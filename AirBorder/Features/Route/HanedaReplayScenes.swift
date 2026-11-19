// SUBSTANTIVE: Maps scripted Haneda route observations to a moving first-person scene.
import RealityKit
import UIKit

enum HanedaReplayScene: Hashable {
    case arrivals, shuttleCurb, outboundRide, terminalTwo, deck, deckLift, returnCurb, returnRide
    case departuresLift, checkpoint, airside, busExit, coachCurb
    case railEntrance, railPlatform, gateWing, cafeConcourse
    case loungeEntrance, immigration, baggageClaim, customs, arrivalsExit

    var isShuttleRide: Bool { self == .outboundRide || self == .returnRide }
    var usesGateWingCoordinates: Bool { self == .gateWing || self == .cafeConcourse }
    var isOutdoors: Bool { isShuttleRide || [.shuttleCurb, .returnCurb, .coachCurb, .deck].contains(self) }

    func cameraPose(_ point: TerminalReading.Point, headingDegrees: Float) -> Transform {
        // Trace x is longitudinal progress and y is lateral offset in the current corridor
        // or coach scene. North in each scene is local -Z. Scales are illustrative metres.
        if usesGateWingCoordinates {
            // Published-map x translates down the hall and y across it. The heading is
            // clockwise from up in the image; world forward points toward image right.
            let yaw = simd_quatf(angle: (90 - headingDegrees) * .pi / 180, axis: [0, 1, 0])
            let local = self == .cafeConcourse ? TerminalReading.Point(x: 2 * point.x - 1, y: point.y) : point
            return Transform(rotation: yaw, translation: Self.gateWingPoint(local))
        }
        let distance: Float = switch self {
        case .outboundRide, .returnRide: 32
        case .railPlatform: 15
        default: 11
        }
        let lateral = (isShuttleRide ? 0.8 : 0) + (point.y - 0.5) * (isShuttleRide ? 1 : 5)
        let yaw = simd_quatf(angle: -headingDegrees * .pi / 180, axis: [0, 1, 0])
        let tilt = simd_quatf(angle: -.pi / 55, axis: [1, 0, 0])
        return Transform(rotation: yaw * tilt,
                         translation: [lateral, isShuttleRide ? 1.72 : 1.58, 3 - point.x * distance])
    }

    static func gateWingPoint(_ point: TerminalReading.Point) -> SIMD3<Float> {
        [GateWingSidePassage.lateralPosition(point), 1.58, GateWingSidePassage.depth(point.x)]
    }
}

/// The two ends of the simulator's side aisle in gate-wing map coordinates.
enum GateWingSidePassage {
    static let west: Float = 0.12381
    static let east: Float = 0.209524
    static let lane: Float = 0.44
    static let dividerX: Float = -0.74

    static func depth(_ x: Float) -> Float {
        // Give the short mapped detour enough depth to read in first person. The
        // adjustment tapers out before the far gates in the authored scene.
        let entering = (x - west) / (east - west)
        let leaving = (0.52 - x) / (0.52 - east)
        let stretch = max(0, min(entering, leaving, 1))
        return 3 - x * 20 - 2.6 * stretch
    }

    static func lateralPosition(_ point: TerminalReading.Point) -> Float {
        // Widen the aisle in the render near the junction while keeping the centerline fixed.
        let along = max(0, min((point.x - west + 0.04) / 0.04, (east + 0.04 - point.x) / 0.04, 1))
        let across = max(0, min((0.5 - point.y) / (0.5 - lane), (point.y - 0.30) / (lane - 0.30), 1))
        return (point.y - 0.5) * 8 - 1.45 * along * across
    }
}

extension TerminalReplayLandmark {
    var scene: HanedaReplayScene? {
        switch self {
        case .lift, .corridor, .gate: nil
        case .arrivals: .arrivals
        case .shuttleStop: .shuttleCurb
        case .outboundShuttle, .terminalOne: .outboundRide
        case .terminalTwo: .terminalTwo
        case .deck: .deck
        case .deckLift: .deckLift
        case .returnStop: .returnCurb
        case .returnShuttle: .returnRide
        case .departuresLift: .departuresLift
        case .checkpoint: .checkpoint
        case .loungeEntrance: .loungeEntrance
        case .immigration: .immigration
        case .baggageClaim: .baggageClaim
        case .customs: .customs
        case .arrivalsExit: .arrivalsExit
        case .screened, .arrivalGate: .airside
        case .naritaExit: .busExit
        case .naritaCurb: .coachCurb
        case .railEntrance, .railDescent: .railEntrance
        case .railApproach, .railWalk, .railDestination: .railPlatform
        }
    }
}

@MainActor
final class HanedaReplayScenes {
    private let anchor: AnchorEntity
    private var scenes: [HanedaReplayScene: Entity] = [:]
    private var shuttleCabins: [HanedaReplayScene: Entity] = [:]
    private var closureBarriers: [HanedaReplayScene: Entity] = [:]
    private struct PedestrianRig {
        let root: Entity
        let arms: [Entity]
        let legs: [Entity]
    }

    private var pedestrianRigs: [Int: PedestrianRig] = [:]
    private var displayedPedestrians: [DriverPedestrian] = []
    private var active: HanedaReplayScene?
    private var assets: [String: Entity] = [:]
    private lazy var stoneTexture = Bundle.main.url(forResource: "ReplayTerrazzo", withExtension: "jpg")
        .flatMap { try? TextureResource.load(contentsOf: $0) }
    private lazy var carpetTexture: TextureResource? = {
        // An authored repeating finish, informed by the blue-gray waiting-area carpet
        // in Haneda's Experience Support Book (pp. 50, 91); not a photograph texture.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        let image = renderer.image { context in
            UIColor(red: 0.18, green: 0.24, blue: 0.29, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            let drawing = context.cgContext
            drawing.setStrokeColor(UIColor(red: 0.47, green: 0.49, blue: 0.47, alpha: 0.62).cgColor)
            drawing.setLineWidth(2.0)
            for row in -1...4 {
                for column in -1...4 {
                    let x = CGFloat(column) * 128 + (row.isMultiple(of: 2) ? 0 : 64)
                    let y = CGFloat(row) * 128
                    drawing.strokeEllipse(in: CGRect(x: x - 38, y: y - 59, width: 102, height: 188))
                    drawing.strokeEllipse(in: CGRect(x: x - 20, y: y - 46, width: 66, height: 162))
                }
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }()

    private let glass = UIColor(red: 0.53, green: 0.68, blue: 0.75, alpha: 1)
    private let stone = UIColor(red: 0.69, green: 0.68, blue: 0.64, alpha: 1)
    private let steel = UIColor(red: 0.53, green: 0.55, blue: 0.56, alpha: 1)
    private let dark = UIColor(red: 0.13, green: 0.17, blue: 0.20, alpha: 1)
    private let white = UIColor(red: 0.87, green: 0.86, blue: 0.82, alpha: 1)
    private let wood = UIColor(red: 0.60, green: 0.43, blue: 0.28, alpha: 1)
    private let yellow = UIColor(red: 1, green: 0.78, blue: 0.19, alpha: 1)

    init(anchor: AnchorEntity) {
        self.anchor = anchor
        let light = DirectionalLight()
        light.light.color = UIColor(red: 1, green: 0.98, blue: 0.93, alpha: 1)
        light.light.intensity = 2600
        light.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
        anchor.addChild(light)
        let fill = DirectionalLight()
        fill.light.intensity = 1200
        fill.orientation = simd_quatf(angle: .pi * 0.70, axis: [0, 1, 0])
        anchor.addChild(fill)
    }

    func show(_ scene: HanedaReplayScene, passageBlocked: Bool = false) {
        if active != scene {
            hide()
            if scenes[scene] == nil {
                let root = Entity()
                build(scene, root)
                anchor.addChild(root)
                scenes[scene] = root
            }
            scenes[scene]?.isEnabled = true
            active = scene
        }
        closureBarriers[scene]?.isEnabled = passageBlocked
    }

    func updatePedestrians(_ poses: [DriverPedestrian], animated: Bool) {
        guard let active, [.gateWing, .checkpoint, .loungeEntrance, .immigration, .customs].contains(active),
              poses != displayedPedestrians else { return }
        let activeIDs = Set(poses.map(\.id))
        for (id, rig) in pedestrianRigs where !activeIDs.contains(id) { rig.root.isEnabled = false }
        guard let scene = scenes[active] else { return }
        let oldPoses = Dictionary(uniqueKeysWithValues: displayedPedestrians.map { ($0.id, $0) })
        for pose in poses where oldPoses[pose.id] != pose {
            let rig = pedestrianRigs[pose.id] ?? makePedestrian(id: pose.id, in: scene, baggage: active == .customs)
            pedestrianRigs[pose.id] = rig
            rig.root.isEnabled = true
            let target = Transform(rotation: simd_quatf(angle: pose.headingDegrees * .pi / 180, axis: [0, 1, 0]),
                                   translation: [pose.x, 0, pose.z])
            rig.root.stopAllAnimations()
            if animated, oldPoses[pose.id] != nil {
                rig.root.move(to: target, relativeTo: scene, duration: 0.13, timingFunction: .linear)
            } else {
                rig.root.transform = target
            }
            let stride = animated ? pose.stride * 0.34 : 0
            for side in rig.arms.indices {
                let swing = side == 0 ? stride : -stride
                rig.arms[side].orientation = simd_quatf(angle: swing, axis: [1, 0, 0])
                rig.legs[side].orientation = simd_quatf(angle: -swing, axis: [1, 0, 0])
            }
        }
        displayedPedestrians = poses
    }

    private func makePedestrian(id: Int, in scene: Entity, baggage: Bool) -> PedestrianRig {
        let figure = Entity()
        scene.addChild(figure)
        let jackets = [UIColor(red: 0.32, green: 0.41, blue: 0.37, alpha: 1), .systemIndigo,
                       UIColor(red: 0.60, green: 0.44, blue: 0.35, alpha: 1)]
        let jacket = jackets[id % jackets.count]
        let skin = UIColor(red: 0.63, green: 0.47, blue: 0.35, alpha: 1)
        let head = ModelEntity(mesh: .generateSphere(radius: 0.113), materials: [UnlitMaterial(color: skin)])
        head.scale = [0.89, 1.15, 1]
        head.position = [0, 1.63, -0.02]
        figure.addChild(head)
        let hair = ModelEntity(mesh: .generateSphere(radius: 0.105), materials: [UnlitMaterial(color: dark)])
        hair.scale = [0.97, 0.69, 1.02]
        hair.position = [0, 1.71, 0.006]
        figure.addChild(hair)
        box(figure, [0, 1.52, 0], [0.10, 0.12, 0.11], skin)
        box(figure, [0, 1.23, 0], [0.38, 0.51, 0.25], jacket)
        box(figure, [0, 0.93, 0], [0.32, 0.14, 0.21], dark)
        box(figure, [0, 1.23, 0.16], [0.31, 0.39, 0.17], dark)
        var arms: [Entity] = []
        var legs: [Entity] = []
        for side: Float in [-1, 1] {
            let arm = Entity()
            arm.position = [side * 0.22, 1.42, 0]
            figure.addChild(arm)
            box(arm, [0, -0.22, 0], [0.12, 0.46, 0.13], jacket)
            box(arm, [0, -0.49, 0], [0.085, 0.09, 0.08], skin)
            arms.append(arm)

            let leg = Entity()
            leg.position = [side * 0.097, 0.90, 0]
            figure.addChild(leg)
            box(leg, [0, -0.42, 0], [0.16, 0.77, 0.18], dark)
            box(leg, [0, -0.83, -0.059], [0.17, 0.13, 0.30], .black)
            legs.append(leg)
        }
        if baggage && id.isMultiple(of: 2) {
            let bag = UIColor(red: 0.26, green: 0.32, blue: 0.43, alpha: 1)
            box(figure, [0.32, 0.22, 0.22], [0.22, 0.39, 0.18], bag)
            box(figure, [0.32, 0.50, 0.22], [0.045, 0.20, 0.035], steel)
        }
        return PedestrianRig(root: figure, arms: arms, legs: legs)
    }

    func hide() {
        for rig in pedestrianRigs.values { rig.root.removeFromParent() }
        pedestrianRigs.removeAll()
        displayedPedestrians.removeAll()
        if let active { scenes[active]?.isEnabled = false }
        active = nil
    }

    func moveShuttle(for scene: HanedaReplayScene, to depth: Float, animated: Bool) {
        guard let cabin = shuttleCabins[scene] else { return }
        var destination = cabin.transform
        destination.translation.z = depth
        cabin.stopAllAnimations()
        if animated {
            cabin.move(to: destination, relativeTo: cabin.parent, duration: 0.28, timingFunction: .linear)
        } else {
            cabin.transform = destination
        }
    }

    private func build(_ scene: HanedaReplayScene, _ root: Entity) {
        switch scene {
        case .arrivals, .terminalTwo, .deckLift, .departuresLift, .busExit, .checkpoint, .airside, .railEntrance,
             .gateWing, .cafeConcourse, .loungeEntrance, .immigration, .baggageClaim, .customs, .arrivalsExit:
            hall(scene, root)
        case .shuttleCurb:
            curb(root, stop: "0", text: "Terminal Shuttle", isCoach: false)
        case .returnCurb:
            curb(root, stop: "9", text: "Terminal Shuttle", isCoach: false)
        case .coachCurb:
            curb(root, stop: "5", text: "Narita Airport", isCoach: true)
        case .outboundRide, .returnRide:
            shuttleRide(root, returning: scene == .returnRide)
        case .deck:
            observationDeck(root)
        case .railPlatform:
            railPlatform(root)
        }
    }

    private func hall(_ scene: HanedaReplayScene, _ root: Entity) {
        if scene.usesGateWingCoordinates {
            gateConcourse(scene, root)
            return
        }
        let start: Float = scene.usesGateWingCoordinates ? -25 : -17
        let end: Float = scene == .cafeConcourse ? 31 : scene == .gateWing ? 11 : 8
        let length = end - start
        let centre: Float = scene == .cafeConcourse ? start + length / 2 : scene == .gateWing ? -8 : -6
        paving(root, extendsGateWing: scene.usesGateWingCoordinates, includesCafe: scene == .cafeConcourse)
        box(root, [0, 4.1, centre], [9.6, 0.16, length], white)
        box(root, [4.65, 2, centre], [0.15, 4, length], scene == .checkpoint ? wood : white)
        box(root, [0, 2, start], [9.5, 4, 0.14], white)
        let lastFixture: Float = scene == .cafeConcourse ? 27 : scene == .gateWing ? 7 : 4
        for metre in stride(from: start + 1, through: lastFixture, by: 3) {
            box(root, [-4.60, 2, metre], [0.12, 3.8, 2.86], glass)
            box(root, [-4.52, 2, metre + 1.46], [0.18, 4, 0.11], steel)
            box(root, [-0.2, 3.98, metre], [5.1, 0.06, 0.12], .white)
        }
        switch scene {
        case .arrivals:
            sign(root, "Buses  ·  1F", at: [0, 2.7, -8.0])
            box(root, [3.3, 0.55, -6.4], [1.8, 1.1, 4.1], wood)
            planter(root, [2.5, 0, -12])
        case .railEntrance:
            sign(root, "Keikyu Line", at: [0, 2.7, -7.2])
            for x: Float in [-1.85, -0.65, 0.65, 1.85] {
                box(root, [x, 0.48, -8.90], [0.30, 0.96, 1.50], steel)
                box(root, [x, 0.97, -8.50], [0.28, 0.02, 0.41], dark)
                box(root, [x, 0.991, -8.45], [0.13, 0.02, 0.13], .systemBlue)
            }
            sign(root, "Trains  ↓", at: [0, 2.3, -12])
            box(root, [1.2, 1.24, -12.35], [1.85, 2.48, 0.15], steel)
            box(root, [1.2, 1.22, -12.25], [0.023, 2.42, 0.012], dark)
            box(root, [2.23, 1.10, -12.22], [0.13, 0.29, 0.06], dark)
        case .terminalTwo:
            lifts(root, signText: "Observation Deck  ·  5F")
        case .deckLift:
            lifts(root, signText: "Shuttle  ·  1F")
        case .departuresLift:
            lifts(root, signText: "Departures  ·  3F")
        case .busExit:
            sign(root, "Buses  ·  Stops 1–11", at: [0, 2.7, -8])
            box(root, [0, 1.28, -11.9], [3.9, 2.56, 0.12], glass)
            for x: Float in [-2, 0, 2] { box(root, [x, 1.27, -11.8], [0.08, 2.56, 0.11], dark) }
            box(root, [0, 0.05, -11.1], [3.5, 0.09, 1.7], dark)
        case .checkpoint:
            bilingualSign(root, japanese: "保安検査場", english: "Security", at: [0, 2.72, -6.4], width: 2.1)
            for x: Float in [-1.85, 1.85] {
                for z: Float in [-3.7, -5.7, -7.7, -9.7] {
                    box(root, [x, 0.45, z], [0.08, 0.9, 0.08], steel)
                    box(root, [x, 0.06, z], [0.31, 0.1, 0.31], steel)
                }
                box(root, [x, 0.82, -6.7], [0.05, 0.08, 6.1], .systemBlue)
            }
            box(root, [1.3, 0.68, -12.0], [0.82, 1.35, 2.8], steel)
            box(root, [1.3, 1.36, -11.6], [0.52, 0.035, 0.40], dark)
            gantry(root, at: [-0.48, 0, -12.0])
        case .loungeEntrance:
            // The lounge line stays to the right. The left side remains the gate concourse.
            let entry: SIMD3<Float> = [2.48, 0, -10.7]
            gantry(root, at: entry)
            box(root, [3.83, 1.38, -10.73], [1.68, 2.76, 0.18], wood)
            box(root, [1.38, 1.38, -10.73], [1.24, 2.76, 0.18], wood)
            box(root, [2.48, 0.047, -11.44], [1.0, 0.075, 1.45], wood)
            bilingualSign(root, japanese: "ラウンジ", english: "Lounge", at: [2.48, 2.72, -10.65], width: 1.64)
            queueRails(root, lanes: [1.62, 3.16], near: -4.35, far: -9.98)
        case .immigration:
            bilingualSign(root, japanese: "入国審査", english: "Immigration Control",
                          at: [1.45, 2.72, -9.55], width: 2.72)
            queueRails(root, lanes: [0.10, 1.64, 3.22], near: -5.8, far: -12.54)
            for x: Float in [0.85, 2.38] {
                box(root, [x, 0.62, -14], [1.25, 1.24, 0.74], steel)
                box(root, [x, 1.80, -14.06], [1.22, 1.18, 0.08], glass)
            }
        case .baggageClaim:
            bilingualSign(root, japanese: "手荷物受取", english: "Baggage Claim",
                          at: [0, 2.72, -7.1], width: 2.6)
            box(root, [-2.10, 0.47, -8.20], [3.8, 0.94, 5.1], steel)
            box(root, [-2.10, 0.96, -8.20], [3.64, 0.08, 4.92], dark)
        case .customs:
            bilingualSign(root, japanese: "電子申告ゲート", english: "Electronic Declaration Gate",
                          at: [-2.16, 2.72, -9.5], width: 3.25)
            bilingualSign(root, japanese: "税関検査", english: "Customs Inspection",
                          at: [1.80, 2.72, -9.5], width: 2.68)
            queueRails(root, lanes: [-3.75, -0.55, 0.52, 3.02], near: -4.45, far: -9.95)
            for x: Float in [-2.66, -1.57] {
                box(root, [x, 0.64, -11.3], [0.25, 1.28, 0.60], steel)
                box(root, [x, 1.22, -10.98], [0.16, 0.12, 0.05], .systemGreen)
            }
            box(root, [1.80, 0.60, -12.4], [1.58, 1.20, 0.86], steel)
            box(root, [1.80, 1.65, -12.43], [1.54, 0.89, 0.08], glass)
        case .arrivalsExit:
            bilingualSign(root, japanese: "到着ロビー", english: "Arrivals Hall",
                          at: [0, 2.72, -5.8], width: 2.30)
        case .gateWing, .cafeConcourse:
            buildSidePassage(scene, root)
            for z in stride(from: Float(-23), through: 5, by: 3) {
                box(root, [3.45, 0.48, z], [0.92, 0.14, 1.70], dark)
                box(root, [3.85, 0.74, z], [0.17, 0.61, 1.70], steel)
                box(root, [3.45, 0.22, z], [0.21, 0.44, 0.13], steel)
            }
            for depth: Float in [-23.0, -12.0, 6.0] { planter(root, [-3.75, 0, depth]) }
            for (gate, point) in [("108A", TerminalReading.Point(x: 0.266667, y: 0.197619)),
                                  ("105", TerminalReading.Point(x: 0.962857, y: 0.390476))] {
                let pose = HanedaReplayScene.gateWingPoint(point)
                let marker = Entity()
                marker.position = [pose.x - 0.75, 0, pose.z]
                marker.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                root.addChild(marker)
                sign(marker, "Gate \(gate)", at: [0, 2.6, 0])
            }
            if scene == .cafeConcourse {
                // The doorway marks shop 116 in the authored scene at the map checkpoint.
                let cafeDepth = Self.cafeDepth
                box(root, [4.49, 1.25, cafeDepth], [0.15, 2.5, 3.4], wood)
                box(root, [4.38, 1.2, cafeDepth], [0.09, 2.23, 1.6], glass)
                planter(root, [3.82, 0, cafeDepth - 2.2])
                sign(root, "Curacion Cafe", at: [0, 2.65, cafeDepth - 3.2])
            }
        case .airside:
            sign(root, "Gate 105", at: [0, 2.65, -9.5])
            for z in stride(from: Float(-14), through: -3, by: 1.10) {
                box(root, [-3.48, 0.47, z], [0.78, 0.11, 0.90], dark)
                box(root, [-3.83, 0.80, z], [0.12, 0.64, 0.90], dark)
                box(root, [-3.48, 0.23, z], [0.16, 0.44, 0.17], steel)
            }
            box(root, [2.95, 0.56, -10.8], [2.1, 1.12, 0.72], wood)
        default: break
        }
        if !scene.usesGateWingCoordinates && ![.loungeEntrance, .checkpoint, .immigration, .customs].contains(scene) {
            arrow(root, [0, 0.017, -3.3])
        }
    }

    private static var cafeDepth: Float {
        HanedaReplayScene.gateWingPoint(.init(x: (833 - 1740) / 1050, y: 0.5)).z
    }

    /// Reconstructs the character of the T3 airside concourse, using airport-book
    /// photographs for finishes and the existing published-map transform for poses.
    /// Exact furniture spacing and vertical dimensions are authored, not surveyed.
    private func gateConcourse(_ scene: HanedaReplayScene, _ root: Entity) {
        let near: Float = scene == .cafeConcourse ? 31 : 11
        let far: Float = -27
        let span = near - far
        let middle = (near + far) / 2
        let ivory = UIColor(red: 0.88, green: 0.87, blue: 0.83, alpha: 1)
        let tile = UIColor(red: 0.70, green: 0.70, blue: 0.67, alpha: 1)

        litBox(root, [0, -0.055, middle], [9.6, 0.10, span], tile, roughness: 0.85)
        litBox(root, [0, 3.95, middle], [9.6, 0.12, span], ivory)
        litBox(root, [4.68, 1.98, middle], [0.18, 3.96, span], ivory)

        // Keep map north at negative world X. The apron glazing belongs to that
        // side even though the approved style preview composed it on the right.
        let daylight = UIColor(red: 0.71, green: 0.82, blue: 0.88, alpha: 1)
        box(root, [-12, 3.4, middle], [0.10, 10, span + 10], daylight)
        litBox(root, [-9, -0.12, middle], [8, 0.10, span + 8],
               UIColor(red: 0.58, green: 0.61, blue: 0.61, alpha: 1))
        for depth in stride(from: far - 2, through: near + 2, by: 4.5) {
            litBox(root, [-8.5, -0.055, depth], [5.5, 0.015, 0.065],
                   UIColor(red: 0.87, green: 0.77, blue: 0.32, alpha: 1))
        }
        // Close the authored display extent beyond the reachable driver poses;
        // these framed end panels are scenery, not an added route connection.
        for depth in [far - 0.02, near + 0.02] {
            litBox(root, [0, 0.24, depth], [9.6, 0.48, 0.16], ivory)
            litBox(root, [0, 3.75, depth], [9.6, 0.40, 0.16], ivory)
            for x: Float in [-3.6, -1.2, 1.2, 3.6] {
                litBox(root, [x, 2.0, depth], [2.30, 3.05, 0.09], daylight, roughness: 0.22)
                litBox(root, [x + 1.18, 2.0, depth + 0.08], [0.11, 3.5, 0.11], ivory)
                litBox(root, [x, 1.20, depth + 0.08], [2.4, 0.075, 0.11], ivory)
                litBox(root, [x, 2.55, depth + 0.08], [2.4, 0.065, 0.11], ivory)
            }
        }
        for depth in [far + 4, middle, near - 4] {
            let fill = PointLight()
            fill.light.color = UIColor(red: 1, green: 0.98, blue: 0.94, alpha: 1)
            fill.light.intensity = 650
            fill.light.attenuationRadius = 16
            fill.position = [0.8, 3.25, depth]
            root.addChild(fill)
        }
        for depth in stride(from: far + 1.5, through: near - 1, by: 2.4) {
            // Transparent-looking glazing leaves a view to the daylit apron;
            // framing and the sill supply depth rather than an opaque blue wall.
            var glazing = PhysicallyBasedMaterial()
            glazing.baseColor = .init(tint: UIColor(red: 0.79, green: 0.89, blue: 0.93, alpha: 1))
            glazing.roughness = .init(floatLiteral: 0.12)
            glazing.blending = .transparent(opacity: .init(floatLiteral: 0.12))
            let pane = ModelEntity(mesh: .generateBox(size: [0.018, 3.5, 2.30]), materials: [glazing])
            pane.position = [-4.57, 2.03, depth]
            root.addChild(pane)
            litBox(root, [-4.53, 2.00, depth + 1.18], [0.12, 3.90, 0.11], ivory)
            litBox(root, [-4.53, 0.55, depth], [0.11, 0.09, 2.4], steel, metallic: true)
            litBox(root, [-4.53, 2.25, depth], [0.10, 0.07, 2.4], ivory)
        }
        for depth in stride(from: far + 3, through: near - 1, by: 6) {
            litBox(root, [-3.87, 1.98, depth], [0.46, 3.96, 0.55], ivory, radius: 0.045)
            litBox(root, [-3.85, 3.88, depth], [1.3, 0.13, 0.7], ivory)
            box(root, [0.40, 3.875, depth], [4.7, 0.025, 0.065],
                UIColor(red: 1, green: 0.97, blue: 0.89, alpha: 1))
        }
        // Small tile seams remain below the camera and do not become navigation cues.
        for depth in stride(from: far, through: near, by: 1.25) {
            litBox(root, [0.20, 0.001, depth], [4.6, 0.003, 0.007],
                   UIColor(white: 0.57, alpha: 1))
        }
        for x: Float in [-1.5, 0, 1.5] {
            litBox(root, [x, 0.001, middle], [0.006, 0.003, span], UIColor(white: 0.57, alpha: 1))
        }

        carpetStrip(root, x: -3.18, width: 2.45, near: near, far: far)
        carpetStrip(root, x: 3.47, width: 1.90, near: near, far: far)
        // Repeated seat banks are outside both the main path and the side aisle.
        let bank = seatingBank()
        for depth in stride(from: far + 3.5, through: near - 2.5, by: 5.5) {
            for side: Float in [-1, 1] {
                let seats = bank.clone(recursive: true)
                seats.position = [side < 0 ? -3.17 : 3.57, 0, depth]
                seats.orientation = simd_quatf(angle: side < 0 ? -.pi / 2 : .pi / 2, axis: [0, 1, 0])
                root.addChild(seats)
            }
        }
        // A low open separation communicates the driver's paired aisles without
        // inventing the full-height wall that the previous scene displayed.
        buildSidePassage(scene, root, lowDivider: true)

        for (gate, point) in [("108A", TerminalReading.Point(x: 0.266667, y: 0.197619)),
                              ("105", TerminalReading.Point(x: 0.962857, y: 0.390476))] {
            let pose = HanedaReplayScene.gateWingPoint(point)
            let marker = Entity()
            marker.position = [pose.x - 0.75, 0, pose.z]
            marker.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
            root.addChild(marker)
            sign(marker, "Gate \(gate)", at: [0, 2.65, 0])
            litBox(root, [pose.x + 1.0, 0.55, pose.z - 0.7], [1.15, 1.1, 0.48], ivory)
        }
        for depth: Float in [-22, 7] {
            planter(root, [3.82, 0, depth])
        }
        if scene == .cafeConcourse {
            let depth = Self.cafeDepth
            litBox(root, [4.45, 1.38, depth], [0.15, 2.76, 3.2], wood)
            litBox(root, [4.34, 1.12, depth], [0.09, 2.24, 1.6], glass)
            sign(root, "Curacion Cafe", at: [0, 2.65, depth - 3.2])
        }
    }

    private func carpetStrip(_ root: Entity, x: Float, width: Float, near: Float, far: Float) {
        var material = SimpleMaterial()
        material.color = .init(tint: .white, texture: carpetTexture.map { .init($0) })
        material.roughness = .float(1)
        let depth: Float = 1.8
        let mesh = MeshResource.generatePlane(width: width, depth: depth)
        for z in stride(from: far + depth / 2, through: near - depth / 2, by: depth) {
            let panel = ModelEntity(mesh: mesh, materials: [material])
            panel.position = [x, 0.008, z]
            root.addChild(panel)
        }
    }

    private func seatingBank() -> Entity {
        let bank = Entity()
        let cushion = UIColor(red: 0.16, green: 0.19, blue: 0.22, alpha: 1)
        let frame = UIColor(red: 0.59, green: 0.63, blue: 0.65, alpha: 1)
        litBox(bank, [0, 0.32, 0], [2.46, 0.07, 0.08], frame, metallic: true)
        for x: Float in [-0.87, -0.29, 0.29, 0.87] {
            litBox(bank, [x, 0.46, 0], [0.53, 0.105, 0.53], cushion, roughness: 0.65, radius: 0.045)
            let back = litBox(bank, [x, 0.76, 0.235], [0.53, 0.49, 0.095], cushion,
                              roughness: 0.65, radius: 0.04)
            back.orientation = simd_quatf(angle: -.pi / 16, axis: [1, 0, 0])
            for edge: Float in [-0.285, 0.285] {
                litBox(bank, [x + edge, 0.65, 0.02], [0.035, 0.045, 0.45], frame, metallic: true, radius: 0.012)
                litBox(bank, [x + edge, 0.55, 0.17], [0.027, 0.22, 0.035], frame, metallic: true)
            }
        }
        for x: Float in [-0.90, 0.90] {
            litBox(bank, [x, 0.18, 0.04], [0.08, 0.32, 0.12], frame, metallic: true)
            litBox(bank, [x, 0.035, 0.04], [0.12, 0.055, 0.60], frame, metallic: true, radius: 0.015)
        }
        return bank
    }

    private func buildSidePassage(_ scene: HanedaReplayScene, _ root: Entity, lowDivider: Bool = false) {
        let west = GateWingSidePassage.depth(GateWingSidePassage.west)
        let east = GateWingSidePassage.depth(GateWingSidePassage.east)
        let dividerFront = west - 1.65
        let dividerBack = east + 0.48
        let center = (dividerFront + dividerBack) / 2
        let divider = GateWingSidePassage.dividerX
        // Both ends stay open where the driver crosses between the parallel aisles.
        if lowDivider {
            litBox(root, [divider, 0.08, center], [0.16, 0.16, dividerFront - dividerBack], steel)
            litBox(root, [divider, 0.91, center], [0.075, 0.07, dividerFront - dividerBack], dark)
            for depth in [dividerFront - 0.08, dividerBack + 0.08] {
                litBox(root, [divider, 0.49, depth], [0.06, 0.84, 0.06], steel, metallic: true)
            }
        } else {
            box(root, [divider, 1.13, center], [0.14, 2.26, dividerFront - dividerBack], steel)
        }

        let barrier = Entity()
        let depth = west - 2.6
        let left: Float = -0.47
        let right: Float = 2.08
        for x in [left, right] {
            box(barrier, [x, 0.44, depth], [0.07, 0.88, 0.07], dark)
            box(barrier, [x, 0.025, depth], [0.28, 0.05, 0.27], dark)
        }
        let tile = (right - left) / 10
        for index in 0..<10 {
            let x = left + (Float(index) + 0.5) * tile
            box(barrier, [x, 0.78, depth], [tile, 0.16, 0.06], index.isMultiple(of: 2) ? yellow : dark)
        }
        barrier.isEnabled = false
        root.addChild(barrier)
        closureBarriers[scene] = barrier
    }

    private func lifts(_ root: Entity, signText: String) {
        sign(root, signText, at: [0, 2.7, -8.5])
        for x: Float in [-1.20, 1.20] {
            box(root, [x, 1.25, -12.5], [1.8, 2.5, 0.18], steel)
            box(root, [x, 1.23, -12.39], [0.022, 2.44, 0.015], dark)
            box(root, [x + 1.0, 1.12, -12.36], [0.14, 0.28, 0.07], dark)
        }
    }

    private func railPlatform(_ root: Entity) {
        paving(root, width: 6.2, centreX: -1.1)
        box(root, [-4.19, 1.74, -6], [0.17, 3.5, 24], white)
        box(root, [-0.40, 3.42, -6], [8.1, 0.16, 24], white)
        box(root, [5.97, 1.45, -6], [0.18, 5.2, 24], steel)
        box(root, [4.25, -1.57, -6], [4.37, 0.17, 24], dark)
        box(root, [1.47, 0.016, -6], [0.32, 0.022, 24], yellow)
        // The tactile strip runs along the railway, inside the platform barrier.
        for depth in stride(from: Float(-17.7), through: 5.7, by: 0.19) {
            box(root, [1.47, 0.029, depth], [0.26, 0.008, 0.02], yellow)
        }
        for depth in stride(from: Float(-15), through: 3, by: 6) {
            if let rails = model("ReplayRailTrack") {
                rails.position = [4.25, -1.48, depth]
                root.addChild(rails)
            }
            box(root, [0.94, 1.66, depth + 0.35], [0.45, 3.32, 0.50], white)
            box(root, [-1.02, 3.30, depth], [0.25, 0.045, 4.9], .white)
        }
        for depth in stride(from: Float(-17), through: 5, by: 1.4) {
            box(root, [2.00, 0.37, depth], [0.13, 0.74, 1.31], steel)
            box(root, [1.996, 0.75, depth], [0.14, 0.045, 1.30], dark)
            box(root, [2.00, 0.61, depth + 0.68], [0.16, 1.22, 0.072], dark)
        }
        if let train = model("ReplayRailCar") {
            train.position = [4.25, -0.90, -8.1]
            root.addChild(train)
            let railRed = UIColor(red: 0.70, green: 0.10, blue: 0.14, alpha: 1)
            box(root, [2.74, 2.56, -8.1], [0.045, 0.14, 18.0], railRed)
        }
        sign(root, "Keikyu Line", at: [-0.43, 2.62, -4.3])
        arrow(root, [0.10, 0.020, -0.96])
        arrow(root, [0.08, 0.020, -5.8])

        // The scripted destination board is fixed to the train's platform-facing side.
        let display = Entity()
        display.position = [2.65, 2.20, -10.7]
        display.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        box(display, .zero, [1.64, 0.52, 0.045], dark)
        label(display, "成田空港", at: [-0.38, 0.017, 0.028], size: 0.22, color: yellow)
        label(display, "Narita Airport", at: [-0.58, -0.183, 0.028], size: 0.18, color: yellow)
        root.addChild(display)
    }

    private func curb(_ root: Entity, stop: String, text: String, isCoach: Bool) {
        paving(root, width: 4.8, centreX: -0.8)
        box(root, [4.9, -0.16, -6], [7.1, 0.2, 28], dark)
        box(root, [1.58, -0.02, -6], [0.21, 0.19, 25], stone)
        box(root, [0.43, 0.014, -6], [0.34, 0.022, 24], yellow.withAlphaComponent(1))
        box(root, [-1.2, 3.7, -6], [6, 0.18, 24.8], white)
        for metre in stride(from: Float(-16), through: 4, by: 3) {
            box(root, [-3.12, 1.85, metre], [0.15, 3.7, 2.80], glass)
            box(root, [-2.97, 1.85, metre + 1.43], [0.18, 3.7, 0.17], steel)
            box(root, [1.46, 1.82, metre], [0.24, 3.65, 0.30], steel)
            box(root, [7.8, -0.045, metre], [0.05, 0.022, 1.4], white)
        }
        box(root, [-0.07, 1.16, -4.6], [0.58, 2.32, 0.37], dark)
        label(root, stop, at: [-0.20, 1.74, -4.40], size: 0.43)
        sign(root, text, at: [-0.65, 2.65, -7.4])
        arrow(root, [-0.50, 0.017, -1.2])
        bus(root, name: isCoach ? "ReplayCoach" : "ReplayShuttle", at: [3.82, -0.06, -9.1])
    }

    private func shuttleRide(_ root: Entity, returning: Bool) {
        box(root, [0, -0.10, -16], [13, 0.19, 48], dark)
        box(root, [-3.15, 0.02, -16], [0.13, 0.02, 48], white)
        box(root, [3.15, 0.02, -16], [0.13, 0.02, 48], white)
        box(root, [7.8, 0.01, -16], [6, 0.12, 48], stone)
        box(root, [-7.8, 0.01, -16], [6, 0.12, 48], stone)
        for z in stride(from: Float(-36), through: 5, by: 6) {
            box(root, [0, 0.005, z], [0.11, 0.035, 2.9], yellow)
            box(root, [-5, 1.8, z], [0.14, 3.6, 0.14], steel)
            box(root, [7.6, 1.12, z], [0.24, 2.25, 0.24], steel)
        }
        if let exterior = model(returning ? "ReplayHanedaT3" : "ReplayHanedaT2") {
            exterior.position = [24, 0.08, -42]
            root.addChild(exterior)
        } else {
            terminalFront(root, at: [11, 0, -28])
        }
        sign(root, "Terminal 1", at: [-3.15, 2.65, -14.5])
        sign(root, returning ? "Terminal 3" : "Terminal 2", at: [3.15, 2.65, -30.5])
        // The foreground travels with the simulated bus; roadside geometry stays in world space.
        let cabin = Entity()
        box(cabin, [0, 2.69, -1.7], [2.45, 0.20, 4.5], white)
        box(cabin, [0, 0.84, -2.9], [2.42, 0.39, 0.20], dark)
        box(cabin, [1.24, 0.94, -1.3], [0.07, 0.32, 3.6], dark)
        for z: Float in [-2.96, -0.82] {
            box(cabin, [1.22, 1.79, z], [0.075, 1.79, 0.083], dark)
        }
        box(cabin, [-1.19, 1.79, -2.96], [0.075, 1.79, 0.083], dark)
        root.addChild(cabin)
        shuttleCabins[returning ? .returnRide : .outboundRide] = cabin
    }

    private func terminalFront(_ root: Entity, at point: SIMD3<Float>) {
        box(root, point + [0, 1.2, 0], [4.0, 2.4, 16.0], glass)
        box(root, point + [0, 2.5, 0], [4.8, 0.28, 16.4], white)
        for z in stride(from: Float(-7), through: 7, by: 2) {
            box(root, point + [-2.02, 1.19, z], [0.10, 2.35, 0.13], steel)
        }
    }

    private func observationDeck(_ root: Entity) {
        paving(root)
        box(root, [-4.78, 1.45, -5.6], [0.18, 2.9, 23.8], glass)
        box(root, [-3.35, 3.18, -5.4], [3.6, 0.18, 23], wood)
        box(root, [1.6, 1.47, -11.1], [5.8, 2.94, 0.18], glass)
        for x: Float in [-1.28, 0.04, 1.36, 2.68, 4.00] {
            box(root, [x, 1.47, -10.99], [0.10, 2.94, 0.12], dark)
        }
        sign(root, "Terminal 2", at: [0.8, 2.65, -10.78])
        for z in stride(from: Float(-16), through: 5, by: 1.5) {
            box(root, [4.43, 1.43, z], [0.06, 2.86, 0.05], steel)
        }
        for y in stride(from: Float(0.20), through: 2.80, by: 0.23) {
            box(root, [4.43, y, -5.5], [0.017, 0.017, 22.4], steel)
        }
        box(root, [4.43, 1.06, -5.5], [0.09, 0.07, 22.4], steel)
        box(root, [18, -1.65, -8], [26, 0.18, 43], stone)
        box(root, [19, -1.54, -8], [8.7, 0.025, 43], dark)
        for z: Float in [-20, -10, 0] { box(root, [19, -1.519, z], [0.22, 0.018, 3.5], white) }
        box(root, [35, -1.70, -14], [34, 0.12, 70],
            UIColor(red: 0.48, green: 0.64, blue: 0.72, alpha: 1))
        aircraft(root, at: [12.8, -1.12, -12], yaw: -.pi / 7)
        aircraft(root, at: [17.3, -1.12, -6.2], yaw: .pi / 8)
        for z: Float in [-10, -4, 1] {
            box(root, [-3.32, 0.28, z], [0.56, 0.16, 1.62], wood)
            box(root, [-3.32, 0.13, z], [0.42, 0.26, 1.4], steel)
        }
        planter(root, [-3.45, 0, -8.3])
        arrow(root, [0.35, 0.017, -4.6])
    }

    private func aircraft(_ root: Entity, at point: SIMD3<Float>, yaw: Float) {
        let plane = Entity()
        plane.position = point
        plane.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let fuselage = ModelEntity(mesh: .generateSphere(radius: 1), materials: [UnlitMaterial(color: .white)])
        fuselage.scale = [0.39, 0.42, 3.6]
        fuselage.position.y = 0.55
        plane.addChild(fuselage)
        for side: Float in [-1, 1] {
            let wing = box(plane, [1.63 * side, 0.44, 0.63], [3.25, 0.09, 0.58], white)
            wing.orientation = simd_quatf(angle: -.pi / 5 * side, axis: [0, 1, 0])
            box(plane, [0.61 * side, 0.63, 2.37], [1.22, 0.07, 0.46], white)
        }
        let tail = box(plane, [0, 0.92, 2.27], [0.10, 0.97, 0.57], .systemBlue)
        tail.orientation = simd_quatf(angle: -.pi / 6, axis: [1, 0, 0])
        root.addChild(plane)
    }

    private func paving(_ root: Entity, width: Float = 9.4, centreX: Float = 0,
                        extendsGateWing: Bool = false, includesCafe: Bool = false) {
        let rows = includesCafe ? 24 : extendsGateWing ? 15 : 10
        let span = 2.4 * Float(rows)
        let north: Float = includesCafe ? 31 : extendsGateWing ? 10 : 6
        let centre = north - span / 2
        box(root, [centreX, -0.05, centre], [width, 0.10, span], stone)
        var finish = UnlitMaterial(color: UIColor(white: 0.80, alpha: 1))
        if let stoneTexture { finish.color.texture = .init(stoneTexture) }
        let columns = width > 5 ? 4 : 2
        let tileWidth = width / Float(columns)
        let tile = MeshResource.generatePlane(width: tileWidth, depth: 2.4)
        for column in 0..<columns {
            for row in 0..<rows {
                let panel = ModelEntity(mesh: tile, materials: [finish])
                panel.position = [centreX - width / 2 + tileWidth * (Float(column) + 0.5), 0.003,
                                  north - 2.4 * (Float(row) + 0.5)]
                root.addChild(panel)
            }
        }
        let seam = UIColor(white: 0.53, alpha: 1)
        for depth in stride(from: north - span + 0.6, through: north - 0.6, by: 1.2) {
            box(root, [centreX, 0.005, depth], [width, 0.002, 0.008], seam)
        }
        for x in stride(from: centreX - width / 2 + tileWidth / 2, to: centreX + width / 2, by: tileWidth / 2) {
            box(root, [x, 0.005, centre], [0.009, 0.002, span], seam)
        }
    }

    private func bus(_ root: Entity, name: String, at point: SIMD3<Float>) {
        if let bus = model(name) {
            bus.position = point
            bus.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
            root.addChild(bus)
        } else {
            box(root, point + [0, 1.48, 0], [2.3, 2.6, 9.7], name == "ReplayCoach" ? white : .systemTeal)
            box(root, point + [0, 1.91, 4.88], [2.08, 0.94, 0.14], dark)
        }
    }

    private func model(_ name: String) -> Entity? {
        if let asset = assets[name] { return asset.clone(recursive: true) }
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
              let asset = try? Entity.load(contentsOf: url) else { return nil }
        assets[name] = asset
        return asset.clone(recursive: true)
    }

    private func gantry(_ root: Entity, at point: SIMD3<Float>) {
        for side: Float in [-0.46, 0.46] {
            box(root, point + [side, 1.24, 0], [0.13, 2.48, 0.19], steel)
        }
        box(root, point + [0, 2.48, 0], [1.05, 0.14, 0.19], steel)
    }

    private func planter(_ parent: Entity, _ point: SIMD3<Float>) {
        box(parent, point + [0, 0.24, 0], [0.65, 0.47, 1.45], wood)
        for z: Float in [-0.49, 0, 0.50] {
            let leaf = ModelEntity(mesh: .generateSphere(radius: 0.24),
                                   materials: [UnlitMaterial(color: UIColor(red: 0.35, green: 0.49, blue: 0.29, alpha: 1))])
            leaf.scale = [1, 0.85, 1]
            leaf.position = point + [0, 0.59, z]
            parent.addChild(leaf)
        }
    }

    private func arrow(_ parent: Entity, _ at: SIMD3<Float>) {
        box(parent, at, [0.085, 0.025, 0.58], yellow)
        for side: Float in [-1, 1] {
            let arm = box(parent, at + [side * 0.102, 0, -0.22], [0.085, 0.025, 0.29], yellow)
            arm.orientation = simd_quatf(angle: side * .pi / 4, axis: [0, 1, 0])
        }
    }

    private func queueRails(_ root: Entity, lanes: [Float], near: Float, far: Float) {
        for x in lanes {
            for z in [near, (near + far) / 2, far] {
                box(root, [x, 0.44, z], [0.067, 0.88, 0.067], steel)
                box(root, [x, 0.045, z], [0.25, 0.09, 0.25], steel)
            }
            box(root, [x, 0.79, (near + far) / 2], [0.043, 0.065, near - far], .systemBlue)
        }
    }

    private func bilingualSign(_ parent: Entity, japanese: String, english: String,
                               at point: SIMD3<Float>, width: Float) {
        box(parent, point, [width, 0.68, 0.10], dark)
        let lines: [(String, CGFloat, Float)] = [(japanese, 0.25, 0.02), (english, 0.18, -0.24)]
        for (line, fontSize, baseline) in lines {
            let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let lineWidth = Float((line as NSString).size(withAttributes: [.font: font]).width)
            label(parent, line, at: point + [-lineWidth / 2, baseline, 0.057], size: fontSize)
        }
    }

    private func sign(_ parent: Entity, _ string: String, at point: SIMD3<Float>) {
        let width = max(1.9, Float(string.count) * 0.126 + 0.50)
        box(parent, point, [width, 0.42, 0.12], dark)
        label(parent, string, at: point + [-width / 2 + 0.20, -0.09, 0.066], size: 0.24)
    }

    private func label(_ parent: Entity, _ value: String, at point: SIMD3<Float>, size: CGFloat, color: UIColor = .white) {
        let mesh = MeshResource.generateText(value, extrusionDepth: 0.006,
                                              font: .systemFont(ofSize: size, weight: .semibold))
        let text = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        text.position = point
        parent.addChild(text)
    }

    @discardableResult
    private func litBox(_ parent: Entity, _ point: SIMD3<Float>, _ size: SIMD3<Float>, _ color: UIColor,
                        roughness: Float = 0.75, metallic: Bool = false, radius: Float = 0) -> ModelEntity {
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = .float(roughness)
        material.metallic = .float(metallic ? 0.8 : 0)
        let entity = ModelEntity(mesh: .generateBox(size: size, cornerRadius: radius), materials: [material])
        entity.position = point
        parent.addChild(entity)
        return entity
    }

    @discardableResult
    private func box(_ parent: Entity, _ point: SIMD3<Float>, _ size: SIMD3<Float>, _ color: UIColor) -> ModelEntity {
        let box = ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: color)])
        box.position = point
        parent.addChild(box)
        return box
    }
}
