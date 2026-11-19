// SUBSTANTIVE: Validates synthetic operator updates against the active itinerary and gate.
import Foundation
import SwiftUI

struct AirportProviderAssignment: Decodable, Equatable {
    let source: String
    let flight: String
    let date: String
    let airport: String
    let terminal: String
    let gate: String
    let revision: Int
    let mapAvailable: Bool

    @MainActor
    func matchesTrip(_ store: JourneyStore) -> Bool {
        source == "syntheticAirportProvider" && revision >= 0
            && store.tripFlight.number == flight && store.outbound.number == flight && store.tripFlight.date == date
            && airport == store.outbound.from.code && terminal == store.outbound.departureTerminal
            && airport == "HND" && terminal == "3" && ["105", "108A"].contains(gate)
    }
}

/// The driver sends independent observations, so a gate change cannot renew an old queue estimate.
struct DriverPlanningSnapshot: Decodable, Equatable {
    struct Wait: Decodable, Equatable {
        let minutes: Int
        let observedAt: TimeInterval
    }

    struct Crowd: Decodable, Equatable {
        enum Level: String, Decodable { case moderate, busy }
        let level: Level
        let observedAt: TimeInterval
    }

    struct FlightStatus: Decodable, Equatable {
        enum Value: String, Decodable { case onSchedule, delayed }
        let value: Value
        let observedAt: TimeInterval
    }

    struct Replacement: Decodable, Equatable, Identifiable {
        let id: String
        let from: String
        let to: String
        let dayOffset: Int
        let departureMinute: Int

        var departure: ClockTime { ClockTime(minutes: departureMinute) }
    }

    struct Lounge: Decodable, Equatable, Identifiable {
        enum Access: String, Decodable { case businessClass, paidEntry }
        let place: PlaceID
        let walkMinutes: Int
        let access: Access

        var id: PlaceID { place }
    }

    struct Guide: Decodable, Equatable, Identifiable {
        let code: String
        let name: String
        let city: String
        let terminals: [String]

        var id: String { code }
    }

    let source: String
    let flight: String
    let date: String
    let airport: String
    let terminal: String
    let gate: String
    let assignmentRevision: Int
    let revision: Int
    let gateCheckedAt: TimeInterval
    let security: Wait
    let cafe: Wait
    let crowd: Crowd
    let status: FlightStatus
    let flightsCheckedAt: TimeInterval
    let flights: [Replacement]
    let lounges: [Lounge]
    let airports: [Guide]

    static func isFresh(_ timestamp: TimeInterval, at time: Date) -> Bool {
        let age = time.timeIntervalSince1970 - timestamp
        return (0..<15 * 60).contains(age)
    }

    func matches(_ assignment: AirportProviderAssignment) -> Bool {
        source == assignment.source && flight == assignment.flight && date == assignment.date
            && airport == assignment.airport && terminal == assignment.terminal && gate == assignment.gate
            && assignmentRevision == assignment.revision && revision >= 0
            && (0...180).contains(security.minutes) && (0...180).contains(cafe.minutes)
            && lounges.count == Set(lounges.map(\.id)).count
            && lounges.allSatisfy { [.anaLounge, .skyLounge].contains($0.place) && (1...60).contains($0.walkMinutes) }
            && flights.count == Set(flights.map(\.id)).count
            && airports.count == Set(airports.map(\.id)).count
    }

    func onwardOptions(to destination: String, fromTime now: ClockTime) -> [Replacement] {
        flights.filter {
            $0.from == airport && $0.to == destination && (0...2).contains($0.dayOffset)
                && (0..<1440).contains($0.departureMinute) && ($0.dayOffset > 0 || $0.departure > now)
        }.sorted {
            ($0.dayOffset, $0.departureMinute) < ($1.dayOffset, $1.departureMinute)
        }
    }
}

@MainActor
final class AirportProviderReplay: ObservableObject {
    let endpoint: URL?
    @Published private(set) var planning: DriverPlanningSnapshot?
    @Published private(set) var planningReachable = false
    @Published private(set) var planningOffline = false
    @Published private(set) var planningLastChecked: Date?
    private var latest: AirportProviderAssignment?
    private let session = URLSession(configuration: .ephemeral, delegate: AirportProviderNoRedirect(), delegateQueue: nil)

    init(arguments: [String]) {
        endpoint = Self.configuredEndpoint(arguments)
    }

    func supports(_ trip: TripFlight) -> Bool {
        endpoint != nil && trip.number == TripFlight.sample.number && trip.date == TripFlight.sample.date
    }

    private static func configuredEndpoint(_ arguments: [String]) -> URL? {
        #if DEBUG && targetEnvironment(simulator)
        guard arguments.contains("--uitesting"),
              let index = arguments.firstIndex(of: "--qa-airport-provider"),
              arguments.indices.contains(index + 1), let url = URL(string: arguments[index + 1]),
              url.scheme == "http", url.host == "127.0.0.1", let port = url.port, (1...65535).contains(port),
              url.path == "/v1/assignment", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
        #else
        return nil
        #endif
    }

    func poll(into store: JourneyStore) async {
        guard endpoint != nil else { return }
        while !Task.isCancelled {
            if let assignment = await refresh(store: store) {
                await refreshPlanning(assignment: assignment, store: store)
            } else {
                markPlanningUnavailable(store: store)
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func refreshPlanning(assignment: AirportProviderAssignment, store: JourneyStore) async {
        guard let endpoint,
              let data = await providerData(at: endpoint.deletingLastPathComponent().appendingPathComponent("planning")),
              let snapshot = try? JSONDecoder().decode(DriverPlanningSnapshot.self, from: data),
              assignment == latest, assignment.matchesTrip(store), snapshot.matches(assignment), snapshot.gate == store.gate,
              planning.map({ snapshot.revision > $0.revision || snapshot == $0 }) ?? true else {
            markPlanningUnavailable(store: store)
            return
        }
        if planning != snapshot { planning = snapshot }
        if !planningReachable { planningReachable = true }
        let now = Date()
        let checkedMinute = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60)
        if planningLastChecked != checkedMinute { planningLastChecked = checkedMinute }
        let usable = DriverPlanningSnapshot.isFresh(snapshot.cafe.observedAt, at: now)
        store.receiveDriverCafeWait(usable ? snapshot.cafe.minutes : nil)
    }

    private func markPlanningUnavailable(store: JourneyStore) {
        if planningReachable { planningReachable = false }
        if supports(store.tripFlight) {
            store.receiveDriverCafeWait(nil)
        } else {
            if planning != nil { planning = nil }
            if planningLastChecked != nil { planningLastChecked = nil }
            store.clearDriverCafeWait()
        }
    }

    func currentPlanning(for store: JourneyStore) -> DriverPlanningSnapshot? {
        guard supports(store.tripFlight), let planning,
              planning.airport == store.outbound.from.code, planning.terminal == store.outbound.departureTerminal,
              planning.gate == store.gate else { return nil }
        if planningReachable, planning.assignmentRevision != latest?.revision { return nil }
        return planning
    }

    /// Keep the suggestion tied to the same appointment, walk and wait that the plan will use.
    func fittingCafe(for store: JourneyStore, at now: Date = Date()) -> (stop: PlanStop, arrival: ClockTime)? {
        guard planningReachable, let planning = currentPlanning(for: store),
              DriverPlanningSnapshot.isFresh(planning.gateCheckedAt, at: now),
              DriverPlanningSnapshot.isFresh(planning.cafe.observedAt, at: now),
              DriverPlanningSnapshot.isFresh(planning.status.observedAt, at: now),
              planning.status.value == .onSchedule,
              planning.gate == SampleJourney.outbound.departureGate else { return nil }
        return store.fittingCafe(waitMinutes: planning.cafe.minutes)
    }

    func addFittingCafe(_ reviewed: PlanStop, arrival: ClockTime, to store: JourneyStore) -> Bool {
        guard let offer = fittingCafe(for: store), offer.stop == reviewed, offer.arrival == arrival else { return false }
        store.add(offer.stop)
        return true
    }

    func onwardOptions(for store: JourneyStore, at now: Date = Date()) -> [DriverPlanningSnapshot.Replacement] {
        guard planningReachable, let planning = currentPlanning(for: store),
              DriverPlanningSnapshot.isFresh(planning.flightsCheckedAt, at: now) else { return [] }
        return planning.onwardOptions(to: store.outbound.to.code, fromTime: store.now)
    }

    @discardableResult
    func refresh(store: JourneyStore) async -> AirportProviderAssignment? {
        guard let endpoint, let data = await providerData(at: endpoint),
              let assignment = try? JSONDecoder().decode(AirportProviderAssignment.self, from: data),
              assignment.matchesTrip(store) else { return nil }
        if let latest {
            guard assignment.revision > latest.revision || assignment == latest else { return nil }
        }
        latest = assignment
        // Apply only changes. Repeated polling never creates a second gate alert or advances a route.
        if store.gate != assignment.gate {
            store.receive(FlightFeed(gate: assignment.gate, receivedAt: store.now))
        }
        return assignment
    }

    private func providerData(at url: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 1.5))
            guard !Task.isCancelled else { return nil }
            let offline = (try? JSONDecoder().decode(ProviderFailure.self, from: data))?.error == "network_unavailable"
            if planningOffline != offline { planningOffline = offline }
            return (response as? HTTPURLResponse)?.statusCode == 200 ? data : nil
        } catch {
            if !Task.isCancelled {
                let offline = (error as? URLError)?.code == .notConnectedToInternet
                if planningOffline != offline { planningOffline = offline }
            }
            return nil
        }
    }

    func mapURL(for assignment: AirportProviderAssignment) -> URL? {
        guard assignment == latest, assignment.mapAvailable,
              let endpoint, var url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        // Build the location on the configured loopback origin. The feed never supplies a URL.
        url.path = "/map/\(assignment.airport)/\(assignment.terminal)/\(assignment.gate)"
        url.queryItems = [URLQueryItem(name: "rev", value: String(assignment.revision))]
        return url.url
    }
}

private struct ProviderFailure: Decodable {
    let error: String
}

private final class AirportProviderNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
