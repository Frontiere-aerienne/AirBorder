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
    /// Where this step sits on the route map, from 0 (where you are) to 1 (the gate).
    var position: CGFloat = 0
}

/// Figma route content per route choice (variable collection "Route choice", 1116:8282).
/// Every route passes the stops in the plan, in arrive order, then takes its own way to the gate.
@MainActor
enum RouteSteps {
    static func steps(for choice: RouteChoice, store: JourneyStore) -> [RouteStep] {
        let gate = store.gate
        let board = "Board at \(SampleJourney.boarding)"
        let last = RouteStep(distance: "At Gate \(gate)", text: "Check \(store.outbound.number) on the gate screen", turn: .gate, remaining: "Arrived", remainingDetail: board, position: 1)
        guard gate == SampleJourney.outbound.departureGate else {
            return spread([
                RouteStep(distance: "", text: "Follow the Gates 105–109 sign", turn: .straight, remaining: "\(store.gateWalkMinutes) min", remainingDetail: ""),
                RouteStep(distance: "", text: "Follow signs for 108–149", turn: .straight, remaining: "", remainingDetail: ""),
                RouteStep(distance: "At Gate \(gate)", text: "Gate \(gate)", turn: .gate, remaining: "Arrived", remainingDetail: board),
            ], from: 0)
        }
        let toGate = gateStretch(choice, gate: gate)
        let stops = stopsInOrder(store)
        guard !stops.isEmpty else { return spread(toGate, from: 0) + [last] }

        let places = [PlaceID.start] + stops.map(\.id)
        let legs = zip(places, places.dropFirst()).map { store.walkMinutes($0, $1) }
        let routeMinutes = store.gateWalkMinutes(for: choice)
        let left = { (leg: Int) in "\(legs[leg...].reduce(0, +) + routeMinutes) min" }
        var steps: [RouteStep] = []
        for (i, stop) in stops.enumerated() {
            let at = mapPosition(of: i, count: stops.count)
            let before = i == 0 ? 0 : mapPosition(of: i - 1, count: stops.count)
            if places[i] == .anaLounge { steps.append(liftDown(left(i), at: before)) }
            let byLift = stop.id == .anaLounge
            steps.append(RouteStep(distance: legs[i] > 0 ? "\(legs[i]) min walk" : "Nearby",
                                   text: byLift ? "Take the lift to ANA LOUNGE, 4F" : "Follow the signs to \(stop.name)",
                                   turn: byLift ? .lift : .straight, remaining: left(i), remainingDetail: "", position: (before + at) / 2))
            let leave = store.times(stop.id)?.leave.description ?? ""
            steps.append(RouteStep(distance: "Stop \(i + 1)", text: "Stop at \(stop.name), leave by \(leave)", turn: .stop,
                                   remaining: "\(routeMinutes + (legs.dropFirst(i + 1).reduce(0, +))) min", remainingDetail: "", position: at))
        }
        let lastStop = mapPosition(of: stops.count - 1, count: stops.count)
        if stops.last?.id == .anaLounge { steps.append(liftDown("\(routeMinutes) min", at: lastStop)) }
        // Distances are measured from the terminal entrance, so they only show on a route without stops.
        let stretch = toGate.map { RouteStep(distance: $0.distance, text: $0.text, turn: $0.turn, remaining: $0.remaining, remainingDetail: "") }
        return steps + spread(stretch, from: lastStop) + [last]
    }

    /// Plan stops in the order the traveller will reach them.
    static func stopsInOrder(_ store: JourneyStore) -> [PlanStop] {
        store.plan.stops.sorted { StopTimes.arrive($0) < StopTimes.arrive($1) }
    }

    /// Stops sit evenly along the map between where you are (0) and the gate (1).
    static func mapPosition(of index: Int, count: Int) -> CGFloat {
        CGFloat(index + 1) / CGFloat(count + 1)
    }

    /// Steps after `start` share the rest of the map evenly; the gate step is added at 1.
    private static func spread(_ steps: [RouteStep], from start: CGFloat) -> [RouteStep] {
        steps.enumerated().map { i, step in
            var step = step
            step.position = start + (1 - start) * CGFloat(i + (start == 0 ? 0 : 1)) / CGFloat(steps.count + (start == 0 ? 0 : 1))
            return step
        }
    }

    /// ANA LOUNGE is on 4F; leaving it starts with the lift back down.
    private static func liftDown(_ remaining: String, at position: CGFloat) -> RouteStep {
        RouteStep(distance: "4F to 3F", text: "Take the lift down to 3F", turn: .lift, remaining: remaining, remainingDetail: "", position: position)
    }

    /// The Figma steps from the terminal to the gate for each route choice.
    private static func gateStretch(_ choice: RouteChoice, gate: String) -> [RouteStep] {
        let step = { (distance: String, text: String, turn: RouteStep.Turn, remaining: String, detail: String) in
            RouteStep(distance: distance, text: text, turn: turn, remaining: remaining, remainingDetail: detail)
        }
        switch choice {
        case .stepFree:
            return [step("260 m", "Follow the Gates 105–109 sign", .straight, "16 min", "600 m"),
                    step("15 m", "Turn right to the lift", .right, "10 min", "340 m"),
                    step("230 m", "Take the lift, then go straight", .lift, "9 min", "325 m"),
                    step("30 m", "Turn left at the Gate \(gate) sign", .left, "2 min", "30 m")]
        case .lessCrowded:
            return [step("40 m", "Keep right toward the windows", .right, "15 min", "700 m"),
                    step("10 m", "Turn left onto the outer concourse", .left, "14 min", "660 m"),
                    step("300 m", "Walk along the windows past Gates 101–104", .straight, "13 min", "650 m"),
                    step("50 m", "Turn left at the Gate \(gate) sign", .left, "3 min", "50 m")]
        case .direct:
            return [step("300 m", "Follow the Gates 105–109 sign", .straight, "12 min", "570 m"),
                    step("40 m", "Take the stairs at the junction", .stairs, "6 min", "270 m"),
                    step("200 m", "Go straight past Gate 104", .straight, "5 min", "230 m"),
                    step("30 m", "Turn left at the Gate \(gate) sign", .left, "1 min", "30 m")]
        }
    }

    static func transfer() -> [RouteStep] {
        spread(TransferRouteContent.steps.enumerated().map { index, text in
            RouteStep(distance: "", text: text, turn: index == 2 ? .stop : .straight, remaining: index == 0 ? "\(NaritaTransfer.busMinutes) min" : "", remainingDetail: "")
        }, from: 0)
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
            Haptics.success()
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
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("mode-\(title.lowercased())")
    }

    private var concourse: some View {
        let steps = RouteSteps.steps(for: store.routeChoice, store: store)
        let index = min(max(store.routeStep, 1), steps.count) - 1
        return RouteMap(stops: RouteSteps.stopsInOrder(store), gate: store.gate, position: steps[index].position)
            .contentShape(Rectangle())
            .onTapGesture { showsMapInfo = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("About this map")
            .accessibilityIdentifier("routeSummary")
            .sheet(isPresented: $showsMapInfo) { Sheets.aboutMap(walk: store.gateWalkMinutes) }
    }
}

/// Route map: where you are, a pin for each stop in your plan and the gate, with a marker that moves per step.
struct RouteMap: View {
    let stops: [PlanStop]
    let gate: String
    let position: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 22
            let width = proxy.size.width - inset * 2
            let x = { (p: CGFloat) in inset + width * p }
            let trackY: CGFloat = 30
            ZStack(alignment: .topLeading) {
                Capsule().fill(AB.screen).frame(width: width, height: 6).offset(x: inset, y: trackY - 3)
                Capsule().fill(AB.ticket).frame(width: max(width * position, 6), height: 6).offset(x: inset, y: trackY - 3)
                pin(icon: nil, label: "Start", color: AB.ticket, filled: false).position(x: x(0), y: trackY + 14)
                ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
                    let at = RouteSteps.mapPosition(of: i, count: stops.count)
                    pin(icon: Self.icon(stop.id), label: Self.label(stop.id), color: PlanStripCard.color(stop.id), filled: position >= at)
                        .position(x: x(at), y: trackY + 14)
                }
                VStack(spacing: 2) {
                    Text(gate).outfitText(13, .bold, AB.gateText)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(AB.gateYellow, in: RoundedRectangle(cornerRadius: 6))
                    Text("Gate").outfitText(13, .semibold, AB.secondary)
                }
                .position(x: x(1), y: trackY + 14)
                Circle().fill(AB.primary)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .frame(width: 20, height: 20)
                    .shadow(color: AB.primary.opacity(0.4), radius: 6)
                    .position(x: x(position), y: trackY)
            }
        }
        .frame(height: 74)
        .animation(.spring(duration: 0.45, bounce: 0.15), value: position)
        .animation(.abOut, value: stops.map(\.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stops.isEmpty ? "Route map to Gate \(gate)" : "Route map: \(stops.map(\.name).joined(separator: ", ")), then Gate \(gate)")
    }

    private func pin(icon: String?, label: String, color: Color, filled: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(filled ? color : .white).overlay(Circle().strokeBorder(color, lineWidth: 2))
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(filled ? (color == AB.sky ? AB.ticket : .white) : color)
                }
            }
            .frame(width: icon == nil ? 14 : 26, height: icon == nil ? 14 : 26)
            .offset(y: icon == nil ? -14 : -14)
            Text(label).outfitText(13, .semibold, AB.secondary).fixedSize().offset(y: -10)
        }
    }

    static func icon(_ id: PlaceID) -> String {
        id == .cafe ? "cup.and.saucer.fill" : "sofa.fill"
    }

    static func label(_ id: PlaceID) -> String {
        switch id {
        case .cafe: "Café"
        case .anaLounge: "LOUNGE"
        default: "SKY"
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let index = min(max(step, 1), steps.count) - 1
        let current = steps[index]
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(current.remaining).outfitText(20, .semibold).contentTransition(.numericText())
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
                    .contentTransition(.symbolEffect(.replace))
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
                .id(index)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            }
            map
            HStack(spacing: 8) {
                if index > 0 {
                    button("Back", fill: AB.screen, text: AB.ticket, id: "previousStep") { go(to: index) }
                }
                if index < steps.count - 1 {
                    button("Next", fill: AB.ticket, text: .white, arrow: true, id: "nextStep") { go(to: index + 2) }
                } else {
                    button("End", fill: AB.primary, text: .white, id: "endRoute", action: end)
                }
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topTrailing) {
            if choosing {
                menu.padding(.top, 62).padding(.trailing, 12)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(.abOut, value: choosing)
    }

    private func go(to newStep: Int) {
        Haptics.tick()
        withAnimation(.abOut) { step = newStep }
    }

    private var choiceButton: some View {
        Button { choosing.toggle() } label: {
            HStack(spacing: 8) {
                Text(store.routeChoice.menuTitle).outfitText(15, .semibold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(choosing ? 180 : 0))
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
        .buttonStyle(.pressable)
        .accessibilityLabel("Route, \(store.routeChoice.menuTitle)")
        .accessibilityHint("Choose another route")
        .accessibilityIdentifier("routeChoice")
    }

    private var menu: some View {
        let choices = RouteChoice.allCases
        return VStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.element) { i, choice in
                if i > 0 { Rectangle().fill(Color(hex: 0xDFE7EA)).frame(height: 1) }
                Button {
                    Haptics.tick()
                    withAnimation(.abOut) {
                        store.routeChoice = choice
                        step = 1
                        choosing = false
                    }
                } label: {
                    HStack(spacing: 12) {
                        let selected = store.routeChoice == choice
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
                .buttonStyle(.pressable)
                .accessibilityAddTraits(store.routeChoice == choice ? .isSelected : [])
                .accessibilityIdentifier("use-\(choice.rawValue)")
                .staggered(i)
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
        .buttonStyle(.pressable)
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
