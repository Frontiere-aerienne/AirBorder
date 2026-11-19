// SUBSTANTIVE: Connects the journey store to the route and provider drivers.
import SwiftUI

@main
struct AirBorderApp: App {
    @StateObject private var store: JourneyStore
    @StateObject private var terminalReplay: TerminalReplay
    @StateObject private var airportProvider: AirportProviderReplay

    init() {
        Outfit.register()
        let arguments = ProcessInfo.processInfo.arguments
        let replay = TerminalReplay(arguments: arguments)
        let provider = AirportProviderReplay(arguments: arguments)
        let source: WalkingDataSource
        if let index = arguments.firstIndex(of: "-walkingSpeed"), arguments.indices.contains(index + 1) {
            source = FixedWalkingData(kmh: Double(arguments[index + 1]))
        } else {
            source = AppleHealthWalkingData()
        }
        let store = JourneyStore(walkingData: source, reset: arguments.contains("-resetState"))
        if arguments.contains("-skipOnboarding") { store.onboardingSeen = true }
        #if DEBUG && targetEnvironment(simulator)
        // The Mac walk launcher opens the existing Route tab. Ordinary launches
        // and device builds retain their normal entry point and navigation.
        if arguments.contains("--qa-open-route"), replay.endpoint != nil { store.tab = .route }
        #endif
        // Sample journey options: "-now 17:10" shows the trip at another airport time;
        // "-gateUpdate off|0|30" sets when the sample gate update arrives (seconds).
        if let index = arguments.firstIndex(of: "-now"), arguments.indices.contains(index + 1) {
            let parts = arguments[index + 1].split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { store.setNow(ClockTime(parts[0], parts[1])) }
        }
        // "-flight NH6" opens the trip on NH 6 from Narita (the Haneda → Narita transfer).
        let naritaRequested = arguments.firstIndex(of: "-flight")
            .map { arguments.indices.contains($0 + 1) && arguments[$0 + 1] == "NH6" } ?? false
        if naritaRequested || replay.route.usesNaritaItinerary {
            store.beginEditingFlight()
            store.flightDraft.number = "NH 6"
            store.saveFlightDraft()
        }
        if provider.supports(store.tripFlight) {
            // A saved wait cannot stand in for the provider's first report after launch.
            store.receiveDriverCafeWait(nil)
        }
        var gateUpdateDelay: Double? = replay.endpoint == nil ? 45 : nil
        if let index = arguments.firstIndex(of: "-gateUpdate"), arguments.indices.contains(index + 1) {
            gateUpdateDelay = Double(arguments[index + 1])
        }
        if provider.endpoint == nil, let gateUpdateDelay { store.startSampleFeed(after: .seconds(gateUpdateDelay)) }
        _store = StateObject(wrappedValue: store)
        _terminalReplay = StateObject(wrappedValue: replay)
        _airportProvider = StateObject(wrappedValue: provider)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(terminalReplay)
                .environmentObject(airportProvider)
                .task { await store.refreshWalkingSpeed() }
                .task { await terminalReplay.poll(store: store) }
                .task { await terminalReplay.loadOfficialFloor() }
                .task { await airportProvider.poll(into: store) }
        }
    }
}
