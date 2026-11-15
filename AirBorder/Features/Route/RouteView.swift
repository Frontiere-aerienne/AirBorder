import AVFoundation
import SwiftUI

/// One route instruction (Figma "Map step", 1121:17357).
struct RouteStep: Equatable {
    enum Turn { case straight, left, right, stairs, lift, stop, gate }
    let distance: String
    let text: String
    let turn: Turn
    /// Header for this step: time left and the distance or boarding line under it.
    let remaining: String
    let remainingDetail: String
}

/// Figma route content per route choice (variable collection "Route choice", 1116:8282).
@MainActor
enum RouteSteps {
    static func steps(for choice: RouteChoice, store: JourneyStore) -> [RouteStep] {
        let gate = store.gate
        let board = "Board at \(SampleJourney.boarding)"
        let last = RouteStep(distance: "At Gate \(gate)", text: "Check \(store.outbound.number) on the gate screen", turn: .gate, remaining: "Arrived", remainingDetail: board)
        guard gate == SampleJourney.outbound.departureGate else {
            return [
                RouteStep(distance: "", text: "Follow the Gates 105–109 sign", turn: .straight, remaining: "\(store.gateWalkMinutes) min", remainingDetail: ""),
                RouteStep(distance: "", text: "Follow signs for 108–149", turn: .straight, remaining: "", remainingDetail: ""),
                RouteStep(distance: "At Gate \(gate)", text: "Gate \(gate)", turn: .gate, remaining: "Arrived", remainingDetail: board),
            ]
        }
        let cafeLeave = store.times(.cafe)?.leave.description ?? "16:28"
        let loungeLeave = store.times(.anaLounge)?.leave.description ?? "17:01"
        let step = RouteStep.init(distance:text:turn:remaining:remainingDetail:)
        switch choice.resolved(for: store.plan) {
        case .stepFree:
            return [step("260 m", "Follow the Gates 105–109 sign", .straight, "16 min", "600 m"),
                    step("15 m", "Turn right to the lift", .right, "10 min", "340 m"),
                    step("230 m", "Take the lift, then go straight", .lift, "9 min", "325 m"),
                    step("30 m", "Turn left at the Gate \(gate) sign", .left, "2 min", "30 m"), last]
        case .lessCrowded:
            return [step("40 m", "Keep right toward the windows", .right, "15 min", "700 m"),
                    step("10 m", "Turn left onto the outer concourse", .left, "14 min", "660 m"),
                    step("300 m", "Walk along the windows past Gates 101–104", .straight, "13 min", "650 m"),
                    step("50 m", "Turn left at the Gate \(gate) sign", .left, "3 min", "50 m"), last]
        case .viaStops where store.plan.contains(.cafe) && store.plan.contains(.anaLounge):
            return [step("150 m", "Follow the signs to Curacion Cafe", .straight, "14 min", ""),
                    step("Stop 1", "Stop at Curacion Cafe, leave by \(cafeLeave)", .stop, "9 min", ""),
                    step("60 m", "Take the lift to ANA LOUNGE, 4F", .lift, "9 min", ""),
                    step("250 m", "Leave the lounge by \(loungeLeave), follow the Gates 105–109 sign", .straight, "4 min", ""), last]
        case .viaStops where store.plan.contains(.cafe):
            return [step("150 m", "Follow the signs to Curacion Cafe", .straight, "13 min", ""),
                    step("Stop 1", "Stop at Curacion Cafe, leave by \(cafeLeave)", .stop, "8 min", ""),
                    step("300 m", "Continue past Gate 104", .straight, "8 min", ""),
                    step("30 m", "Turn left at the Gate \(gate) sign", .left, "1 min", ""), last]
        case .viaStops:
            return [step("120 m", "Follow the signs to the lift", .straight, "14 min", ""),
                    step("Stop 1", "Take the lift to ANA LOUNGE, 4F", .lift, "4 min", ""),
                    step("4F to 3F", "Leave the lounge by \(loungeLeave), take the lift down", .lift, "4 min", ""),
                    step("120 m", "Follow the Gates 105–109 sign", .straight, "2 min", ""), last]
        case .direct:
            return [step("300 m", "Follow the Gates 105–109 sign", .straight, "12 min", "570 m"),
                    step("40 m", "Take the stairs at the junction", .stairs, "6 min", "270 m"),
                    step("200 m", "Go straight past Gate 104", .straight, "5 min", "230 m"),
                    step("30 m", "Turn left at the Gate \(gate) sign", .left, "1 min", "30 m"), last]
        }
    }

    static func transfer() -> [RouteStep] {
        TransferRouteContent.steps.enumerated().map { index, text in
            RouteStep(distance: "", text: text, turn: index == 2 ? .stop : .straight, remaining: index == 0 ? "\(NaritaTransfer.busMinutes) min" : "", remainingDetail: "")
        }
    }
}

/// Figma "Route" (858:10477): Map/Camera switch and one white route card.
struct RouteView: View {
    @EnvironmentObject private var store: JourneyStore
    @State private var mode: Mode = .map
    @State private var showsMapInfo = false
    @State private var cameraCovers = false

    enum Mode { case map, camera }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !(mode == .camera && cameraCovers) {
                    Text(store.isAirportTransfer ? "Route to Narita" : "Route to Gate \(store.gate)").outfitText(30, .bold).tracking(-1.1)
                        .accessibilityAddTraits(.isHeader)
                    modeSwitch
                    if let condition = store.primaryCondition, !store.isAirportTransfer {
                        TravelUpdateBanner(condition: condition, place: .route)
                    }
                }
                if mode == .camera {
                    CameraGuide(sign: sign, exit: { mode = .map }, covers: $cameraCovers) { routeCard(map: false) }
                } else {
                    routeCard(map: true)
                    if store.isAirportTransfer {
                        TransferRouteContent().padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 54)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The sign the camera looks for at the current step.
    private var sign: SignTarget {
        if store.isAirportTransfer { return .bus }
        if store.gate != SampleJourney.outbound.departureGate && store.routeStep >= 2 { return .gates108to149 }
        return .gates105to109
    }

    private func routeCard(map: Bool) -> some View {
        let steps = store.isAirportTransfer ? RouteSteps.transfer() : RouteSteps.steps(for: store.routeChoice, store: store)
        return RouteCard(step: $store.routeStep, steps: steps, showsChoice: !store.isAirportTransfer) {
            if map && !store.isAirportTransfer { concourse }
        } end: {
            store.routeStep = 1
            mode = .map
            store.tab = .flight
            guard !store.isAirportTransfer else { return }
            if store.alerts[.gateChange] != nil { store.acknowledge(.gateChange) }
            store.showToast(ToastMessage(text: "Arrived, Gate \(store.gate), \(store.outbound.number), boarding \(SampleJourney.boarding)."))
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 4) {
            segment("Map", .map)
            segment("Camera", .camera)
        }
        .padding(4)
        .background(.white.opacity(0.7), in: Capsule())
    }

    private func segment(_ title: String, _ value: Mode) -> some View {
        let selected = mode == value
        return Button { mode = value } label: {
            Text(title).outfitText(14, .semibold, selected ? .white : AB.primary)
                .frame(maxWidth: .infinity, minHeight: 47)
                .background(selected ? AB.primary : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("mode-\(title.lowercased())")
    }

    // ponytail: one terminal map with a step marker, not Figma's per-step vector maps.
    private var concourse: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .topLeading) {
                Image("concourseFrame").resizable().frame(width: 320, height: 46)
                Text(store.gate).outfitText(12, .bold, AB.ticket).offset(x: 140, y: -12)
                Image("concourseCurrent").resizable().frame(width: 18, height: 18)
                    .offset(markerOffset)
                    .animation(.easeInOut, value: store.routeStep)
            }
            .frame(width: 320, height: 46, alignment: .topLeading)
            HStack {
                Text("105–109").outfitText(12, .bold, AB.ticket)
                Spacer()
                Text("108–149").outfitText(12, .bold, AB.ticket)
            }
            .frame(width: 320)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { showsMapInfo = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Terminal map, you are at step \(store.routeStep)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("About this map")
        .accessibilityIdentifier("routeSummary")
        .sheet(isPresented: $showsMapInfo) { Sheets.aboutMap(walk: store.gateWalkMinutes) }
    }

    private var markerOffset: CGSize {
        let count = max(RouteSteps.steps(for: store.routeChoice, store: store).count - 1, 1)
        let progress = CGFloat(store.routeStep - 1) / CGFloat(count)
        return CGSize(width: 8 + progress * 124, height: 26)
    }
}

/// Figma route card: time left and route choice, progress, the current instruction, map, Back / Next / End.
struct RouteCard<Map: View>: View {
    @EnvironmentObject private var store: JourneyStore
    @Binding var step: Int
    let steps: [RouteStep]
    var showsChoice = true
    @ViewBuilder let map: Map
    let end: () -> Void
    @State private var choosing = false

    var body: some View {
        let index = min(max(step, 1), steps.count) - 1
        let current = steps[index]
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(current.remaining).outfitText(20, .semibold)
                Text(current.remainingDetail).outfitText(15, .regular, AB.secondary)
                Spacer()
                if showsChoice { choiceButton }
            }
            .frame(minHeight: 36)
            .zIndex(1)
            HStack(spacing: 4) {
                ForEach(steps.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(i <= index ? AB.ticket : AB.screen).frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(index + 1) of \(steps.count)")
            .accessibilityIdentifier("routeProgress")
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: Self.symbol(current.turn))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AB.ice)
                    .frame(width: 52, height: 52)
                    .background(AB.ticket, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if !current.distance.isEmpty {
                        Text(current.distance).outfitText(15, .semibold, AB.secondary)
                    }
                    Text(current.text).outfitText(22, .bold, AB.ticket)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("routeInstruction")
                }
            }
            map
            HStack(spacing: 8) {
                if index > 0 {
                    button("Back", fill: AB.screen, text: AB.ticket, id: "previousStep") { step = index }
                }
                if index < steps.count - 1 {
                    button("Next", fill: AB.ticket, text: .white, arrow: true, id: "nextStep") { step = index + 2 }
                } else {
                    button("End", fill: AB.primary, text: .white, id: "endRoute", action: end)
                }
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topTrailing) {
            if choosing { menu.padding(.top, 62).padding(.trailing, 12) }
        }
        .animation(.easeOut(duration: 0.15), value: choosing)
    }

    private var choiceButton: some View {
        Button { choosing.toggle() } label: {
            HStack(spacing: 8) {
                Text(store.routeChoice.resolved(for: store.plan).menuTitle).outfitText(15, .semibold)
                Image(systemName: choosing ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AB.navy)
                    .frame(width: 26, height: 26)
                    .background(.white, in: Circle())
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .frame(height: 36)
            .background(AB.screen, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Route, \(store.routeChoice.resolved(for: store.plan).menuTitle)")
        .accessibilityHint("Choose another route")
        .accessibilityIdentifier("routeChoice")
    }

    private var menu: some View {
        let choices = RouteChoice.allCases.filter { $0 != .viaStops || RouteChoice.viaStops.resolved(for: store.plan) == .viaStops }
        return VStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.element) { i, choice in
                if i > 0 { Rectangle().fill(Color(hex: 0xDFE7EA)).frame(height: 1) }
                Button {
                    store.routeChoice = choice
                    step = 1
                    choosing = false
                } label: {
                    HStack(spacing: 12) {
                        let selected = store.routeChoice.resolved(for: store.plan) == choice
                        Circle().strokeBorder(selected ? AB.primary : Color(hex: 0xB9C8CF), lineWidth: 1.5)
                            .overlay { if selected { Circle().fill(AB.primary).padding(5) } }
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(choice.title).outfitText(15, .semibold)
                                if choice == .direct {
                                    Text("Fastest").outfitText(11, .medium, AB.primary)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(AB.screen, in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            Text(choice.detail).outfitText(13, .regular, AB.secondary)
                        }
                        Spacer()
                        Text("\(choice.averageMinutes) min").outfitText(15, .semibold)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.routeChoice.resolved(for: store.plan) == choice ? .isSelected : [])
                .accessibilityIdentifier("use-\(choice.rawValue)")
            }
        }
        .padding(.horizontal, 15)
        .frame(width: 320)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AB.screen, lineWidth: 1))
        .shadow(color: AB.navy.opacity(0.14), radius: 12, y: 6)
    }

    private func button(_ title: String, fill: Color, text: Color, arrow: Bool = false, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).outfitText(16, .semibold, text)
                if arrow { Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(text) }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    static func symbol(_ turn: RouteStep.Turn) -> String {
        switch turn {
        case .straight: "arrow.up"
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .stairs: "figure.stairs"
        case .lift: "arrow.up.arrow.down"
        case .stop: "mappin.and.ellipse"
        case .gate: "airplane.departure"
        }
    }
}
