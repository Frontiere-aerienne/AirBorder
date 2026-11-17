import SwiftUI

/// Screens pushed on top of a tab.
enum Destination: Hashable {
    case journeyDetails, journeySteps, addFlight, importFlight, manualEntry
    case reviewEntered(ManualFlight), manualFlights, editFlight, chooseFlight, chooseDate, choosePurpose
    case checkFlight, flightSaved, baggage, declareBaggage, returnFlight
    case cameraPermission, ticketCamera, cameraUnavailable, unreadableTicket, capturedReview(ParsedTicket), ticketSaved
    case returnToGate(PlaceID)
    case anaLounge, loungeMap, landsideRoute(Bool), facilityGuide, t2Deck, t2NotEnoughTime, toTerminal2, atTerminal2, returnFromT2, shuttleFull
    case choosePDF, importWallet, connectGmail, connectCalendar, reviewImported(ParsedTicket), flightUpdated, reviewFlight
    case connectedAccounts, healthPermission, removeHealth, airportWalking, previousTrips, savedFlights
    case language, about, help, editProfile, tutorial
    case alerts(AlertKind)
}

struct RootView: View {
    @EnvironmentObject private var store: JourneyStore
    @State private var paths: [AppTab: [Destination]] = [:]
    @State private var showsGateAlert = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Apple's tab bar: Liquid Glass on iOS 26 and later, the standard bar on iOS 18.
            TabView(selection: $store.tab) {
                ForEach(AppTab.allCases) { tab in
                    NavigationStack(path: binding(for: tab)) {
                        root(for: tab)
                            .navigationDestination(for: Destination.self) { destination in
                                self.destination(for: destination)
                                    .toolbar(destination == .journeyDetails ? .visible : .hidden, for: .tabBar)
                            }
                    }
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .accessibilityIdentifier("tab-\(tab.rawValue)")
                    .tag(tab)
                }
            }
            .tint(AB.primary)
            if let toast = store.toast {
                ToastView(toast: toast, perform: toast.action == nil ? nil : { store.performToastAction() })
                    .padding(.bottom, showsTabBar ? 96 : 24)
                    .transition(.opacity)
                    .zIndex(2)
            }
            if showsGateAlert {
                GateChangeAlert { showsGateAlert = false }
                    .transition(.opacity)
                    .zIndex(3)
            }
            if store.asksForCamera {
                CameraPrompt()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .background(AB.screen.ignoresSafeArea())
        .animation(.easeOut(duration: 0.2), value: showsGateAlert)
        .animation(.easeOut(duration: 0.2), value: store.asksForCamera)
        .environment(\.openDestination, OpenDestinationAction { destination in
            paths[store.tab, default: []].append(destination)
        })
        .environment(\.popToRoot, PopToRootAction { paths[store.tab] = [] })
        .environment(\.popTo, PopToAction { target in
            var path = paths[store.tab] ?? []
            if let index = path.lastIndex(of: target) {
                path.removeSubrange((index + 1)...)
            } else {
                path.append(target)
            }
            paths[store.tab] = path
        })
        .onChange(of: store.alertToPresent) { presentAlert() }
        .onAppear { presentAlert() }
        .onChange(of: store.onboardingSeen) { presentAlert() }
        .fullScreenCover(isPresented: Binding(get: { !store.onboardingSeen }, set: { _ in })) {
            OnboardingFlow(startAt: 0) {}.environmentObject(store)
        }
    }

    /// A gate change shows the Figma alert over the current screen; other alerts open the Alerts screen on Flight.
    private func presentAlert() {
        guard let kind = store.alertToPresent, store.onboardingSeen else { return }
        store.alertToPresent = nil
        if kind == .gateChange {
            showsGateAlert = true
            return
        }
        store.tab = .flight
        if paths[.flight]?.last != .alerts(kind) {
            paths[.flight, default: []].append(.alerts(kind))
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
        case .addFlight: AddFlightSummaryView()
        case .importFlight: AddFlightView()
        case .manualEntry: ManualEntryView()
        case let .reviewEntered(flight): ReviewEnteredView(flight: flight)
        case .manualFlights: ManualFlightsView()
        case .editFlight: EditFlightView()
        case .chooseFlight: ChooseFlightView()
        case .chooseDate: ChooseDateView()
        case .choosePurpose: ChoosePurposeView()
        case .checkFlight: CheckFlightView()
        case .flightSaved: FlightSavedView()
        case .baggage: BaggageView()
        case .declareBaggage: DeclareBaggageView()
        case .returnFlight: ReturnFlightView()
        case .cameraPermission: CameraPermissionView()
        case .ticketCamera: TicketCameraView()
        case .cameraUnavailable: CameraUnavailableView()
        case .unreadableTicket: UnreadableTicketView()
        case let .capturedReview(ticket): CapturedReviewView(ticket: ticket)
        case .ticketSaved: TicketSavedView()
        case .choosePDF: ChoosePDFView()
        case .importWallet: ImportWalletView()
        case .connectGmail: ConnectGoogleView(calendar: false)
        case .connectCalendar: ConnectGoogleView(calendar: true)
        case let .reviewImported(ticket): ReviewImportedView(ticket: ticket)
        case .flightUpdated: FlightUpdatedView()
        case .reviewFlight: ReviewFlightView()
        case let .returnToGate(place): coveredFacility { ReturnToGateView(place: place) }
        case .anaLounge: coveredFacility { ANALoungeView() }
        case .loungeMap: coveredFacility { LoungeMapView() }
        case let .landsideRoute(deck): coveredFacility { LandsideRouteView(observationDeck: deck) }
        case .facilityGuide: coveredFacility { FacilityGuideView() }
        case .t2Deck: coveredFacility { T2DeckView() }
        case .t2NotEnoughTime: coveredFacility { T2NotEnoughTimeView() }
        case .toTerminal2: coveredFacility { ToTerminal2View() }
        case .atTerminal2: coveredFacility { AtTerminal2View() }
        case .returnFromT2: coveredFacility { ReturnFromT2View() }
        case .shuttleFull: coveredFacility { ShuttleFullView() }
        case .connectedAccounts: ConnectedAccountsView()
        case .healthPermission: HealthPermissionView()
        case .removeHealth: RemoveHealthView()
        case .airportWalking: AirportWalkingView()
        case .previousTrips: PreviousTripsView()
        case .savedFlights: SavedFlightsView()
        case .language: LanguageView()
        case .about: AboutView()
        case .help: AboutView()
        case .editProfile: EditProfileView()
        case .tutorial: TutorialReplay()
        case let .alerts(kind): AlertsView(kind: kind)
        }
    }

    @ViewBuilder
    private func coveredFacility<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if store.hasConcourseCoverage {
            content()
        } else {
            PlaceScreen(title: "Facilities") {
                Text("This connection has no available facility directions.")
                    .outfitText(15, .regular, AB.muted)
            }
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

struct PopToAction {
    let handler: (Destination) -> Void
    func callAsFunction(_ destination: Destination) { handler(destination) }
}

private struct PopToKey: EnvironmentKey {
    static let defaultValue = PopToAction { _ in }
}

private struct PopToRootKey: EnvironmentKey {
    static let defaultValue = PopToRootAction {}
}

extension EnvironmentValues {
    var openDestination: OpenDestinationAction {
        get { self[OpenDestinationKey.self] }
        set { self[OpenDestinationKey.self] = newValue }
    }

    var popTo: PopToAction {
        get { self[PopToKey.self] }
        set { self[PopToKey.self] = newValue }
    }

    var popToRoot: PopToRootAction {
        get { self[PopToRootKey.self] }
        set { self[PopToRootKey.self] = newValue }
    }
}

/// Extra space under scroll content; the system tab bar already insets it.
let tabBarClearance: CGFloat = 24

/// Profile › Replay tutorial (Figma link to Onboarding 1).
private struct TutorialReplay: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        OnboardingFlow(startAt: 1) { dismiss() }
    }
}
