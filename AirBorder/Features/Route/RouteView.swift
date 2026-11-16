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
    /// Where this step starts on the route map: an index into the map route's points.
    var position: CGFloat = 0
}

/// Route steps for each route choice, generated from the walk drawn on the Terminal 3 map:
/// one step per maneuver, plus "Stop at …" for each stop in the plan, in arrive order.
@MainActor
enum RouteSteps {
    /// Map units to metres, so the direct route measures the Figma 570 m.
    static let metresPerUnit: CGFloat = 570 / RouteMap.length(of: RouteMap.route(through: [], choice: .direct).nodes)

    static func steps(for choice: RouteChoice, store: JourneyStore) -> [RouteStep] {
        let gate = store.gate
        let board = "Board at \(SampleJourney.boarding)"
        let timed = store.schedule(for: choice)
        let stops = timed.stops.map(\.stop)
        let route = RouteMap.route(through: stops.map { RouteMap.node(for: $0.id) }, choice: choice)
        let nodes = route.nodes
        let last = RouteStep(distance: "At Gate \(gate)", text: "Check \(store.outbound.number) on the gate screen", turn: .gate,
                             remaining: "Arrived", remainingDetail: board, position: CGFloat(nodes.count - 1))
        let stopAt = Dictionary(uniqueKeysWithValues: zip(route.stopIndices, stops))
        let edges = zip(nodes, nodes.dropFirst()).map { RouteMap.edge($0, $1) }
        let metres = { (from: Int) in RouteMap.length(of: Array(nodes[from...])) * metresPerUnit }
        let ends = route.stopIndices + [nodes.count - 1]
        let durations = timed.stops.map(\.walkFromPrevious) + [timed.walkToGate]
        // Use the schematic only to apportion the time within each already timed leg.
        let minutes = { (from: Int) in
            guard let leg = ends.firstIndex(where: { $0 > from }) else { return 0 }
            let start = leg == 0 ? 0 : ends[leg - 1]
            let end = ends[leg]
            let legLength = RouteMap.length(of: Array(nodes[start...end]))
            let remaining = RouteMap.length(of: Array(nodes[from...end]))
            let current = legLength > 0 ? Int((Double(durations[leg]) * Double(remaining / legLength)).rounded(.up)) : 0
            return current + durations.dropFirst(leg + 1).reduce(0, +)
        }
        var steps: [RouteStep] = []
        var group: [Int] = [] // edge indices walked as one step

        /// The next stop after edge `i`, so the first step of each leg can point to it.
        let nextStop = { (i: Int) in stopAt.keys.filter { $0 > i }.min().flatMap { stopAt[$0] } }
        var legStarts = true

        func flush(into stop: PlanStop? = nil) {
            guard let first = group.first else { return }
            let a = nodes[first], b = nodes[first + 1]
            defer { legStarts = stop != nil }
            let length = group.map { RouteMap.length(of: [nodes[$0], nodes[$0 + 1]]) }.reduce(0, +) * metresPerUnit
            let (text, turn): (String, RouteStep.Turn) = {
                if let stop {
                    if stop.id.floor == "4F" { return ("Take the lift to \(stop.name), 4F", .lift) }
                    return legStarts ? ("Follow the signs to \(stop.name)", .straight) : ("Turn into \(stop.name)", .right)
                }
                if a == .lounge || a == .sushi { return ("Take the lift down to 3F", .lift) }
                let (text, turn) = phrase(a, b, gate: gate)
                if legStarts, turn != .stairs, turn != .lift, let target = nextStop(first) {
                    return ("Follow the signs to \(target.name)", .straight)
                }
                // Just came down from the lounge: no second lift.
                if a == .lift, b == .southLink, steps.last?.text == "Take the lift down to 3F" { return ("Go straight along the level corridor", .straight) }
                return (text, turn)
            }()
            let distance = a == .lounge || a == .sushi ? "4F to 3F" : "\(Int((length / 10).rounded()) * 10) m"
            steps.append(RouteStep(distance: distance, text: text, turn: turn, remaining: "\(minutes(first)) min",
                                   remainingDetail: "\(Int((metres(first) / 10).rounded()) * 10) m", position: CGFloat(first)))
            group = []
        }

        for (i, edge) in edges.enumerated() {
            if let stop = stopAt[i] {
                let leave = timed.stops.first { $0.stop.id == stop.id }?.end.description ?? ""
                steps.append(RouteStep(distance: "Stop \(steps.filter { $0.turn == .stop }.count + 1)", text: "Stop at \(stop.name), leave by \(leave)",
                                       turn: .stop, remaining: "Leave by \(leave)", remainingDetail: "\(minutes(i)) min walk left",
                                       position: CGFloat(i)))
            }
            let leavingRoom = stopAt[i] != nil
            if leavingRoom && (nodes[i] == .lounge || nodes[i] == .sushi) {
                group = [i]
                flush()
                legStarts = true
                continue
            }
            if let open = group.last {
                let previous = edges[open]
                let onlyLeavingDoor = group.count == 1 && stopAt[group[0]] != nil
                let sameWay = RouteMap.heading(nodes[open], nodes[open + 1]) == RouteMap.heading(nodes[i], nodes[i + 1])
                let flows = previous.kind != .stairs && edge.kind != .stairs && previous.kind != .lift && edge.kind != .lift
                if !(edge.kind == .door || onlyLeavingDoor || (sameWay && flows)) { flush() }
            }
            group.append(i)
            if let stop = stopAt[i + 1] { flush(into: stop) }
        }
        flush()
        return steps + [last]
    }

    /// Plan stops in the order the traveller will reach them.
    static func stopsInOrder(_ store: JourneyStore) -> [PlanStop] {
        store.schedule.stops.map(\.stop)
    }

    /// What to do on a stretch of the map, worded like the Figma route steps.
    private static func phrase(_ a: RouteMap.Node, _ b: RouteMap.Node, gate: String) -> (String, RouteStep.Turn) {
        switch (a, b) {
        case (.start, .cafeDoor): ("Follow the Gates 105–109 sign", .straight)
        case (.cafeDoor, .junction), (.cafe, .cafeDoor): ("Continue to the junction", .straight)
        case (.junction, .east): ("Take the stairs at the junction", .stairs)
        // ponytail: a changed gate (108A) shares the map; only the gate-area sign differs.
        case (.east, .bentoDoor), (.bentoDoor, .approach), (.bento, .bentoDoor):
            gate == SampleJourney.outbound.departureGate ? ("Go straight past Gate 104", .straight) : ("Follow signs for 108–149", .straight)
        case (.approach, .gate), (.windowsGate, .approach), (.windowsEast, .windowsGate): ("Turn left at the Gate \(gate) sign", .left)
        case (.junction, .lift): ("Turn right to the lift", .right)
        case (.lift, .junction): ("Go back to the central concourse", .straight)
        case (.lift, .southLink): ("Take the lift, then go straight", .lift)
        case (.southLink, .liftLane), (.liftLane, .windowsGate), (.sky, .liftLane): ("Continue along the level corridor", .straight)
        case (.liftLane, .southLink): ("Head back along the level corridor", .straight)
        case (.southLink, .windowsSouth): ("Turn right toward the windows", .right)
        case (.windowsSouth, .southLink): ("Turn left off the windows", .left)
        case (.start, .windowsWest): ("Keep right toward the windows", .right)
        case (.windowsWest, .udonDoor), (.udonDoor, .windowsSouth), (.udon, .udonDoor), (.windowsSouth, .windowsEast):
            ("Walk along the windows past Gates 101–104", .straight)
        default: ("Continue toward Gate \(gate)", .straight)
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
        // Camera access is asked in the AirBorder pop-up (RootView); open the camera once it's allowed.
        .onChange(of: store.cameraAllowed) { mode = .camera }
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
        return Button {
            if value == .camera, AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                store.asksForCamera = true
            } else {
                mode = value
            }
        } label: {
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
        return RouteMap(stops: RouteSteps.stopsInOrder(store), gate: store.gate, choice: store.routeChoice, position: steps[index].position) { id in
            // Tapping a stop on the map jumps to that stop's step.
            guard let name = store.plan.stops.first(where: { $0.id == id })?.name,
                  let target = steps.firstIndex(where: { $0.turn == .stop && $0.text.hasPrefix("Stop at \(name),") }) else { return }
            Haptics.tick()
            withAnimation(.abOut) { store.routeStep = target + 1 }
        }
            .contentShape(Rectangle())
            .onTapGesture { showsMapInfo = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("About this map")
            .accessibilityIdentifier("routeSummary")
            .sheet(isPresented: $showsMapInfo) { Sheets.aboutMap(walk: store.gateWalkMinutes) }
    }
}

/// Terminal 3, 3F floor plan with the walking route drawn on it. Each route choice takes its own corridors;
/// stops in the plan are rooms the route detours into, in arrive order. The walked part fills in as you go.
struct RouteMap: View {
    let stops: [PlanStop]
    let gate: String
    let choice: RouteChoice
    let position: CGFloat
    var select: (PlaceID) -> Void = { _ in }

    var body: some View {
        let route = Self.route(through: stops.map { Self.node(for: $0.id) }, choice: choice)
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.size.width
            let p = { (n: Node) in CGPoint(x: Self.points[n]!.x * scale, y: Self.points[n]!.y * scale) }
            let line = RouteLine(points: route.nodes.map(p))
            let walked = line.share(upToPoint: position)
            ZStack(alignment: .topLeading) {
                // Corridors
                ForEach(Self.edges.indices, id: \.self) { i in
                    let edge = Self.edges[i]
                    Path { path in path.move(to: p(edge.0)); path.addLine(to: p(edge.1)) }
                        .stroke(AB.screen, style: StrokeStyle(lineWidth: 18 * scale, lineCap: .round))
                }
                // Gates 101–104 along the windows
                ForEach(Array(["101", "102", "103", "104"].enumerated()), id: \.offset) { i, number in
                    Text(number).outfitText(12, .semibold, AB.secondary)
                        .position(x: (100 + CGFloat(i) * 52) * scale, y: 204 * scale)
                }
                Text("Windows").outfitText(12, .medium, AB.sky).position(x: 52 * scale, y: 204 * scale)
                room("Café", .cafe, at: p(.cafe))
                room("4F LOUNGE", .anaLounge, at: p(.lounge))
                room("SKY", .skyLounge, at: p(.sky))
                room("Bento", .bento, at: p(.bento))
                room("Udon", .udon, at: p(.udon))
                room("4F Sushi", .sushi, at: p(.sushi))
                icon("figure.stairs", at: CGPoint(x: (p(.junction).x + p(.east).x) / 2, y: p(.junction).y))
                icon("arrow.up.arrow.down", at: p(.lift))
                // Route: ahead dotted, walked solid
                line.stroke(AB.primary.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [2, 6]))
                line.trim(from: 0, to: walked)
                    .stroke(AB.ticket, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                Text("Start").outfitText(12, .bold, AB.secondary).position(x: p(.start).x + 2, y: p(.start).y - 20 * scale)
                Circle().fill(AB.ticket).frame(width: 10, height: 10).position(p(.start))
                Text(gate).outfitText(14, .bold, AB.gateText)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(AB.gateYellow, in: RoundedRectangle(cornerRadius: 7))
                    .position(p(.gate))
                Circle().fill(AB.primary)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .frame(width: 20, height: 20)
                    .shadow(color: AB.primary.opacity(0.45), radius: 6)
                    .position(line.point(atDistance: walked))
            }
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .animation(.spring(duration: 0.5, bounce: 0.12), value: position)
        .animation(.abOut, value: choice)
        .animation(.abOut, value: stops.map(\.id))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Map of the \(choice.title.lowercased()) route\(stops.isEmpty ? "" : " via \(stops.map(\.name).joined(separator: ", "))") to Gate \(gate)")
    }

    /// A room on the map; rooms in the plan are filled in and jump to their step when tapped.
    private func room(_ label: String, _ id: PlaceID, at point: CGPoint) -> some View {
        let color = PlanStripCard.color(id)
        let active = stops.contains { $0.id == id }
        return Button { select(id) } label: {
            Text(label).outfitText(12, .bold, active ? PlanStripCard.textColor(id) : AB.secondary)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(active ? color : .white, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(active ? color : AB.border, lineWidth: 1.5))
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.pressable)
        .allowsHitTesting(active)
        .accessibilityIdentifier("mapStop-\(id.rawValue)")
        .position(point)
    }

    private func icon(_ name: String, at point: CGPoint) -> some View {
        Image(systemName: name).font(.system(size: 10, weight: .bold)).foregroundStyle(AB.secondary)
            .frame(width: 20, height: 20)
            .background(.white, in: Circle())
            .overlay(Circle().strokeBorder(AB.border, lineWidth: 1))
            .position(point)
    }

    // MARK: Floor plan (map units; scaled to the card width)

    enum Node: Hashable {
        case start, cafeDoor, cafe, junction, east, approach, gate, lift, lounge, southLink, liftLane, sky
        case windowsWest, windowsSouth, windowsEast, windowsGate
        case bentoDoor, bento, udonDoor, udon, sushi
    }
    /// corridor: busy central concourse; level: step-free corridors on the lift side; windows: outer concourse.
    enum Kind { case corridor, stairs, lift, level, windows, door }

    static let size = CGSize(width: 340, height: 216)
    static let points: [Node: CGPoint] = [
        .start: CGPoint(x: 20, y: 84), .cafeDoor: CGPoint(x: 70, y: 84), .cafe: CGPoint(x: 70, y: 46),
        .junction: CGPoint(x: 140, y: 84), .east: CGPoint(x: 230, y: 84), .approach: CGPoint(x: 305, y: 84),
        .gate: CGPoint(x: 305, y: 26), .lift: CGPoint(x: 140, y: 128), .lounge: CGPoint(x: 78, y: 128),
        .southLink: CGPoint(x: 185, y: 128), .liftLane: CGPoint(x: 230, y: 128), .sky: CGPoint(x: 230, y: 158),
        .windowsWest: CGPoint(x: 20, y: 182), .windowsSouth: CGPoint(x: 185, y: 182),
        .windowsEast: CGPoint(x: 305, y: 182), .windowsGate: CGPoint(x: 305, y: 128),
        .bentoDoor: CGPoint(x: 268, y: 84), .bento: CGPoint(x: 268, y: 50),
        .udonDoor: CGPoint(x: 100, y: 182), .udon: CGPoint(x: 100, y: 156), .sushi: CGPoint(x: 140, y: 160),
    ]
    static let edges: [(Node, Node, Kind)] = [
        (.start, .cafeDoor, .corridor), (.cafeDoor, .cafe, .door), (.cafeDoor, .junction, .corridor),
        (.junction, .east, .stairs), (.east, .bentoDoor, .corridor), (.bentoDoor, .approach, .corridor), (.bentoDoor, .bento, .door),
        (.approach, .gate, .corridor), (.lift, .sushi, .door),
        (.junction, .lift, .lift), (.lift, .lounge, .door), (.lift, .southLink, .level), (.southLink, .liftLane, .level),
        (.liftLane, .sky, .door), (.liftLane, .windowsGate, .level), (.windowsGate, .approach, .level),
        (.southLink, .windowsSouth, .level),
        (.start, .windowsWest, .windows), (.windowsWest, .udonDoor, .windows), (.udonDoor, .windowsSouth, .windows), (.udonDoor, .udon, .door),
        (.windowsSouth, .windowsEast, .windows),
        (.windowsEast, .windowsGate, .windows),
    ]

    static func node(for id: PlaceID) -> Node {
        switch id {
        case .cafe: .cafe
        case .anaLounge: .lounge
        case .bento: .bento
        case .udon: .udon
        case .sushi: .sushi
        default: .sky
        }
    }

    /// How each route choice weighs the corridors: direct keeps to the centre and the stairs,
    /// step-free never takes the stairs, less crowded prefers the windows over the busy centre.
    private static func cost(_ kind: Kind, _ choice: RouteChoice) -> CGFloat {
        switch (choice, kind) {
        case (_, .door): 1
        case (.direct, .corridor), (.direct, .stairs): 1
        case (.direct, _): 3
        case (.stepFree, .stairs): 100
        case (.stepFree, .windows): 1.5
        case (.stepFree, _): 1
        case (.lessCrowded, .windows): 0.5
        case (.lessCrowded, .level), (.lessCrowded, .lift): 1.5
        case (.lessCrowded, .corridor): 2.5
        case (.lessCrowded, .stairs): 4
        }
    }

    /// Shortest walk start → each stop → gate on the floor plan for this choice.
    static func route(through stops: [Node], choice: RouteChoice) -> (nodes: [Node], stopIndices: [Int]) {
        var nodes: [Node] = [.start]
        var stopIndices: [Int] = []
        for target in stops + [.gate] {
            let leg = shortestPath(from: nodes.last!, to: target, choice: choice)
            nodes += leg.dropFirst()
            if target != .gate { stopIndices.append(nodes.count - 1) }
        }
        return (nodes, stopIndices)
    }

    private static func shortestPath(from start: Node, to goal: Node, choice: RouteChoice) -> [Node] {
        var distance: [Node: CGFloat] = [start: 0]
        var previous: [Node: Node] = [:]
        var open: Set<Node> = [start]
        while let current = open.min(by: { distance[$0, default: .infinity] < distance[$1, default: .infinity] }) {
            open.remove(current)
            if current == goal { break }
            for (a, b, kind) in edges where a == current || b == current {
                let next = a == current ? b : a
                let length = hypot(points[a]!.x - points[b]!.x, points[a]!.y - points[b]!.y) * cost(kind, choice)
                let candidate = distance[current, default: .infinity] + length
                if candidate < distance[next, default: .infinity] {
                    distance[next] = candidate
                    previous[next] = current
                    open.insert(next)
                }
            }
        }
        var path = [goal]
        while let back = previous[path[0]] { path.insert(back, at: 0) }
        return path
    }

    static func edge(_ a: Node, _ b: Node) -> (from: Node, to: Node, kind: Kind) {
        let match = edges.first { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) }!
        return (a, b, match.2)
    }

    static func length(of nodes: [Node]) -> CGFloat {
        zip(nodes, nodes.dropFirst()).map { hypot(points[$1]!.x - points[$0]!.x, points[$1]!.y - points[$0]!.y) }.reduce(0, +)
    }

    /// Compass heading of a corridor stretch (corridors are straight and axis-aligned).
    static func heading(_ a: Node, _ b: Node) -> Int {
        let dx = points[b]!.x - points[a]!.x, dy = points[b]!.y - points[a]!.y
        return abs(dx) >= abs(dy) ? (dx > 0 ? 0 : 2) : (dy > 0 ? 1 : 3)
    }
}

/// The route as a polyline through floor-plan points.
struct RouteLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    private var lengths: [CGFloat] { zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) } }
    private var total: CGFloat { lengths.reduce(0, +) }

    /// Share of the path walked when standing at point `index` (fractional indices fall between points).
    func share(upToPoint index: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let whole = min(max(Int(index), 0), lengths.count)
        var walked = lengths.prefix(whole).reduce(0, +)
        if whole < lengths.count { walked += lengths[whole] * (index - CGFloat(whole)) }
        return walked / total
    }

    /// The point a given share of the way along the path.
    func point(atDistance share: CGFloat) -> CGPoint {
        var remaining = share * total
        for (i, length) in lengths.enumerated() {
            if remaining <= length || i == lengths.count - 1 {
                let f = length > 0 ? min(remaining / length, 1) : 0
                return CGPoint(x: points[i].x + (points[i + 1].x - points[i].x) * f, y: points[i].y + (points[i + 1].y - points[i].y) * f)
            }
            remaining -= length
        }
        return points.last ?? .zero
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
