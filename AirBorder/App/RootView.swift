import SwiftUI

/// Screens pushed on top of a tab.
enum Destination: Hashable {
    case journeyDetails, journeySteps, myPlan, editStop(PlaceID), addFlight, importFlight, manualEntry
    case reviewEntered(ManualFlight), manualFlights, editFlight, chooseFlight, chooseDate, choosePurpose
    case checkFlight, flightSaved, baggage, declareBaggage, returnFlight
    case cameraPermission, ticketCamera, cameraUnavailable, unreadableTicket, capturedReview(ParsedTicket), ticketSaved
    case addToPlan, cafeAvailability, routeThroughStops, routeDetail(RouteChoice), openAnotherMap, returnToGate(PlaceID)
    case anaLounge, loungeMap, landsideRoute(Bool), facilityGuide, t2Deck, t2NotEnoughTime, toTerminal2, atTerminal2, returnFromT2, shuttleFull
    case choosePDF, importWallet, connectGmail, connectCalendar, reviewImported(ParsedTicket), flightUpdated, reviewFlight
    case connectedAccounts, healthPermission, removeHealth, airportWalking, previousTrips, savedFlights
    case language, about, help, editProfile, tutorial, routeOptions
    case alerts(AlertPresentation)

    // Replace the active alert in place so Back returns to the original screen.
    static func presentingAlert(_ alert: AlertPresentation, on path: [Self]) -> [Self] {
        withoutActiveAlert(in: path) + [.alerts(alert)]
    }

    static func withoutActiveAlert(in path: [Self]) -> [Self] {
        if case .alerts = path.last { return Array(path.dropLast()) }
        return path
    }

    static func showingArrivalAfterClosure(on path: [Self]) -> [Self] {
        // The Flight root exposes the after-closure warning and boarding assistance together.
        if case .alerts = path.last { return [] }
        return path
    }
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
            if let toast = store.toast {
                ToastView(toast: toast, perform: toast.action == nil ? nil : { store.performToastAction() })
                    .padding(.bottom, showsTabBar ? 104 : 24)
                    .transition(.opacity)
                    .zIndex(2)
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
        .onChange(of: store.primaryCondition) { dismissSupersededAlert() }
        .onAppear { presentAlert() }
        .onChange(of: store.onboardingSeen) { presentAlert() }
        .fullScreenCover(isPresented: Binding(get: { !store.onboardingSeen }, set: { _ in })) {
            OnboardingFlow(startAt: 0) {}.environmentObject(store)
        }
    }

    /// A new alert opens the Alerts screen on the Flight tab, as the Figma gate update does.
    private func presentAlert() {
        guard let alert = store.alertToPresent, store.onboardingSeen else { return }
        store.alertToPresent = nil
        store.tab = .flight
        paths[.flight] = Destination.presentingAlert(alert, on: paths[.flight, default: []])
    }

    private func dismissSupersededAlert() {
        guard case .arrivesAfterClosure = store.primaryCondition else { return }
        paths[.flight] = Destination.showingArrivalAfterClosure(on: paths[.flight, default: []])
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
        case .addToPlan: AddToPlanView()
        case .cafeAvailability: CafeAvailabilityView()
        case .routeThroughStops: RouteThroughStopsView()
        case let .routeDetail(choice): RouteDetailView(choice: choice)
        case .openAnotherMap: OpenAnotherMapView()
        case let .returnToGate(place): ReturnToGateView(place: place)
        case .anaLounge: ANALoungeView()
        case .loungeMap: LoungeMapView()
        case let .landsideRoute(deck): LandsideRouteView(observationDeck: deck)
        case .facilityGuide: FacilityGuideView()
        case .t2Deck: T2DeckView()
        case .t2NotEnoughTime: T2NotEnoughTimeView()
        case .toTerminal2: ToTerminal2View()
        case .atTerminal2: AtTerminal2View()
        case .returnFromT2: ReturnFromT2View()
        case .shuttleFull: ShuttleFullView()
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
        case .routeOptions: RouteOptionsView()
        case let .alerts(alert): AlertsView(presentation: alert).id(alert)
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

/// Profile › Replay tutorial (Figma link to Onboarding 1).
private struct TutorialReplay: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        OnboardingFlow(startAt: 1) { dismiss() }
    }
}
