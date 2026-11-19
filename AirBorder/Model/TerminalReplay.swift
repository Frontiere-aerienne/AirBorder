// SUBSTANTIVE: Applies confirmed position observations to the controlled indoor replay.
import Foundation
import CryptoKit
import SwiftUI

enum TerminalReplayRoute: String {
    case gate, observationDeck = "observation-deck", narita, naritaRail = "narita-rail", lounge, arrivals

    var usesNaritaItinerary: Bool { self == .narita || self == .naritaRail }

    func includes(_ landmark: TerminalReplayLandmark) -> Bool {
        switch self {
        case .gate: [.lift, .corridor, .gate].contains(landmark)
        case .observationDeck:
            [.arrivals, .shuttleStop, .outboundShuttle, .terminalOne, .terminalTwo, .deck, .deckLift,
             .returnStop, .returnShuttle, .departuresLift, .checkpoint, .screened, .arrivalGate].contains(landmark)
        case .lounge: [.loungeEntrance, .gate].contains(landmark)
        case .arrivals: [.immigration, .baggageClaim, .customs, .arrivalsExit].contains(landmark)
        case .narita: [.arrivals, .naritaExit, .naritaCurb].contains(landmark)
        case .naritaRail: [.railEntrance, .railDescent, .railApproach, .railWalk, .railDestination].contains(landmark)
        }
    }
}

enum TerminalReplayLandmark: String {
    case lift = "t3-elevator-north"
    case corridor = "t3-gates-center"
    case gate = "gate-105"
    case arrivals = "t3-public-arrivals"
    case loungeEntrance = "t3-lounge-entrance"
    case immigration = "t3-arrivals-immigration"
    case baggageClaim = "t3-arrivals-baggage"
    case customs = "t3-arrivals-customs"
    case arrivalsExit = "t3-arrivals-exit"
    case shuttleStop = "t3-shuttle-stop-0"
    case outboundShuttle = "shuttle-to-t2"
    case terminalOne = "shuttle-via-t1"
    case terminalTwo = "t2-public-lift"
    case deck = "t2-observation-deck"
    case deckLift = "t2-deck-lift"
    case returnStop = "t2-shuttle-stop-9"
    case returnShuttle = "shuttle-to-t3"
    case departuresLift = "t3-departures-lift"
    case checkpoint = "t3-return-security"
    case screened = "t3-after-security"
    case arrivalGate = "t3-gate-105-arrival"
    case naritaExit = "t3-exit-to-buses"
    case naritaCurb = "t3-narita-stop-5"
    case railEntrance = "t3-keikyu-gates"
    case railDescent = "t3-keikyu-platform-lift"
    case railApproach = "t3-keikyu-platform-approach"
    case railWalk = "t3-keikyu-platform-walk"
    case railDestination = "t3-keikyu-platform-destination"

    var floor: Int {
        switch self {
        case .lift, .checkpoint, .screened, .arrivalGate: 3
        case .corridor, .gate, .loungeEntrance: 4
        case .arrivals, .railEntrance, .railDescent, .immigration, .baggageClaim, .customs, .arrivalsExit: 2
        case .deck, .deckLift: 5
        default: 1
        }
    }

    var requiresClearance: Bool { [.screened, .arrivalGate, .baggageClaim, .arrivalsExit].contains(self) }

    var facilityQueueKind: DriverFacilityQueue.Kind? {
        switch self {
        case .loungeEntrance: .lounge
        case .immigration: .immigration
        case .customs: .customs
        default: nil
        }
    }

    var instruction: String {
        switch self {
        case .lift: "Follow the Gates 105–109 sign"
        case .corridor, .screened: "Gate 105 ahead"
        case .gate, .arrivalGate: "Check your flight"
        case .arrivals: "Go down to the buses on 1F"
        case .shuttleStop: "Board at Stop 0"
        case .outboundShuttle, .terminalOne: "Stay on until Terminal 2"
        case .terminalTwo: "Take the lift to 5F"
        case .deck: "Return to Terminal 3"
        case .deckLift: "Take the lift to 1F"
        case .returnStop: "Board at Stop 9"
        case .returnShuttle: "Stay on until Terminal 3"
        case .departuresLift: "Take the lift to 3F"
        case .checkpoint: "Go through security"
        case .loungeEntrance: "Lounge entrance on your right"
        case .immigration: "Follow signs to immigration"
        case .baggageClaim: "Collect your checked bags"
        case .customs: "Follow signs to customs"
        case .arrivalsExit: "Continue to the arrivals hall"
        case .naritaExit: "Follow signs to Stop 5"
        case .naritaCurb: "Board the Narita bus"
        case .railEntrance: "Follow the Keikyu Line signs"
        case .railDescent: "Take the lift down to the platform"
        case .railApproach: "Head to the platform"
        case .railWalk: "Walk to the boarding point"
        case .railDestination: "Check for Narita Airport"
        }
    }

    var routeTitle: String {
        switch self {
        case .deck: "T2 Observation Deck"
        case .deckLift, .returnStop, .returnShuttle: "Route to Terminal 3"
        case .lift, .corridor, .departuresLift, .checkpoint, .screened, .arrivalGate, .gate: "Route to Gate 105"
        case .loungeEntrance: "Route to lounge"
        case .immigration, .baggageClaim, .customs, .arrivalsExit: "Route to arrivals"
        default: "Route to Terminal 2"
        }
    }

    var location: String {
        switch self {
        case .outboundShuttle: "T3 → T2 · Landside"
        case .terminalOne: "Via T1 · Landside"
        case .returnShuttle: "T2 → T3 · Landside"
        case .terminalTwo, .deck, .deckLift, .returnStop: "T2 · \(floor)F · Landside"
        case .screened, .arrivalGate, .gate: "T3 · \(floor)F · Airside"
        case .loungeEntrance: "T3 · Airside"
        case .immigration, .baggageClaim, .customs: "T3 · Arrivals"
        case .arrivalsExit: "T3 · 2F · Landside"
        case .railEntrance, .railDescent, .railApproach, .railWalk, .railDestination: "T3 · Landside"
        default: "T3 · \(floor)F · Landside"
        }
    }
}

enum TerminalCheckpointStage: Equatable {
    case security, immigration, baggage, customs

    var isArrival: Bool { self != .security }

    var currentStep: Int {
        switch self {
        case .immigration: 0
        case .security, .baggage: 1
        case .customs: 2
        }
    }

    var sign: String {
        switch self {
        case .security: "保安検査場 · Security"
        case .immigration: "入国審査 · Immigration Control"
        case .baggage: "手荷物受取 · Baggage Claim"
        case .customs: "税関検査 · Customs Inspection"
        }
    }
}

struct DriverFacilityQueue: Decodable, Equatable {
    enum Kind: String, Decodable {
        case lounge, immigration, customs

        var title: String {
            switch self {
            case .lounge: "Lounge queue"
            case .immigration: "Immigration queue"
            case .customs: "Customs queue"
            }
        }
    }

    // The security-only driver predates the combined facility payload.
    var kind: Kind? = nil
    let additionalWaitMinutes: Int
    let pedestrians: [DriverPedestrian]

    var isValid: Bool { (0...60).contains(additionalWaitMinutes) }
    var scenePedestrians: [DriverPedestrian] { DriverPedestrian.validated(pedestrians, limit: 12) }
}

struct TerminalReading: Decodable, Equatable {
    struct Point: Decodable, Hashable {
        let x: Float
        let y: Float
        var isValid: Bool { (0...1).contains(x) && (0...1).contains(y) }
    }

    let point: Point?
    let level: Int?
    let floorConfirmed: Bool
    let matchedNodeID: String?
    let source: String
    var headingDegrees: Float?
    var clearanceConfirmed: Bool?
    var mapFrameID: String? = nil
    var sequence: Int? = nil
    var shuttleFull: Bool? = nil
    var liftAvailable: Bool? = nil
    var routeRevision: Int? = nil
    var landmarkToken: Int? = nil
    var securityQueue: DriverFacilityQueue? = nil
    var facilityQueues: [DriverFacilityQueue]? = nil
    var checkpointEntered: Bool? = nil

    var landmark: TerminalReplayLandmark? { matchedNodeID.flatMap(TerminalReplayLandmark.init(rawValue:)) }
}

/// Guidance derived from a validated position and any current travel constraint.
struct TerminalGuidance {
    enum Checkpoint { case cafeStop, confirmCafe(Int) }
    let instruction: String
    var turn: RouteStep.Turn?
    var position: TerminalReading?
    var location: String?
    var lastConfirmedFloor: Int?
    var canFinish = false
    var checkpoint: Checkpoint? = nil
}

struct TerminalReplayState: Equatable {
    var route: TerminalReplayRoute = .gate
    var confirmed: TerminalReading?
    var awaitingFloor = false
    var awaitingCheckpoint = false
    var awaitingShuttle = false
    var awaitingLift = false
    var hasConnection = true
    private var securityReport: DriverFacilityQueue? = nil
    private var facilityReports: [DriverFacilityQueue] = []

    init(route: TerminalReplayRoute = .gate) {
        self.route = route
    }

    var checkpointStage: TerminalCheckpointStage? {
        switch confirmed?.landmark {
        case .checkpoint: .security
        case .immigration: .immigration
        case .baggageClaim: .baggage
        case .customs: .customs
        default: nil
        }
    }

    var cameraRestricted: Bool { checkpointStage != nil || (route == .arrivals && confirmed == nil) }

    var isApproachingCheckpoint: Bool {
        hasConnection && !awaitingCheckpoint && checkpointStage != nil && checkpointStage != .baggage
            && confirmed?.checkpointEntered == false
    }

    var securityQueue: DriverFacilityQueue? {
        guard hasConnection, route == .observationDeck,
              confirmed?.landmark == .checkpoint || confirmed?.landmark == .departuresLift,
              let report = securityReport, report.isValid else { return nil }
        return report
    }

    var facilityQueue: DriverFacilityQueue? {
        guard hasConnection, let kind = confirmed?.landmark?.facilityQueueKind else { return nil }
        let matching = facilityReports.filter { $0.kind == kind }
        guard matching.count == 1, let report = matching.first, report.isValid else { return nil }
        return report
    }

    var guidance: TerminalGuidance {
        let landmark = confirmed?.landmark
        let hold: String? = if !hasConnection { "Position unavailable" }
        else if awaitingFloor { "Wait for floor confirmation" }
        else if awaitingCheckpoint {
            switch landmark {
            case .immigration: "Wait for immigration clearance"
            case .customs: "Wait for customs clearance"
            default: "Wait for security clearance"
            }
        }
        else if awaitingShuttle { "This shuttle is full. Wait for the next one." }
        else if awaitingLift { "Lift unavailable. Ask airport staff for a step-free route." }
        else { nil }
        let atDestination = landmark.map { [.gate, .arrivalGate, .naritaCurb, .railDestination, .arrivalsExit].contains($0) } ?? false
        let location = route == .gate ? confirmed?.level.map { "\($0)F" } : landmark?.location
        return TerminalGuidance(instruction: hold ?? landmark?.instruction ?? "Waiting for your location",
                                position: confirmed, location: location,
                                lastConfirmedFloor: awaitingFloor || !hasConnection ? confirmed?.level : nil,
                                canFinish: hold == nil && atDestination)
    }

    mutating func receive(_ incoming: TerminalReading) {
        guard incoming.source == "externalSignalReplay", let landmark = incoming.landmark,
              route.includes(landmark), incoming.level == landmark.floor,
              (-360...360).contains(incoming.headingDegrees ?? 0) else { return }
        hasConnection = true
        securityReport = incoming.securityQueue
        facilityReports = if let reports = incoming.facilityQueues, reports.count <= 3 { reports } else { [] }
        awaitingFloor = !incoming.floorConfirmed || incoming.point?.isValid != true
        guard !awaitingFloor else { return }
        // The expanded journey requires an explicit scripted clearance observation.
        // Position, floor and heading can never establish permission to cross.
        awaitingCheckpoint = landmark.requiresClearance && incoming.clearanceConfirmed != true
        guard !awaitingCheckpoint else { return }
        let shuttleLandmarks: Set<TerminalReplayLandmark> =
            [.shuttleStop, .outboundShuttle, .terminalOne, .returnStop, .returnShuttle]
        let atShuttleStop = confirmed?.landmark == .shuttleStop || confirmed?.landmark == .returnStop
        awaitingShuttle = route == .observationDeck && incoming.shuttleFull == true
            && (awaitingShuttle || atShuttleStop || landmark == .shuttleStop || landmark == .returnStop)
            && shuttleLandmarks.contains(landmark)
        if awaitingShuttle && landmark != .shuttleStop && landmark != .returnStop { return }
        let lifts: Set<TerminalReplayLandmark> = [.lift, .terminalTwo, .deckLift, .departuresLift, .railDescent]
        let atLift = confirmed?.landmark.map(lifts.contains) == true
        awaitingLift = incoming.liftAvailable == false && (lifts.contains(landmark) || atLift)
        if awaitingLift && !lifts.contains(landmark) { return }
        // Queue observations change independently of the accepted traveler pose.
        var position = incoming
        position.securityQueue = nil
        position.facilityQueues = nil
        confirmed = position
    }
}

@MainActor
final class TerminalReplay: ObservableObject {
    let endpoint: URL?
    let route: TerminalReplayRoute
    let officialGate: String?
    var isCafeWalk: Bool { officialGate == "cafe" }
    var isAdaptiveWalk: Bool { isCafeWalk || officialGate == "adaptive" }
    var frame: String { isCafeWalk ? OfficialGateWalkPath.cafeConcourse : OfficialGateWalkPath.gateWing }
    @Published private(set) var state: TerminalReplayState
    @Published private(set) var officialWalk: OfficialGateWalkState?
    @Published private(set) var floorImage: UIImage?
    @Published private(set) var cafeResolved = false
    private let session = URLSession(configuration: .ephemeral, delegate: NoReplayRedirect(), delegateQueue: nil)

    init(arguments: [String]) {
        endpoint = Self.endpoint(arguments: arguments)
        officialGate = endpoint == nil ? nil : arguments.firstIndex(of: "--qa-official-walk").flatMap { index in
            guard arguments.indices.contains(index + 1), ["105", "108A", "adaptive", "cafe"].contains(arguments[index + 1]) else { return nil }
            return arguments[index + 1]
        }
        let requested = arguments.firstIndex(of: "--qa-terminal-route")
            .flatMap { arguments.indices.contains($0 + 1) ? TerminalReplayRoute(rawValue: arguments[$0 + 1]) : nil }
        route = endpoint != nil ? requested ?? .gate : .gate
        state = TerminalReplayState(route: route)
    }

    static func endpoint(arguments: [String]) -> URL? {
        #if DEBUG && targetEnvironment(simulator)
        guard arguments.contains("--uitesting"), let flag = arguments.firstIndex(of: "--qa-indoor-feed"),
              arguments.indices.contains(flag + 1), let url = URL(string: arguments[flag + 1]),
              url.scheme == "http", url.host == "127.0.0.1", url.port != nil,
              url.path == "/reading", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
        #else
        return nil
        #endif
    }

    func poll(store: JourneyStore) async {
        guard let endpoint else { return }
        while !Task.isCancelled {
            if let officialGate {
                if isAdaptiveWalk {
                    await pollAdaptiveWalk(store: store, endpoint: endpoint)
                } else {
                    await pollOfficialWalk(gate: officialGate, endpoint: endpoint)
                }
                try? await Task.sleep(for: .milliseconds(125))
                continue
            }
            var next = state
            if let (data, response) = try? await session.data(for: URLRequest(url: endpoint, timeoutInterval: 1)),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let reading = try? JSONDecoder().decode(TerminalReading.self, from: data) {
                next.receive(reading)
            } else {
                next.hasConnection = false
            }
            guard !Task.isCancelled else { return }
            if next != state { state = next }
            try? await Task.sleep(for: .milliseconds(125))
        }
    }

    func loadOfficialFloor() async {
        guard officialGate != nil, floorImage == nil,
              let data = await fetch(OfficialGateWalkPath.sourceURL, timeout: 8) else { return }
        // The route coordinates belong to this exact floor-plan revision.
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == OfficialGateWalkPath.sourceSHA256 else { return }
        floorImage = UIImage(data: data)
    }

    private func pollOfficialWalk(gate: String, endpoint: URL) async {
        if officialWalk == nil {
            let url = endpoint.deletingLastPathComponent().appendingPathComponent("map-path")
            guard let data = await fetch(url), let path = try? JSONDecoder().decode(OfficialGateWalkPath.self, from: data),
                  path.matches(gate: gate) else { return }
            officialWalk = OfficialGateWalkState(path: path)
        }
        let data = await fetch(endpoint)
        guard !Task.isCancelled, var next = officialWalk else { return }
        let reading = data.flatMap { try? JSONDecoder().decode(TerminalReading.self, from: $0) }
        next.receive(reading)
        if next != officialWalk { officialWalk = next }
    }

    private func pollAdaptiveWalk(store: JourneyStore, endpoint: URL) async {
        let gate = store.gate
        let assignment = store.gateAssignmentRevision
        guard ["105", "108A"].contains(gate), !store.isAirportTransfer,
              store.tripFlight.number == TripFlight.sample.number,
              store.tripFlight.date == TripFlight.sample.date else { return }
        let base = endpoint.deletingLastPathComponent()
        let pathURL = base.appendingPathComponent("map-path")
        let quieter = store.routeChoice == .lessCrowded
        if cafeResolved, !store.plan.contains(.cafe) { cafeResolved = false }
        let viaCafe = shouldVisitCafe(store: store)
        let control = "control/gate-\(gate.lowercased())" + (quieter ? "-quieter" : "") + (viaCafe ? "-cafe" : "")
        // The driver acknowledges unchanged requests without replacing its current trace.
        var request = URLRequest(url: base.appendingPathComponent(control), timeoutInterval: 1)
        request.httpMethod = "POST"
        guard let (_, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let data = await fetch(pathURL),
              let path = try? JSONDecoder().decode(OfficialGateWalkPath.self, from: data),
              path.revision != nil, path.matches(gate: gate, frame: frame, viaCafe: viaCafe), path.prefersQuieter == quieter else {
            holdOfficialWalk()
            return
        }
        let reading = await fetch(endpoint).flatMap { try? JSONDecoder().decode(TerminalReading.self, from: $0) }
        guard !Task.isCancelled, assignment == store.gateAssignmentRevision, gate == store.gate,
              quieter == (store.routeChoice == .lessCrowded), viaCafe == shouldVisitCafe(store: store) else { return }
        if let revision = officialWalk?.path.revision, let nextRevision = path.revision, nextRevision < revision {
            holdOfficialWalk()
            return
        }
        var next = OfficialGateWalkState(path: path, retaining: officialWalk)
        if var previous = officialWalk, previous.path.revision == path.revision {
            guard previous.updateConditions(from: path) else {
                holdOfficialWalk()
                return
            }
            next = previous
        }
        next.receive(reading)
        if next != officialWalk { officialWalk = next }
    }

    private func holdOfficialWalk() {
        guard var walk = officialWalk, walk.positionAvailable || walk.landmarkToken != nil else { return }
        walk.receive(nil)
        officialWalk = walk
    }

    func shouldVisitCafe(store: JourneyStore) -> Bool {
        isCafeWalk && !cafeResolved && store.guidanceSchedule(for: store.routeChoice).stops.map(\.stop.id) == [.cafe]
    }

    func resolveCafe(store: JourneyStore) {
        guard shouldVisitCafe(store: store), let walk = officialWalk,
              walk.path.matches(gate: store.gate, frame: frame, viaCafe: true), walk.atCafe else { return }
        cafeResolved = true
    }

    func confirmCafe(token: Int, store: JourneyStore) async {
        guard shouldVisitCafe(store: store), officialWalk?.landmarkToken == token,
              let endpoint, let walk = officialWalk,
              walk.path.matches(gate: store.gate, frame: frame, viaCafe: true) else { return }
        let url = endpoint.deletingLastPathComponent().appendingPathComponent("control/confirm-cafe-\(token)")
        var request = URLRequest(url: url, timeoutInterval: 1)
        request.httpMethod = "POST"
        // Only the driver's next matching observation can restore confirmed position.
        _ = try? await session.data(for: request)
    }

    private func fetch(_ url: URL, timeout: TimeInterval = 1) async -> Data? {
        guard let (data, response) = try? await session.data(for: URLRequest(url: url, timeoutInterval: timeout)),
              !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

private final class NoReplayRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
