import SwiftUI

/// Screens pushed on top of a tab.
enum Destination: Hashable {
    case journeyDetails, journeySteps, myPlan, editStop(PlaceID), addFlight
    case connectedAccounts, healthPermission, removeHealth, airportWalking, previousTrips, savedFlights
    case language, about, privacy, help, editProfile, tutorial, routeOptions
}

struct RootView: View {
    @EnvironmentObject private var store: JourneyStore
    @State private var paths: [AppTab: [Destination]] = [:]

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: binding(for: tab)) {
                    root(for: tab)
                        .navigationDestination(for: Destination.self) { destination(for: $0) }
                }
                .opacity(store.tab == tab ? 1 : 0)
                .allowsHitTesting(store.tab == tab)
                .accessibilityHidden(store.tab != tab)
            }
            if showsTabBar {
                TabBar(selection: $store.tab).offset(y: 10)
            }
        }
        .background(AB.screen.ignoresSafeArea())
        .environment(\.openDestination, OpenDestinationAction { destination in
            paths[store.tab, default: []].append(destination)
        })
        .environment(\.popToRoot, PopToRootAction { paths[store.tab] = [] })
        .fullScreenCover(isPresented: Binding(get: { !store.onboardingSeen }, set: { _ in })) {
            TutorialView(onFinish: {}).environmentObject(store)
        }
    }

    /// The tab bar shows on the four tab roots and on Journey details, as in Figma.
    private var showsTabBar: Bool {
        let path = paths[store.tab] ?? []
        return path.isEmpty || path == [.journeyDetails]
    }

    private func binding(for tab: AppTab) -> Binding<[Destination]> {
        Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .flight: FlightView()
        case .layover: LayoverView()
        case .route: RouteView()
        case .profile: ProfileView()
        }
    }

    @ViewBuilder
    private func destination(for destination: Destination) -> some View {
        switch destination {
        case .journeyDetails: JourneyDetailsView()
        case .journeySteps: JourneyStepsView()
        case .myPlan: MyPlanView()
        case let .editStop(id): EditStopView(stopID: id)
        case .addFlight: AddFlightView()
        case .connectedAccounts: ConnectedAccountsView()
        case .healthPermission: HealthPermissionView()
        case .removeHealth: RemoveHealthView()
        case .airportWalking: AirportWalkingView()
        case .previousTrips: PreviousTripsView()
        case .savedFlights: SavedFlightsView()
        case .language: LanguageView()
        case .about: AboutView()
        case .privacy: PrivacyView()
        case .help: AboutView()
        case .editProfile: EditProfileView()
        case .tutorial: TutorialView()
        case .routeOptions: RouteOptionsView()
        }
    }
}

// MARK: - Navigation helpers

struct OpenDestinationAction {
    let handler: (Destination) -> Void
    func callAsFunction(_ destination: Destination) { handler(destination) }
}

private struct OpenDestinationKey: EnvironmentKey {
    static let defaultValue = OpenDestinationAction { _ in }
}

struct PopToRootAction {
    let handler: () -> Void
    func callAsFunction() { handler() }
}

private struct PopToRootKey: EnvironmentKey {
    static let defaultValue = PopToRootAction {}
}

extension EnvironmentValues {
    var openDestination: OpenDestinationAction {
        get { self[OpenDestinationKey.self] }
        set { self[OpenDestinationKey.self] = newValue }
    }

    var popToRoot: PopToRootAction {
        get { self[PopToRootKey.self] }
        set { self[PopToRootKey.self] = newValue }
    }
}

// MARK: - Tab bar (Figma "Tab Bar")

struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = selection == tab
                Button { selection = tab } label: {
                    VStack(spacing: tab == .profile ? 4 : 3) {
                        icon(for: tab, selected: selected)
                        Text(tab.title).outfitText(12, selected ? .bold : .regular, selected ? AB.primary : AB.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .padding(.vertical, 7)
                    .background(selected ? AB.primary.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 26))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(width: 378)
        .background(.white, in: RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(AB.border, lineWidth: 1))
        .shadow(color: AB.navy.opacity(0.14), radius: 7.5, x: 0, y: 10)
    }

    @ViewBuilder
    private func icon(for tab: AppTab, selected: Bool) -> some View {
        let name: String = switch tab {
        case .flight: selected ? "tabFlightOn" : "tabFlightOff"
        case .layover: selected ? "tabLayoverOn" : "tabLayoverOff"
        case .route: selected ? "tabRouteOn" : "tabRouteOff"
        case .profile: selected ? "tabProfileOn" : "tabProfileOff"
        }
        if tab == .profile {
            Image(name).resizable().frame(width: 26.25, height: 26.25).offset(y: 1).frame(width: 21, height: 21)
        } else {
            Image(name).resizable().frame(width: 21, height: 21)
        }
    }
}

/// Bottom space so scroll content clears the floating tab bar.
let tabBarClearance: CGFloat = 110
