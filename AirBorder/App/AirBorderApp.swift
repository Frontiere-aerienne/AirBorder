import SwiftUI

@main
struct AirBorderApp: App {
    @StateObject private var store: JourneyStore

    init() {
        Outfit.register()
        let arguments = ProcessInfo.processInfo.arguments
        let source: WalkingDataSource
        if let index = arguments.firstIndex(of: "-walkingSpeed"), arguments.indices.contains(index + 1) {
            source = FixedWalkingData(kmh: Double(arguments[index + 1]))
        } else {
            source = AppleHealthWalkingData()
        }
        let store = JourneyStore(walkingData: source, reset: arguments.contains("-resetState"))
        if arguments.contains("-skipOnboarding") { store.onboardingSeen = true }
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.refreshWalkingSpeed() }
        }
    }
}
