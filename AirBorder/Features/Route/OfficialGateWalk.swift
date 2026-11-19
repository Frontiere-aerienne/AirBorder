// SUBSTANTIVE: Aligns the driver's confirmed positions with Haneda's published floor image.
import SwiftUI

struct OfficialGateWalkPath: Decodable, Equatable {
    static let gateWing = "hnd-t3-3f-gate-wing"
    static let cafeConcourse = "hnd-t3-3f-cafe-concourse"
    static let sourceURL = URL(string: "https://tokyo-haneda.com/site_resource/floor/img/floor__img_floor_map_t3_3f.png")!
    static let sourceSHA256 = "6ad843dacc17b9c4aa0f27a2e7f87fa8426aaf86f3b49b1eb2a79bb7289e5e4e"
    let frameID: String
    let destination: String
    let points: [TerminalReading.Point]
    var revision: Int? = nil
    struct CrowdReport: Decodable, Equatable {
        let start: TerminalReading.Point
        let end: TerminalReading.Point
        let reportedAt: TimeInterval
        let delayMinutes: Int
    }

    struct Junction: Decodable, Equatable {
        let start: TerminalReading.Point
        let end: TerminalReading.Point

        var isValid: Bool { start.isValid && end.isValid && start.x < end.x && start.y == end.y }

        func includesSidePoint(_ point: TerminalReading.Point) -> Bool {
            (start.x...end.x).contains(point.x) && point.y < start.y
        }
    }

    enum Closure: String, Decodable { case detour, unavailable }

    var crowdReport: CrowdReport? = nil
    var junction: Junction? = nil
    var closure: Closure? = nil
    var prefersQuieter: Bool? = nil
    var cafePending: Bool? = nil
    var pedestrians: [DriverPedestrian]? = nil

    var scenePedestrians: [DriverPedestrian] {
        DriverPedestrian.validated(pedestrians ?? [], limit: 3)
    }

    var crop: CGRect {
        frameID == Self.cafeConcourse ? CGRect(x: 690, y: 740, width: 2100, height: 420)
            : CGRect(x: 1740, y: 740, width: 1050, height: 420)
    }

    func matches(gate: String, frame: String = Self.gateWing, viaCafe: Bool = false) -> Bool {
        frameID == frame && (cafePending == true) == viaCafe
            && destination == "t3-departure-gate-\(gate.lowercased())"
            && (junction?.isValid ?? (closure == nil))
            && (1...200).contains(points.count) && points.allSatisfy(\.isValid)
            && Set(points).count == points.count
    }
}

// Metres in the authored Haneda scene. These positions are independent of route observations.
struct DriverPedestrian: Decodable, Equatable {
    let id: Int
    let x: Float
    let z: Float
    let headingDegrees: Float
    let stride: Float

    static func validated(_ poses: [DriverPedestrian], limit: Int) -> [DriverPedestrian] {
        guard poses.count <= limit, Set(poses.map(\.id)).count == poses.count,
              poses.allSatisfy({ (0..<limit).contains($0.id) && $0.isValid }) else { return [] }
        return poses
    }

    private var isValid: Bool {
        (-4...4).contains(x) && (-19...3).contains(z)
            && (0...360).contains(headingDegrees) && (-1...1).contains(stride)
    }
}

struct WalkCrowdImpact: Equatable {
    struct Segment: Equatable {
        let start: TerminalReading.Point
        let end: TerminalReading.Point
    }

    let segments: [Segment]
    /// An old observation retains its location, but its current delay is unknown.
    let delayMinutes: Int?

    init?(report: OfficialGateWalkPath.CrowdReport?, remaining: ArraySlice<TerminalReading.Point>, now: Date) {
        guard let report, report.start.isValid, report.end.isValid, report.start.y == report.end.y,
              report.start.x < report.end.x, (1...60).contains(report.delayMinutes),
              report.reportedAt.isFinite, report.reportedAt > 0 else { return nil }
        let age = now.timeIntervalSince1970 - report.reportedAt
        guard age >= 0 else { return nil }

        // The driver reports one horizontal strip. Include only its overlap with the walking
        // edges still ahead. Touching the strip at the bypass entrance or exit adds no delay.
        segments = zip(remaining, remaining.dropFirst()).compactMap { a, b in
            guard a.y == report.start.y, b.y == report.start.y else { return nil }
            let lower = max(min(a.x, b.x), report.start.x)
            let upper = min(max(a.x, b.x), report.end.x)
            guard lower < upper else { return nil }
            return Segment(start: .init(x: lower, y: a.y), end: .init(x: upper, y: a.y))
        }
        guard !segments.isEmpty else { return nil }
        delayMinutes = age < 5 * 60 ? report.delayMinutes : nil
    }
}

struct OfficialGateWalkState: Equatable {
    private(set) var path: OfficialGateWalkPath
    private(set) var index: Int?
    private(set) var positionAvailable = false
    private(set) var confirmed: TerminalReading?
    private(set) var landmarkToken: Int?
    private(set) var crowdImpact: WalkCrowdImpact?
    private var latest: TerminalReading?

    init(path: OfficialGateWalkPath, retaining previous: OfficialGateWalkState? = nil) {
        self.path = path
        latest = previous?.latest
        guard let confirmed = previous?.confirmed, confirmed.mapFrameID == path.frameID,
              let point = confirmed.point else { return }
        self.confirmed = confirmed
        self.index = path.points.firstIndex(of: point)
    }

    var atGate: Bool {
        path.closure != .unavailable && path.cafePending != true && positionAvailable && index == path.points.count - 1
    }
    var atCafe: Bool {
        path.closure != .unavailable && path.cafePending == true && positionAvailable && index == path.points.count - 1
    }

    var showsClosure: Bool {
        if path.closure == .unavailable { return true }
        guard path.closure == .detour, let index, let junction = path.junction else { return false }
        return path.points[index...].contains(where: junction.includesSidePoint)
    }

    var shouldTurnBack: Bool {
        positionAvailable && index == 0 && (path.revision ?? 0) > 0
            && path.points.count > 1 && path.points[1].x < path.points[0].x
    }

    func guidance(gate: String) -> TerminalGuidance {
        let location = confirmed?.level.map { "\($0)F" }
        if let landmarkToken {
            return .init(instruction: "Confirm your location", position: confirmed, location: location,
                         checkpoint: .confirmCafe(landmarkToken))
        }
        guard positionAvailable else {
            return .init(instruction: "Position unavailable", position: confirmed,
                         location: location, lastConfirmedFloor: confirmed?.level)
        }
        if path.closure == .unavailable {
            return .init(instruction: "Route unavailable. Ask airport staff.", position: confirmed, location: location)
        }
        if let maneuver = sidePassageManeuver {
            return .init(instruction: maneuver.text, turn: maneuver.turn, position: confirmed, location: location)
        }
        if atCafe {
            return .init(instruction: "Curacion Cafe", turn: .stop, position: confirmed, location: location,
                         checkpoint: .cafeStop)
        }
        if path.cafePending == true {
            return .init(instruction: "Walk to Curacion Cafe", turn: .straight,
                         position: confirmed, location: location)
        }
        if atGate {
            return .init(instruction: "Check your flight at Gate \(gate)", turn: .gate,
                         position: confirmed, location: location, canFinish: true)
        }
        if shouldTurnBack {
            return .init(instruction: "Turn back along the concourse", turn: .turnBack,
                         position: confirmed, location: location)
        }
        return .init(instruction: "Continue to Gate \(gate)", turn: .straight,
                     position: confirmed, location: location)
    }

    private var sidePassageManeuver: (text: String, turn: RouteStep.Turn)? {
        guard let junction = path.junction, junction.isValid, let index, index + 1 < path.points.count,
              let heading = confirmed?.headingDegrees else { return nil }
        let here = path.points[index]
        let next = path.points[index + 1]
        let startsOnSide = junction.includesSidePoint(here)
        let endsOnSide = junction.includesSidePoint(next)
        guard startsOnSide || endsOnSide else { return nil }

        // The image axes are east and down. Use image pixels so x and y have the same scale.
        let east = Double(next.x - here.x) * Double(path.crop.width)
        let north = Double(here.y - next.y) * Double(path.crop.height)
        let direction = atan2(east, north) * 180 / Double.pi
        let delta = (direction - Double(heading) + 540).truncatingRemainder(dividingBy: 360) - 180
        let turn: RouteStep.Turn = if abs(delta) >= 145 { .turnBack }
        else if delta < -35 { .left }
        else if delta > 35 { .right }
        else { .straight }
        if !startsOnSide {
            switch turn {
            case .left: return ("Turn left onto the side passage", turn)
            case .right: return ("Turn right onto the side passage", turn)
            case .turnBack: return ("Turn back toward the side passage", turn)
            default: return ("Take the side passage", turn)
            }
        }
        if !endsOnSide {
            return ("Rejoin the concourse", turn)
        }
        return ("Continue along the side passage", turn)
    }

    mutating func updateConditions(from updated: OfficialGateWalkPath) -> Bool {
        guard updated.revision == path.revision, updated.points == path.points,
              updated.destination == path.destination, updated.frameID == path.frameID,
              updated.prefersQuieter == path.prefersQuieter, updated.cafePending == path.cafePending,
              updated.junction == path.junction else { return false }
        path = updated
        return true
    }

    mutating func receive(_ reading: TerminalReading?, at now: Date = .now) {
        positionAvailable = false
        landmarkToken = nil
        crowdImpact = nil
        guard let reading, reading.source == "externalSignalReplay",
              reading.mapFrameID == path.frameID,
              reading.routeRevision == path.revision,
              path.revision == nil || reading.sequence != nil else { return }
        if let sequence = reading.sequence, let lastSequence = latest?.sequence {
            guard sequence >= lastSequence, sequence != lastSequence || reading == latest else { return }
        }
        latest = reading
        if let token = reading.landmarkToken, token > 0, path.cafePending == true,
           reading.level == 3, reading.floorConfirmed, let confirmed,
           confirmed.mapFrameID == reading.mapFrameID {
            landmarkToken = token
            return
        }
        guard reading.level == 3, reading.floorConfirmed, let point = reading.point,
              reading.landmarkToken == nil,
              let match = path.points.firstIndex(of: point),
              (-360...360).contains(reading.headingDegrees ?? 0) else { return }
        confirmed = reading
        index = match
        positionAvailable = true
        crowdImpact = WalkCrowdImpact(report: path.crowdReport, remaining: path.points[match...], now: now)
    }
}

struct OfficialGateWalkMap: View {
    private static let sourceSize = CGSize(width: 2778, height: 1700)
    let image: UIImage
    let gate: String
    let state: OfficialGateWalkState
    var showRoute = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var drawsRoute: Bool { showRoute && state.path.closure != .unavailable }

    var body: some View {
        let crop = state.path.crop
        let windowWidth = min(crop.width, 1050)
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let scale = width / windowWidth
            let focusX = state.confirmed?.point.map { crop.minX + CGFloat($0.x) * crop.width } ?? crop.minX
            let left = min(max(crop.minX, focusX - windowWidth / 2), crop.maxX - windowWidth)
            // Pan one window over the photo. Draw map, path and position with this same transform.
            let project = { (point: TerminalReading.Point) in
                CGPoint(x: (crop.minX + CGFloat(point.x) * crop.width - left) * scale, y: CGFloat(point.y) * height)
            }
            let points = state.path.points.map(project)
            let gatePixel = gate == "105" ? CGPoint(x: 2751, y: 870) : CGPoint(x: 2004, y: 791)
            ZStack(alignment: .topLeading) {
                Color.white.frame(width: width, height: height)
                    .overlay(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: Self.sourceSize.width * scale, height: Self.sourceSize.height * scale)
                            .offset(x: -left * scale, y: -crop.minY * scale)
                    }
                if drawsRoute {
                    WalkLine(points: points, progress: 1)
                        .stroke(AB.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
                    WalkLine(points: points, progress: walkedFraction)
                        .stroke(AB.ticket, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    if let crowd = state.crowdImpact, crowd.delayMinutes != nil {
                        Path { path in
                            for segment in crowd.segments {
                                path.move(to: project(segment.start))
                                path.addLine(to: project(segment.end))
                            }
                        }
                        .stroke(AB.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [3, 4]))
                    }
                }
                if drawsRoute, state.path.cafePending == true, let cafe = points.last {
                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AB.gateText)
                        .frame(width: 22, height: 22)
                        .background(AB.gateYellow, in: Circle())
                        .position(x: cafe.x, y: cafe.y - 15)
                } else {
                    Circle().strokeBorder(Color(hex: 0xD79E00), lineWidth: 3)
                        .frame(width: 20, height: 20)
                        .position(x: (gatePixel.x - left) * scale, y: (gatePixel.y - crop.minY) * scale)
                }
                if showRoute, state.showsClosure, let junction = state.path.junction {
                    let start = project(junction.start)
                    let end = project(junction.end)
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AB.removeRed)
                        .padding(1.5)
                        .background(.white, in: Circle())
                        // Move the marker below the edge to keep the position dot and bypass leg visible.
                        .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + 9)
                }
                if let current = state.confirmed?.point {
                    Circle().fill(AB.primary)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .position(project(current))
                        .opacity(state.positionAvailable && showRoute ? 1 : 0.45)
                }
            }
            .frame(width: width, height: height)
            .clipped()
            .animation(reduceMotion ? nil : .linear(duration: 0.27), value: state.confirmed?.point)
        }
        .aspectRatio(windowWidth / crop.height, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AB.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.path.cafePending == true ? "Terminal 3 floor 3 route to Curacion Cafe"
                            : "Terminal 3 floor 3 route to Gate \(gate)")
        .accessibilityValue(mapStatus)
    }

    private var mapStatus: String {
        if state.path.closure == .unavailable { return "Route unavailable" }
        guard state.positionAvailable, showRoute else { return "Position unavailable" }
        return "\(Int((walkedFraction * 100).rounded()))% of route"
    }

    private var walkedFraction: CGFloat {
        guard let index = state.index else { return 0 }
        let points = state.path.points.map {
            CGPoint(x: CGFloat($0.x) * state.path.crop.width, y: CGFloat($0.y) * state.path.crop.height)
        }
        let lengths = zip(points, points.dropFirst()).map { hypot($0.0.x - $0.1.x, $0.0.y - $0.1.y) }
        let total = lengths.reduce(0, +)
        return total > 0 ? lengths.prefix(index).reduce(0, +) / total : 0
    }
}

extension View {
    /// Expose the same rendered pose in both modes for the Debug simulator regression.
    @ViewBuilder
    func drivenPoseValue(_ reading: TerminalReading?) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--qa-verify-route-pose"), let point = reading?.point {
            accessibilityValue(String(format: "%.6f,%.6f,%.2f", point.x, point.y, reading?.headingDegrees ?? 0))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

private struct WalkLine: Shape {
    let points: [CGPoint]
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addLines(points)
        }.trimmedPath(from: 0, to: progress)
    }
}
