import AVFoundation
import SwiftUI

/// Colours of the Figma "Travel update" tones and alert tags.
extension AB {
    static let amber = Color(hex: 0x82550B)
    static let warningTint = Color(hex: 0xFFFBF2)
    static let returnTint = Color(hex: 0xFFF5F2)
    static let riskTint = Color(hex: 0xFFF2F0)
    static let returnTag = Color(hex: 0xED9E38)
    static let riskTag = Color(hex: 0xDB5247)
}

extension JourneyStore {
    var boardingContact: BoardingContact? { journey.presentation?.boardingContact }
}

/// Where a travel update is shown; the copy and action follow the Figma screen for that place.
enum UpdatePlace {
    case flight, details, layover, route
}

/// Figma "Travel update" (862:16293): a tinted strip with an icon, a short message and an action.
struct TravelUpdateBanner: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.openURL) private var openURL
    let condition: JourneyCondition
    let place: UpdatePlace
    @State private var showsAssistance = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: tap) {
                HStack(spacing: 10) {
                    Image(icon).renderingMode(.template).resizable()
                        .foregroundStyle(tone)
                        .frame(width: 18, height: 18)
                        .frame(width: 20, height: 20)
                    title
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .allowsHitTesting(tapAction != nil)
            .accessibilityAddTraits(tapAction == nil ? .isStaticText : .isButton)
            .accessibilityIdentifier("travelUpdate-\(place)")
            if let action {
                TextLink(title: action.title, action: action.perform)
                    .accessibilityIdentifier("travelUpdateAction-\(place)")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, action == nil ? 0 : 12)
        .frame(minHeight: 44)
        .background(background, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showsAssistance) { BoardingAssistanceSheet() }
    }

    // MARK: Copy (Figma Flight, Journey details, Layover and Route variants)

    @ViewBuilder
    private var title: some View {
        switch condition {
        case let .gateChanged(from, to):
            HStack(spacing: 6) {
                Text("Gate changed").outfitText(14, .bold, AB.ticket)
                Spacer(minLength: 4)
                Text(from).outfitText(14, .bold, AB.secondary).strikethrough(color: AB.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(AB.chip, in: RoundedRectangle(cornerRadius: 6))
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(AB.ticket)
                Text(to).outfitText(14, .bold, AB.gateText)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(AB.gateYellow, in: RoundedRectangle(cornerRadius: 6))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gate changed from \(from) to \(to)")
        case let .returnNow(closesIn, _):
            Text(place == .flight ? "Time to return to Gate \(store.gate)" : "Gate \(store.gate) closes in \(closesIn) min")
                .outfitText(14, .semibold, tone)
        case let .boardingAtRisk(closesIn, walk):
            Text("Gate closes in \(closesIn) min, walk \(walk) min").outfitText(14, .semibold, tone)
        case let .arrivesAfterClosure(_, late):
            Text("Arrival \(late) min after closure").outfitText(14, .semibold, tone)
        case .airportTransfer:
            Text(transferTitle).outfitText(14, .semibold, tone)
        }
    }

    private var transferTitle: String {
        switch place {
        case .flight: "Change airports: \(store.transferArrivalName) → \(store.transferDepartureName)"
        case .details: "Next flight leaves from \(store.transferDepartureName)"
        case .layover, .route: "Transfer to \(store.transferDepartureName) comes first"
        }
    }

    private var icon: String {
        switch condition {
        case .gateChanged: "bannerBell"
        case .airportTransfer: "bannerTransfer"
        default: "bannerClock"
        }
    }

    private var tone: Color {
        switch condition {
        case .boardingAtRisk, .arrivesAfterClosure: AB.removeRed
        default: AB.amber
        }
    }

    private var background: Color {
        switch condition {
        case .gateChanged, .airportTransfer: AB.warningTint
        case .returnNow: AB.returnTint
        case .boardingAtRisk, .arrivesAfterClosure: AB.riskTint
        }
    }

    private var action: (title: String, perform: () -> Void)? {
        let route = ("Route", { store.openRoute(directToGate: true) })
        let call: (title: String, perform: () -> Void)
        if let contact = store.boardingContact, let url = contact.url {
            call = ("Call \(contact.name)", { openURL(url) })
        } else {
            call = ("Get help", { showsAssistance = true })
        }
        switch (condition, place) {
        case (.returnNow, .details), (.returnNow, .layover): return route
        case (.boardingAtRisk, .flight), (.boardingAtRisk, .route): return call
        case (.boardingAtRisk, _): return route
        case (.arrivesAfterClosure, _): return call
        default: return nil
        }
    }

    private var tapAction: (() -> Void)? {
        // Figma "Gate change strip": tapping it anywhere shows the gate change again.
        if case .gateChanged = condition { return { store.alertToPresent = .gateChange } }
        guard place == .flight else { return nil }
        if let kind = condition.alertKind { return { open(.alerts(kind)) } }
        if case .arrivesAfterClosure = condition { return { showsAssistance = true } }
        return nil
    }

    private func tap() { tapAction?() }
}

/// The AirBorder pop-up (Figma "Gate change alert", 1157:17460): a dimmed screen, a white card,
/// and two actions along the bottom. Used for gate changes and for asking to use the camera.
struct AirBorderPopup<Visual: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let message: String
    let id: String
    let secondary: (title: String, id: String, perform: () -> Void)
    let primary: (title: String, id: String, perform: () -> Void)
    @ViewBuilder let visual: Visual
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: secondary.perform)
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    Text(title).outfitText(17, .bold).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    visual
                    Text(message)
                        .outfitText(15, .regular, AB.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                Rectangle().fill(AB.border).frame(height: 1)
                HStack(spacing: 0) {
                    action(secondary.title, .regular, id: secondary.id, perform: secondary.perform)
                    Rectangle().fill(AB.border).frame(width: 1)
                    action(primary.title, .bold, id: primary.id, perform: primary.perform)
                }
                .frame(height: 52)
            }
            .frame(width: 300)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(shown || reduceMotion ? 1 : 0.95)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { withAnimation(.abOut) { shown = true } }
    }

    private func action(_ title: String, _ weight: OutfitWeight, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).outfitText(17, weight, AB.primary).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(id)
    }
}

/// Figma "Gate change alert" (1157:17460).
struct GateChangeAlert: View {
    @EnvironmentObject private var store: JourneyStore
    let dismiss: () -> Void

    var body: some View {
        let previousGate = store.feed?.previousGate ?? store.outbound.departureGate
        let walk = store.knownGateWalkMinutes(for: store.routeChoice)
        let direction = walk.map { "It’s a \($0) min walk." } ?? "Indoor directions aren’t available here."
        AirBorderPopup(
            title: "Gate changed",
            message: "\(store.outbound.number) now departs from Gate \(store.gate). \(direction)",
            id: "gateAlert",
            secondary: ("Dismiss", "alertDismiss", dismiss),
            primary: ("View route", "alertRoute", {
                store.acknowledge(.gateChange)
                dismiss()
                store.openRoute(directToGate: store.hasTimingSituation)
            })
        ) {
            HStack(spacing: 10) {
                gate(previousGate, old: true)
                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(AB.ticket)
                gate(store.gate, old: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gate \(previousGate) changed to \(store.gate)")
        }
        .onAppear {
            store.alertSeen(.gateChange)
            Haptics.warning()
        }
    }

    private func gate(_ gate: String, old: Bool) -> some View {
        VStack(spacing: 0) {
            Text("Gate").outfitText(12, .medium, old ? AB.secondary : AB.gateText)
            Text(gate).outfitText(old ? 22 : 30, .bold, old ? AB.secondary : AB.gateText)
                .strikethrough(old, color: AB.secondary)
        }
        .frame(minWidth: old ? 64 : 104, minHeight: 64)
        .padding(.horizontal, 6)
        .background(old ? AB.screen : AB.gateYellow, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Asks to use the camera for sign reading, before iOS's own permission prompt.
struct CameraPrompt: View {
    @EnvironmentObject private var store: JourneyStore

    var body: some View {
        AirBorderPopup(
            title: "Use the camera to read signs?",
            message: "Point your iPhone at an overhead sign and AirBorder checks you’re heading the right way. You can switch back to the map at any time.",
            id: "cameraPrompt",
            secondary: ("Dismiss", "cameraDismiss", { store.asksForCamera = false }),
            primary: ("Allow camera", "cameraAllow", {
                store.asksForCamera = false
                Task {
                    if await AVCaptureDevice.requestAccess(for: .video) { store.cameraAllowed += 1 }
                }
            })
        ) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(AB.gateText)
                .frame(width: 72, height: 64)
                .background(AB.gateYellow, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
        }
    }
}

/// Figma "Alerts" (858:10770 gate change, 858:10824 return now, 858:10878 boarding at risk) and their reminders.
struct AlertsView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let kind: AlertKind
    @State private var reminder = false
    @State private var showsAssistance = false

    var body: some View {
        let record = store.alerts[kind]
        VStack(alignment: .leading, spacing: 16) {
            BackButton { dismiss() }.offset(x: -9)
            Text("Alerts").outfitText(30, .bold).accessibilityAddTraits(.isHeader)
            Text(stamp(record)).outfitText(13, .regular, AB.muted)
            card
            HStack {
                Spacer()
                Button {
                    store.acknowledge(kind)
                    dismiss()
                    store.openRoute(directToGate: kind != .gateChange || store.hasTimingSituation)
                } label: {
                    HStack(spacing: 9) {
                        Image("icWalkWhite").resizable().frame(width: 21, height: 21)
                        Text("Route").outfitText(15, .semibold, .white)
                    }
                    .frame(width: 200, height: 52)
                    .background(AB.primary, in: Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("alertRoute")
                Spacer()
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsAssistance) { BoardingAssistanceSheet() }
        .onAppear {
            reminder = record?.isReminder(at: Date()) ?? false
            store.alertSeen(kind)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                pill(tag.text, tag.foreground, tag.background)
                if reminder { pill("Reminder", AB.ice, AB.ice.opacity(0.14)) }
            }
            Text(headline).outfitText(22, .bold, AB.ice)
            HStack(spacing: 8) {
                GateSign(gate: store.gate)
                Text("closes").outfitText(15, .regular, AB.ice.opacity(0.75))
                Text(store.outbound.gateCloses?.description ?? "–").outfitText(20, .semibold, AB.ice)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(AB.ice.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityElement(children: .combine)
            if let walkText {
                HStack(spacing: 6) {
                    Image("icWalkSmall").renderingMode(.template).resizable().foregroundStyle(AB.sky).frame(width: 18, height: 18)
                    Text(walkText).outfitText(14, .semibold, AB.sky)
                }
                .accessibilityElement(children: .combine)
            }
            TextLink(title: "Get help", color: AB.sky) {
                if let url = store.boardingContact?.url { openURL(url) } else { showsAssistance = true }
            }
            .accessibilityLabel(store.boardingContact.map { "Get help, call \($0.name)" } ?? "Get help")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.ticket, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("alertCard")
    }

    private func pill(_ text: String, _ foreground: Color, _ background: Color) -> some View {
        Text(text).outfitText(12, .semibold, foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }

    private var tag: (text: String, foreground: Color, background: Color) {
        switch kind {
        case .gateChange: ("Gate changed", AB.gateText, AB.gateYellow)
        case .returnNow: ("Return now", AB.gateText, AB.returnTag)
        case .boardingAtRisk: ("Boarding at risk", .white, AB.riskTag)
        }
    }

    private var headline: String {
        switch kind {
        case .gateChange: reminder ? "Gate changed to \(store.gate)" : "Gate \(store.feed?.previousGate ?? store.outbound.departureGate) → \(store.gate)"
        case .returnNow: "Time to return to Gate \(store.gate)"
        case .boardingAtRisk: "Boarding time is tight"
        }
    }

    private var walkText: String? {
        guard let walk = store.knownGateWalkMinutes(for: store.routeChoice) else { return nil }
        guard kind == .boardingAtRisk, let closes = store.outbound.gateCloses else { return "\(walk) min walk" }
        return "\(walk) min walk, \(closes - (store.now + walk)) min spare"
    }

    /// "15 Oct, 12:00": the flight date and when the situation began.
    private func stamp(_ record: AlertRecord?) -> String {
        "\(TripDate.format(store.outbound.date, "d MMM")), \((record?.issuedAt ?? store.now).description)"
    }
}

/// Figma "Boarding and rebooking" sheet (858:10204), titled Boarding assistance.
struct BoardingAssistanceSheet: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open

    var body: some View {
        let arrival = store.knownGateWalkMinutes(for: store.routeChoice).map { store.now + $0 }
        let closes = store.outbound.gateCloses
        let contact = store.boardingContact
        let gateName = store.gate.isEmpty ? "Gate" : "Gate \(store.gate)"
        let closure = closes.map { "\(gateName) closes \($0)" } ?? "Gate closing time unavailable"
        InfoSheet(
            title: "Boarding assistance",
            rows: [
                SheetRow(icon: "tileClock", label: arrival.map { "Arriving \($0)" } ?? "Arrival estimate unavailable", detail: closure),
                SheetRow(icon: "tileBell", label: "Ask about the next flight", detail: contact == nil ?
                         "Check your airline’s app or contact an airport agent." : "\(store.outbound.airline.name) can rebook \(store.outbound.number)"),
            ] + (store.isAirportTransfer || store.journey.presentation?.baggageTaggedThrough != true ? [] : [
                SheetRow(icon: "tileBag", label: "Bag tagged to \(store.outbound.to.code)", detail: store.extraBagDeclared ? "1 checked, 1 extra" : "1 checked"),
            ]),
            link: contact.map { ("Call \($0.name), \($0.hours)", "tel:\($0.phone)") },
            button: ("View journey details", { open(.journeyDetails) })
        )
    }
}

/// The Flight tab's "Your plan" area while a timing situation holds (Figma Return, Boarding at risk, Boarding assistance).
struct ScenarioPlanSection: View {
    @EnvironmentObject private var store: JourneyStore
    let condition: JourneyCondition

    var body: some View {
        switch condition {
        case let .returnNow(closesIn, walk):
            countdown(closesIn, color: AB.amber)
            routeButton(color: AB.amber)
            Text("\(walk) min walk\nLeave now to reach your gate in time.").outfitText(14, .regular, AB.navy)
                .accessibilityIdentifier("arrivalEstimate")
        case let .boardingAtRisk(closesIn, _):
            countdown(closesIn, color: AB.removeRed)
            routeButton(color: AB.removeRed)
        case let .arrivesAfterClosure(arrival, _):
            VStack(alignment: .leading, spacing: 8) {
                timeRow("Arrival", arrival.description)
                timeRow("Gate closes", store.outbound.gateCloses?.description ?? "–")
            }
            .accessibilityIdentifier("arrivalAfterClosure")
            TextLink(title: "Route") { store.openRoute(directToGate: true) }
        default:
            EmptyView()
        }
    }

    private func countdown(_ minutes: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(minutes) min").outfitText(20, .semibold, AB.ice)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(color, in: RoundedRectangle(cornerRadius: 8))
            Text("before").outfitText(22, .regular, color)
            GateSign(gate: store.gate, size: 18)
            Text("closes.").outfitText(22, .regular, color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(minutes) min before Gate \(store.gate) closes.")
        .accessibilityIdentifier("scenarioCountdown")
    }

    private func routeButton(color: Color) -> some View {
        Button {
            if let kind = condition.alertKind { store.acknowledge(kind) }
            store.openRoute(directToGate: true)
        } label: {
            HStack(spacing: 8) {
                Image("icWalkWhite").resizable().frame(width: 21, height: 21)
                Text("Route").outfitText(14, .semibold, .white)
            }
            .frame(width: 222, height: 47)
            .background(color, in: Capsule())
        }
        .buttonStyle(.pressable)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("routeButton")
    }

    private func timeRow(_ label: String, _ time: String) -> some View {
        HStack(spacing: 6) {
            Text(label).outfitText(22, .regular, AB.muted)
            Text(time).outfitText(20, .semibold, AB.ice)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(AB.ticket, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityElement(children: .combine)
    }
}
