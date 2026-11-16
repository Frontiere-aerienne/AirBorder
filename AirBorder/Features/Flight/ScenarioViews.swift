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

/// ANA reservations and boarding help, as on the Figma alerts and Boarding assistance sheet.
enum ANAHelp {
    static let phone = "+81366260648"
    static let hours = "07:00–19:00"
    static var url: URL? { URL(string: "tel:\(phone)") }
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
        case .flight: "Change airports: Haneda → Narita"
        case .details: "Next flight leaves from Narita"
        case .layover, .route: "Transfer to Narita comes first"
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
        let route = ("Route", { store.tab = .route })
        let call = ("Call ANA", { if let url = ANAHelp.url { openURL(url) } })
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
        if let kind = condition.alertKind { return { store.alertToPresent = kind } }
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
                // Just a title and a visual; the full explanation is read by VoiceOver.
                VStack(spacing: 16) {
                    Text(title).outfitText(18, .bold).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHint(message)
                    visual
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
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
        AirBorderPopup(
            title: "Gate changed",
            message: "\(store.outbound.number) now departs from Gate \(store.gate). It’s a \(store.gateWalkMinutes) min walk.",
            id: "gateAlert",
            secondary: ("Dismiss", "alertDismiss", dismiss),
            primary: ("View route", "alertRoute", {
                store.acknowledge(.gateChange)
                store.routeStep = 1
                dismiss()
                store.tab = .route
            })
        ) {
            HStack(spacing: 10) {
                gate(store.outbound.departureGate, old: true)
                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(AB.ticket)
                gate(store.gate, old: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gate \(store.outbound.departureGate) changed to \(store.gate)")
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

/// "Won't fit" warning before adding a stop (Figma "Sit-down warning popup").
struct FitPrompt: View {
    @EnvironmentObject private var store: JourneyStore
    let warning: FitWarning

    var body: some View {
        AirBorderPopup(
            title: warning.need != nil ? "This meal may not fit" : "That's a lot of stops",
            message: warning.message,
            id: "fitPrompt",
            secondary: ("Cancel", "fitCancel", { store.fitPrompt = nil }),
            primary: ("Add anyway", "fitAdd", {
                store.fitPrompt = nil
                Haptics.tap()
                withAnimation(.abOut) { store.add(warning.stop) }
            })
        ) {
            HStack(spacing: 10) {
                if let need = warning.need, let free = warning.free {
                    box("Meal", "~\(need) min", AB.alert, AB.alertBackground)
                    Text(">").outfitText(18, .bold, AB.ticket)
                    box("Free", "~\(free) min", AB.ticket, AB.screen)
                } else if let stops = warning.stops {
                    box("Stops", "\(stops)", AB.alert, AB.alertBackground)
                    Text(">").outfitText(18, .bold, AB.ticket)
                    box("Safer", "2–3", AB.ticket, AB.screen)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func box(_ top: String, _ value: String, _ color: Color, _ fill: Color) -> some View {
        VStack(spacing: 0) {
            Text(top).outfitText(12, .medium, color)
            Text(value).outfitText(24, .bold, color).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(fill, in: RoundedRectangle(cornerRadius: 12))
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

/// Head back now / Boarding is tight as an AirBorder pop-up (no separate Alerts page).
struct SituationAlert: View {
    @EnvironmentObject private var store: JourneyStore
    let kind: AlertKind
    let dismiss: () -> Void

    var body: some View {
        let numbers = self.numbers
        AirBorderPopup(
            title: kind == .boardingAtRisk ? "Boarding is tight" : "Head back now",
            message: "Gate \(store.gate) closes in \(numbers.left) min and the walk takes \(numbers.walk) min.",
            id: "situationAlert",
            secondary: ("Dismiss", "situationDismiss", dismiss),
            primary: ("View route", "situationRoute", {
                store.acknowledge(kind)
                dismiss()
                store.tab = .route
            })
        ) {
            HStack(spacing: 10) {
                box("Walk", "\(numbers.walk) min", AB.ticket, AB.screen)
                Text(kind == .boardingAtRisk ? "≈" : "<").outfitText(18, .bold, AB.ticket)
                box("Left", "\(numbers.left) min", kind == .boardingAtRisk ? AB.alert : AB.amber,
                    kind == .boardingAtRisk ? AB.alertBackground : AB.warningTint)
            }
            .accessibilityHidden(true)
        }
        .onAppear {
            store.alertSeen(kind)
            Haptics.warning()
        }
    }

    private var numbers: (walk: Int, left: Int) {
        for condition in store.conditions {
            switch condition {
            case let .returnNow(closesIn, walk) where kind == .returnNow: return (walk, closesIn)
            case let .boardingAtRisk(closesIn, walk) where kind == .boardingAtRisk: return (walk, closesIn)
            default: continue
            }
        }
        return (store.gateWalkMinutes, max((store.outbound.gateCloses ?? SampleJourney.gateArrivalTarget) - store.now, 0))
    }

    private func box(_ top: String, _ value: String, _ color: Color, _ fill: Color) -> some View {
        VStack(spacing: 0) {
            Text(top).outfitText(12, .medium, color)
            Text(value).outfitText(24, .bold, color).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(fill, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Figma "Boarding and rebooking" sheet (858:10204), titled Boarding assistance.
struct BoardingAssistanceSheet: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open

    var body: some View {
        let arrival = store.now + store.gateWalkMinutes
        let closes = store.outbound.gateCloses?.description ?? "–"
        InfoSheet(
            title: "Boarding assistance",
            rows: [
                SheetRow(icon: "tileClock", label: "Arriving \(arrival)", detail: "Gate \(store.gate) closes \(closes)"),
                SheetRow(icon: "tileBell", label: "Ask about the next flight", detail: "ANA can rebook \(store.outbound.number)"),
                SheetRow(icon: "tileBag", label: "Bag tagged to \(store.outbound.to.code)", detail: store.extraBagDeclared ? "1 checked, 1 extra" : "1 checked"),
            ],
            link: ("Call ANA, \(ANAHelp.hours)", "tel:\(ANAHelp.phone)"),
            button: ("View journey details", { open(.journeyDetails) })
        )
    }
}

/// The Flight tab's "Your plan" area while a timing situation holds (Figma Return, Boarding at risk, Boarding assistance).
/// A taller warning strip above the ticket for timing situations: what's happening, one line of numbers,
/// and the one action that matters (Route, or Call ANA when the gate will have closed).
struct SituationStrip: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.openURL) private var openURL
    let condition: JourneyCondition

    var body: some View {
        let content = self.content
        HStack(spacing: 12) {
            Image(systemName: content.late ? "exclamationmark.circle.fill" : (store.isAirportTransfer ? "bus.fill" : "clock.fill"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(content.tint)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.75), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title).outfitText(18, .bold, content.tint)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(content.title). \(content.spoken)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("travelUpdate-flight")
                Text(content.detail).outfitText(14, .regular, AB.ticket)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(content.countdownLabel ?? content.detail)
                    .accessibilityIdentifier(content.countdownLabel == nil ? "situationDetail" : "scenarioCountdown")
            }
            Spacer(minLength: 0)
            Button(action: content.late ? callANA : route) {
                HStack(spacing: 7) {
                    Image(systemName: content.late ? "phone.fill" : "figure.walk").font(.system(size: 14, weight: .bold))
                    Text(content.late ? "Call ANA" : "Route").outfitText(14, .semibold, .white)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(content.tint, in: Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(content.late ? "Call ANA" : "Route")
            .accessibilityIdentifier("travelUpdateAction-flight")
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .background(content.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(content.tint.opacity(0.25), lineWidth: 1))
    }

    private var content: (title: String, detail: String, spoken: String, countdownLabel: String?, tint: Color, background: Color, late: Bool) {
        let gate = store.gate
        switch condition {
        case let .returnNow(closesIn, walk):
            return ("Head back now", "\(walk) min walk, \(closesIn) min left", "Time to return to Gate \(gate)",
                    "\(closesIn) min before Gate \(gate) closes.", AB.amber, AB.warningTint, false)
        case let .boardingAtRisk(closesIn, walk):
            return ("Boarding is tight", "\(walk) min walk, \(closesIn) min left", "Gate closes in \(closesIn) min, walk \(walk) min",
                    "\(closesIn) min before Gate \(gate) closes.", AB.removeRed, AB.riskTint, false)
        case let .arrivesAfterClosure(arrival, late):
            return ("Arriving too late", "Arriving \(arrival), closes \(store.outbound.gateCloses?.description ?? "–")",
                    "Arrival \(late) min after closure", nil, AB.removeRed, AB.riskTint, true)
        case .airportTransfer:
            return ("Changing airports", "Haneda → Narita by airport bus", "Change airports: Haneda → Narita",
                    nil, AB.amber, AB.warningTint, false)
        default:
            return ("", "", "", nil, AB.amber, AB.warningTint, false)
        }
    }

    private func tap() {
        if let kind = condition.alertKind { store.alertToPresent = kind }
    }

    private func route() {
        if let kind = condition.alertKind { store.acknowledge(kind) }
        Haptics.tick()
        store.tab = .route
    }

    private func callANA() { if let url = ANAHelp.url { openURL(url) } }
}
