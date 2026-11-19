import SwiftUI

/// Figma "Layover & transit" (858:10462) and its Landside / City tabs (section 858:12531).
struct LayoverView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var airportProvider: AirportProviderReplay
    @Environment(\.openDestination) private var open
    @State private var area: Area = .airside
    @State private var filter: Filter = .all
    @State private var showsAirsideInfo = false

    enum Area: String, CaseIterable { case airside = "Airside", landside = "Landside", city = "City & transfer" }
    enum Filter: String, CaseIterable { case all = "All", rest = "Rest", food = "Food & drink" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Layover & transit").outfitText(30, .bold).tracking(-1.1).accessibilityAddTraits(.isHeader)
                TextLink(title: "Airport guides") { open(.airportGuides) }
                    .accessibilityIdentifier("airportGuidesLink")
                if let condition = store.primaryCondition {
                    TravelUpdateBanner(condition: condition, place: .layover).padding(.top, 16)
                }
                areaTabs.padding(.top, 22)
                switch area {
                case .airside:
                    if LoungeDirectory.covers(store.outbound) { airside }
                case .landside: LandsideList()
                case .city: CityList()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 54)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            if !store.plan.stops.isEmpty { planBar.padding(.bottom, 8) }
        }
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsAirsideInfo) { Sheets.whyAirside() }
    }

    /// Figma "Plan bar" (1172:17715): pinned above the tab bar once the plan has stops.
    private var planBar: some View {
        Button { open(.plan) } label: {
            HStack {
                HStack(spacing: 8) {
                    Text("Your plan").outfitText(15, .bold, .white)
                    Text("\(store.plan.stops.count)").outfitText(14, .bold, AB.gateText)
                        .contentTransition(.numericText(value: Double(store.plan.stops.count)))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(AB.gateYellow, in: Capsule())
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("View plan").outfitText(15, .bold, AB.gateYellow)
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold)).foregroundStyle(AB.gateYellow)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: AB.navy.opacity(0.2), radius: 8, y: 4)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Your plan, \(store.plan.stops.count) \(store.plan.stops.count == 1 ? "stop" : "stops"). View plan")
        .accessibilityIdentifier("planBar")
        .transition(.offset(y: 16).combined(with: .opacity))
    }

    private var areaTabs: some View {
        HStack(spacing: 4) {
            ForEach(Area.allCases, id: \.self) { item in
                let selected = item == area
                Button { area = item } label: {
                    Text(item.rawValue).outfitText(12, selected ? .semibold : .regular, selected ? AB.primary : AB.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selected ? AB.primary : .clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(item == .airside && !LoungeDirectory.covers(store.outbound)
                                   ? "Venue listings are unavailable for this terminal" : "")
                .accessibilityIdentifier("area-\(item.rawValue)")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(AB.border).frame(height: 1) }
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                Button { showsAirsideInfo = true } label: {
                    Image("icInfoWhy").resizable().frame(width: 16, height: 16).frame(width: 44, height: 44)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("About airside")
                .offset(x: proxy.size.width / 3 * 0.5 + 18, y: -1)
            }
        }
    }

    private var airside: some View {
        let lounges = LoungeDirectory.options(for: store.outbound, gate: store.gate, pace: store.pace)
        let loungeIDs = lounges.map(\.id)
        let gateWalksAvailable = store.gate == SampleJourney.outbound.departureGate
        let food = Venue.airside.filter { $0.filter == .food }
        let visibleVenues: [Venue] = switch filter {
        case .all: Venue.airside
        case .food: gateWalksAvailable ? food.sorted {
            store.venueToGateMinutes($0.id) < store.venueToGateMinutes($1.id)
        } : food
        case .rest: loungeIDs.compactMap { id in Venue.airside.first { $0.id == id } }
        }

        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 7) {
                ForEach(Filter.allCases, id: \.self) { item in
                    let selected = item == filter
                    Button { filter = item } label: {
                        Text(item.rawValue).outfitText(12, .regular, selected ? .white : AB.navy)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 42)
                            .background(selected ? AB.primary : .white, in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? AB.primary : AB.border, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.top, 17)
            if filter == .rest, airportProvider.currentPlanning(for: store) != nil {
                TextLink(title: "Lounges near your gate") { open(.nearbyLounges) }
                    .accessibilityIdentifier("nearbyLounges")
            }
            if filter != .rest, let offer = airportProvider.fittingCafe(for: store) {
                cafeOffer(offer.stop, arrival: offer.arrival)
            }
            VStack(spacing: 13) {
                ForEach(visibleVenues) { venue in
                    let nearestLounge = lounges.first { $0.id == venue.id }
                    let walk = if venue.filter == .rest {
                        nearestLounge?.walkToGate
                    } else {
                        gateWalksAvailable ? store.venueToGateMinutes(venue.id) : nil
                    }
                    VenueCard(venue: venue, walkToGate: walk)
                }
            }
        }
    }

    private func cafeOffer(_ stop: PlanStop, arrival: ClockTime) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Fits your connection", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .outfit(21, .bold, .white)
                .accessibilityAddTraits(.isHeader)
            Label(stop.name, systemImage: "cup.and.saucer")
                .outfit(18, .semibold, .white)
            FlowRow {
                Chip(text: "\(stop.visitMinutes) min visit · \(stop.waitMinutes) min wait")
                Chip(text: "At Gate \(store.gate) by \(arrival)", tone: .leaveBy)
            }
            CTAButton(title: "Review stop", style: .light) {
                open(.reviewCafe(wait: stop.waitMinutes, arrival: arrival))
            }
            .accessibilityIdentifier("reviewCafeOffer")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.ticket, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct CafeOfferReview: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var airportProvider: AirportProviderReplay
    @Environment(\.dismiss) private var dismiss
    let wait: Int
    let arrival: ClockTime
    @State private var changed = false

    private var canAdd: Bool {
        guard !changed, let offer = airportProvider.fittingCafe(for: store) else { return false }
        return offer.stop.waitMinutes == wait && offer.arrival == arrival
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StackedHeader(title: PlanStop.cafe.name) { dismiss() }
                if canAdd {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(PlanStop.cafe.visitMinutes) min visit · \(wait) min wait")
                            .outfitText(16, .semibold)
                        Text("Estimated arrival at Gate \(store.gate) at \(arrival.description)")
                            .outfitText(16, .regular, AB.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    CTAButton(title: "Add to plan") {
                        var cafe = PlanStop.cafe
                        cafe.waitMinutes = wait
                        if airportProvider.addFittingCafe(cafe, arrival: arrival, to: store) {
                            dismiss()
                        } else {
                            changed = true
                        }
                    }
                    .accessibilityIdentifier("addReviewedCafe")
                } else {
                    Text("This stop needs a new timing check. Return to Layover for the latest options.")
                        .outfitText(16, .regular, AB.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct NearbyLoungesView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var airportProvider: AirportProviderReplay
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.openDestination) private var open
    @State private var selected: PlaceID?

    var body: some View {
        let planning = airportProvider.currentPlanning(for: store)
        let gateIsCurrent = airportProvider.planningReachable && planning.map {
            DriverPlanningSnapshot.isFresh($0.gateCheckedAt, at: .now)
        } == true
        let options = gateIsCurrent ? (planning?.lounges ?? []).sorted { $0.walkMinutes < $1.walkMinutes } : planning?.lounges ?? []
        let choice = options.first { $0.id == selected } ?? options.first
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StackedHeader(title: "Lounges") { dismiss() }
                if let planning, let choice {
                    FlowRow {
                        TerminalSign(terminal: planning.terminal)
                        Text(gateIsCurrent ? "Near Gate \(planning.gate)" : "Gate proximity unavailable")
                            .outfitText(14, .semibold)
                    }
                    ForEach(options) { lounge in
                        loungeCard(lounge, selected: lounge.id == choice.id, showWalk: gateIsCurrent)
                    }
                    CTAButton(title: "Directions") {
                        if choice.place == .anaLounge {
                            open(.loungeMap)
                        } else if let url = URL(string: "https://tokyo-haneda.com/en/floor/floor-guide.html?area=9&tab=terminal3&floor=4F") {
                            openURL(url)
                        }
                    }
                } else {
                    Text("Lounge details are unavailable for this terminal.")
                        .outfitText(16, .regular, AB.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func loungeCard(_ lounge: DriverPlanningSnapshot.Lounge, selected: Bool, showWalk: Bool) -> some View {
        Button {
            self.selected = lounge.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(lounge.place == .anaLounge ? "ANA LOUNGE" : "SKY LOUNGE")
                        .outfitText(18, .bold, .white)
                    Spacer(minLength: 0)
                    if showWalk {
                        let walk = WalkingTimes.minutes(average: lounge.walkMinutes, pace: store.pace)
                        Text("\(walk) min walk").outfitText(14, .semibold, AB.ice)
                            .accessibilityLabel("\(walk) minute walk to the gate")
                    }
                }
                HStack {
                    Text(lounge.access == .businessClass ? "Business class · Check at entrance" : "Paid entry · Check at entrance")
                        .outfitText(14, .regular, AB.ice)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(AB.gateYellow)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("ranked-lounge-\(lounge.place.rawValue)")
    }
}

private struct AirportGuide: Identifiable {
    let code: String
    let name: String
    let destination: URL
    var id: String { code }

    static let guides = [
        Self(code: "HND", name: "Tokyo Haneda",
             destination: URL(string: "https://tokyo-haneda.com/en/shop_and_dine/search_r.html")!),
        Self(code: "NRT", name: "Tokyo Narita",
             destination: URL(string: "https://www.narita-airport.jp/en/shop/shop-search/?category=shop")!),
        Self(code: "LHR", name: "London Heathrow",
             destination: URL(string: "https://www.heathrow.com/at-the-airport")!)
    ]
}

struct AirportGuidesView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var airportProvider: AirportProviderReplay
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedGuide: String?

    private var directory: [DriverPlanningSnapshot.Guide] {
        (airportProvider.planning?.airports ?? []).filter { $0.code == "SIN" }
    }

    private var matches: [AirportGuide] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? AirportGuide.guides : AirportGuide.guides.filter {
            $0.code.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    private var directoryMatches: [DriverPlanningSnapshot.Guide] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? directory : directory.filter {
            $0.code.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search)
                || $0.city.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BackButton(showsText: true) { dismiss() }
                Text("Airport guides").outfitText(30, .bold)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AB.secondary).accessibilityHidden(true)
                    TextField("Airport or code", text: $query,
                              prompt: Text("Airport or code").foregroundStyle(AB.secondary))
                        .outfit(16)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("airportGuideSearch")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(.white, in: Capsule())
                .overlay(Capsule().strokeBorder(AB.border))

                if matches.isEmpty && directoryMatches.isEmpty {
                    Text("No matching airports").outfitText(16, .regular, AB.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(matches) { guide in
                            if guide.id != matches.first?.id { Divider() }
                            Link(destination: guide.destination) {
                                guideRow(code: guide.code, name: guide.name,
                                         subtitle: guide.code == store.outbound.from.code ? "Current trip" : nil,
                                         icon: "arrow.right")
                            }
                            .accessibilityHint("Opens the airport’s official website")
                            .accessibilityIdentifier("airport-guide-\(guide.code)")
                        }
                        ForEach(directoryMatches) { guide in
                            if !matches.isEmpty || guide.id != directoryMatches.first?.id { Divider() }
                            Button {
                                selectedGuide = selectedGuide == guide.id ? nil : guide.id
                            } label: {
                                guideRow(code: guide.code, name: guide.name, subtitle: "Terminal guides",
                                         icon: selectedGuide == guide.id ? "chevron.up" : "chevron.down")
                            }
                            .buttonStyle(.pressable)
                            .accessibilityIdentifier("airport-guide-\(guide.code)")
                            if selectedGuide == guide.id {
                                ForEach(guide.terminals, id: \.self) { terminal in
                                    if let url = changiGuide(terminal: terminal) {
                                        Divider()
                                        Link(destination: url) {
                                            Label("Terminal \(terminal)", systemImage: "arrow.up.right")
                                                .outfit(16, .semibold, AB.primary)
                                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                                .contentShape(Rectangle())
                                        }
                                        .accessibilityHint("Opens Changi Airport’s terminal guide")
                                        .accessibilityIdentifier("airport-guide-SIN-terminal-\(terminal)")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func guideRow(code: String, name: String, subtitle: String?, icon: String) -> some View {
        HStack(spacing: 12) {
            Text(code).outfitText(17, .bold, AB.gateText)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(AB.gateYellow, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).outfitText(17, .semibold)
                if let subtitle { Text(subtitle).outfitText(14, .regular, AB.primary) }
            }
            Spacer(minLength: 4)
            Image(systemName: icon).foregroundStyle(AB.primary).accessibilityHidden(true)
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private func changiGuide(terminal: String) -> URL? {
        guard ["1", "2", "3", "4"].contains(terminal) else { return nil }
        return URL(string: "https://www.changiairport.com/en/at-changi/terminal-guides/terminal-\(terminal).html")
    }
}

// MARK: - Airside venues

struct Venue: Identifiable {
    let id: PlaceID
    let name: String
    let icon: String?
    let airline: Airline?
    let filter: LayoverView.Filter
    let floor: String
    let status: String?
    let details: [String]
    let amenities: [String]
    let showsLeaveBy: Bool
    let stop: PlanStop

    static let airside: [Venue] = [
        Venue(id: .anaLounge, name: "LOUNGE", icon: nil, airline: .ana, filter: .rest, floor: "4F", status: "Open now",
              details: ["Business Class pass"], amenities: ["icWifi", "icSeating"], showsLeaveBy: true, stop: .anaLounge),
        Venue(id: .cafe, name: "Curacion Cafe", icon: "icCoffee", airline: nil, filter: .food, floor: "3F", status: nil,
              details: ["05:30–02:00", "Coffee & light meals"], amenities: ["icSeating"], showsLeaveBy: false, stop: .cafe),
        Venue(id: .skyLounge, name: "SKY LOUNGE", icon: "icRest", airline: nil, filter: .rest, floor: "4F", status: "Open 24 hours",
              details: ["JPY 1,500"], amenities: ["icSeating"], showsLeaveBy: false, stop: .skyLounge),
        // ponytail: sample food places to compare quick and sit-down meals; descriptive names, not real outlets.
        Venue(id: .bento, name: "Bento & Onigiri To Go", icon: "sf:takeoutbag.and.cup.and.straw.fill", airline: nil, filter: .food, floor: "3F",
              status: nil, details: ["Grab and go"], amenities: [], showsLeaveBy: false, stop: .bento),
        Venue(id: .udon, name: "Udon Noodle Counter", icon: "sf:fork.knife", airline: nil, filter: .food, floor: "3F",
              status: nil, details: ["Counter seats"], amenities: ["icSeating"], showsLeaveBy: false, stop: .udon),
        Venue(id: .sushi, name: "Sushi Restaurant", icon: "sf:fork.knife", airline: nil, filter: .food, floor: "4F",
              status: nil, details: ["Table service"], amenities: ["icSeating"], showsLeaveBy: false, stop: .sushi),
    ]
}

private struct VenueCard: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    let venue: Venue
    let walkToGate: Int?
    @State private var warning: (title: String, message: String)?

    var body: some View {
        let added = store.plan.contains(venue.id)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if let airline = venue.airline { AirlineBadge(airline: airline) }
                    if let icon = venue.icon {
                        if icon.hasPrefix("sf:") {
                            Image(systemName: String(icon.dropFirst(3))).font(.system(size: 16, weight: .semibold)).foregroundStyle(AB.ice).frame(width: 20, height: 20)
                        } else {
                            Image(icon).resizable().frame(width: 20, height: 20)
                        }
                    }
                    Button { if venue.id == .anaLounge { open(.anaLounge) } } label: {
                        Text(venue.name).outfitText(20, .bold, AB.ice).tracking(-0.2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.pressable)
                    .allowsHitTesting(venue.id == .anaLounge)
                    // Figma Place Card "Show add" / "Show remove": the plan bar below shows what was added.
                    Button {
                        if !added, let check = store.fitWarning(for: venue.stop) {
                            Haptics.warning()
                            warning = check
                            return
                        }
                        Haptics.tap()
                        withAnimation(.abOut) {
                            if added { store.removeWithUndo(venue.id) } else { store.add(venue.stop) }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if added {
                                Image(systemName: "minus").font(.system(size: 14, weight: .bold)).foregroundStyle(AB.removeRed).frame(width: 21, height: 21)
                            } else {
                                Image("icPlusNavy").resizable().frame(width: 21, height: 21)
                            }
                            Text(added ? "Remove" : "Add to plan").outfitText(14, .semibold, added ? AB.removeRed : AB.ticket)
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 13)
                        .frame(minHeight: 47)
                        .background(added ? Color(hex: 0xFCEDED) : AB.ice, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .fixedSize()
                    .accessibilityIdentifier("add-\(venue.id.rawValue)")
                }
                HStack(spacing: 8) {
                    TerminalSign(terminal: SampleJourney.outbound.departureTerminal)
                    if let walkToGate {
                        HStack(spacing: 6) {
                            Image("icWalkSmall").resizable().frame(width: 15, height: 15)
                            Text("\(walkToGate) min")
                                .outfitText(13, .semibold, AB.ice)
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 12)
                        .padding(.vertical, 7)
                        .background(AB.ice.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(walkToGate) minute walk to the gate")
                        .accessibilityIdentifier("venueWalk-\(venue.id.rawValue)")
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 10) {
                FlowRow {
                    if let times = store.times(venue.id) {
                        Chip(text: "In your plan \(times.arrive)–\(times.leave)", tone: .leaveBy)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                    }
                    if let meal = venue.id.meal {
                        Chip(text: meal.sitDown ? "Sit-down, ~\(meal.minutes) min" : "Quick, ~\(meal.minutes) min", tone: meal.sitDown ? .sitDown : .quick)
                    }
                    if let status = venue.status { Chip(text: status, tone: .open) }
                    if venue.showsLeaveBy, let walkToGate {
                        Chip(text: "Leave by \(SampleJourney.gateArrivalTarget - walkToGate)", tone: .leaveBy)
                            .accessibilityIdentifier("venueLeaveBy-\(venue.id.rawValue)")
                    }
                    ForEach(venue.details, id: \.self) { Chip(text: $0) }
                    Chip(text: venue.floor)
                }
                HStack(spacing: 16) {
                    ForEach(venue.amenities, id: \.self) { Image($0).resizable().frame(width: 24, height: 24) }
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .onTapGesture { open(.facilityGuide) }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(venue.amenities.contains("icWifi") ? "Wi-Fi and seating" : "Seating")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .background(AB.ticket, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .alert(warning?.title ?? "", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
            Button("Add anyway") {
                Haptics.tap()
                withAnimation(.abOut) { store.add(venue.stop) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(warning?.message ?? "")
        }
    }
}

// MARK: - Landside (Figma 858:12562)

private struct LandsideList: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.openURL) private var openURL
    @State private var showsLeaving = false

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                Image("icShieldLarge").resizable().frame(width: 34, height: 34)
                Text("Return: 30 min security + \(store.gateWalkMinutes) min walk")
                    .outfitText(13, .regular, AB.muted)
                    .multilineTextAlignment(.center)
                TextLink(title: "View return details") { showsLeaving = true }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(AB.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AB.border, lineWidth: 1))

            LandsideCard(radius: 16) {
                Text("STATION BOOTH").outfitText(20, .bold, AB.ice)
                where_("3", "2F")
                FlowRow { Chip(text: "Private workspace") }
                externalLink("View booth & booking ↗", "https://www.tokyo-haneda.com/en/shop_and_dine/detail/tenant_00567.html")
            }
            LandsideCard {
                heading("icShopping", "Air BicCamera")
                where_("3", "2F", extra: "Arrivals")
                FlowRow {
                    Chip(text: "07:00–22:00")
                    Chip(text: "Travel accessories & electronics")
                }
                Button { openURL(URL(string: "tel:+81355797790")!) } label: {
                    Text("Call Air BicCamera, +81 3 5579 7790").outfitText(13, .bold, AB.sky).underline()
                }
                .buttonStyle(.pressable)
                CTAButton(title: "View access & return", height: 47) { open(.landsideRoute(false)) }
            }
            LandsideCard {
                heading("icObservation", "Observation Deck")
                where_("3", "5F")
                FlowRow {
                    Chip(text: "Open 24 hours", tone: .open)
                }
                CTAButton(title: "View visit details", height: 47) { open(.landsideRoute(true)) }
            }
            LandsideCard(padding: 18) {
                Text("T2 Observation Deck").outfitText(20, .bold, .white)
                where_("2", "5F")
                FlowRow {
                    Chip(text: "06:30–22:00")
                    Chip(text: "Free shuttle, T3 → T1 → T2")
                }
                HStack(spacing: 8) {
                    Image("icWalkWhite20").resizable().frame(width: 20, height: 20)
                    Image("icShuttleBus").resizable().frame(width: 24, height: 24)
                    Text("30 min").outfitText(15, .semibold, .white)
                    Spacer()
                }
                CTAButton(title: "View route & return") {
                    open(TerminalTwo.hasTime(now: store.now, gateWalk: store.gateWalkMinutes) ? .t2Deck : .t2NotEnoughTime)
                }
            }
        }
        .sheet(isPresented: $showsLeaving) { Sheets.beforeLeavingAirside(walk: store.gateWalkMinutes) }
    }

    private func heading(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(icon).resizable().frame(width: 24, height: 24)
            Text(title).outfitText(20, .bold, .white)
        }
        .frame(height: 28)
    }

    private func where_(_ terminal: String, _ floor: String, extra: String? = nil) -> some View {
        HStack(spacing: 6) {
            TerminalSign(terminal: terminal)
            Text(floor).outfitText(13, .bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AB.ice, in: RoundedRectangle(cornerRadius: 6))
            if let extra { Chip(text: extra) }
        }
    }

    private func externalLink(_ title: String, _ url: String) -> some View {
        Button { openURL(URL(string: url)!) } label: {
            Text(title).outfitText(14, .semibold, AB.sky).underline()
        }
        .buttonStyle(.pressable)
    }
}

private struct LandsideCard<Content: View>: View {
    var radius: CGFloat = 20
    var padding: CGFloat? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, padding ?? 20)
            .padding(.vertical, 18)
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: radius))
    }
}

// MARK: - City & transfer (Figma 858:12577)

private struct CityList: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Places to visit").outfitText(20, .semibold).accessibilityAddTraits(.isHeader)
            Text("Back at HND Terminal 3 by 15:30").outfitText(14, .semibold)
            place(
                "Footbath Sky Deck",
                lines: ["Tenkubashi, HANEDA INNOVATION CITY", "Visit, 30 min"],
                link: ("View the Sky Deck ↗", "https://haneda-innovation-city.com/facility/")
            ) {
                Image("icTrain").resizable().frame(width: 20, height: 20)
            }
            place(
                "Anamori Inari Shrine",
                lines: ["To Anamori-inari", "Visit, 30 min"],
                link: ("Explore the shrine ↗", "https://anamori.jp/")
            ) {
                Image("logoKeikyu").resizable().scaledToFit().frame(width: 56, height: 14).padding(.vertical, 4)
                    .accessibilityLabel("Keikyu line")
            }
        }
    }

    private func place<Icon: View>(_ name: String, lines: [String], link: (String, String), @ViewBuilder icon: () -> Icon) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).outfitText(18, .semibold)
            HStack(alignment: .top, spacing: 8) {
                icon()
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines, id: \.self) { Text($0).outfitText(14, .regular, AB.muted) }
                }
            }
            Button { openURL(URL(string: link.1)!) } label: {
                Text(link.0).outfitText(14, .semibold).underline()
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
