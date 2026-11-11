import SwiftUI

/// Figma "Layover & transit" (858:10462) and its Landside / City tabs (section 858:12531).
struct LayoverView: View {
    @EnvironmentObject private var store: JourneyStore
    @State private var area: Area = .airside
    @State private var filter: Filter = .all
    @State private var showsAirsideInfo = false

    enum Area: String, CaseIterable { case airside = "Airside", landside = "Landside", city = "City & transfer" }
    enum Filter: String, CaseIterable { case all = "All", rest = "Rest", food = "Food & drink" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Layover & transit").outfitText(30, .bold).tracking(-1.1).accessibilityAddTraits(.isHeader)
                areaTabs.padding(.top, 22)
                switch area {
                case .airside: airside
                case .landside: LandsideList()
                case .city: CityList()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 54)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsAirsideInfo) { Sheets.whyAirside() }
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
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("area-\(item.rawValue)")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(AB.border).frame(height: 1) }
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                Button { showsAirsideInfo = true } label: {
                    Image("icInfoWhy").resizable().frame(width: 16, height: 16).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About airside")
                .offset(x: proxy.size.width / 3 * 0.5 + 18, y: -1)
            }
        }
    }

    private var airside: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.top, 17)
            VStack(spacing: 13) {
                ForEach(Venue.airside.filter { filter == .all || $0.filter == filter }) { venue in
                    VenueCard(venue: venue)
                }
            }
        }
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
    ]
}

private struct VenueCard: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    let venue: Venue

    var body: some View {
        let added = store.plan.contains(venue.id)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if let airline = venue.airline { AirlineBadge(airline: airline) }
                    if let icon = venue.icon { Image(icon).resizable().frame(width: 20, height: 20) }
                    Button { if venue.id == .anaLounge { open(.anaLounge) } } label: {
                        Text(venue.name).outfitText(20, .bold, AB.ice).tracking(-0.2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(venue.id != .anaLounge)
                    Button {
                        if added {
                            store.remove(venue.id)
                        } else {
                            store.add(venue.stop)
                            store.showToast(ToastMessage(text: "Added to your plan", action: "View on Flight")) { store.tab = .flight }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(added ? "icCheckSmall" : "icPlusNavy").resizable().frame(width: 21, height: 21)
                            Text(added ? "In your plan" : "Add to plan").outfitText(14, .semibold, AB.ticket)
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 13)
                        .frame(minHeight: 47)
                        .background(AB.ice, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityIdentifier("add-\(venue.id.rawValue)")
                }
                HStack(spacing: 8) {
                    TerminalSign(terminal: SampleJourney.outbound.departureTerminal)
                    HStack(spacing: 6) {
                        Image("icWalkSmall").resizable().frame(width: 15, height: 15)
                        Text("\(walkFromYou) min")
                            .outfitText(13, .semibold, AB.ice)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 12)
                    .padding(.vertical, 7)
                    .background(AB.ice.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(walkFromYou) minute walk")
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 10) {
                FlowRow {
                    if let status = venue.status { Chip(text: status, tone: .open) }
                    if venue.showsLeaveBy {
                        Chip(text: "Leave by \(SampleJourney.gateArrivalTarget - store.walkMinutes(venue.id, .gate))", tone: .leaveBy)
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
    }

    /// Walking time between the venue and the gate (Figma cards: 4, 6 and 8 min on average).
    private var walkFromYou: Int { store.venueToGateMinutes(venue.id) }
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
                checked
                Button { openURL(URL(string: "tel:+81355797790")!) } label: {
                    Text("Call Air BicCamera, +81 3 5579 7790").outfitText(13, .bold, AB.sky).underline()
                }
                .buttonStyle(.plain)
                CTAButton(title: "View access & return", height: 47) { open(.landsideRoute(false)) }
            }
            LandsideCard {
                heading("icObservation", "Observation Deck")
                where_("3", "5F")
                FlowRow {
                    Chip(text: "Open 24 hours", tone: .open)
                }
                checked
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
                CTAButton(title: "View route & return") { open(.t2Deck) }
            }
        }
        .sheet(isPresented: $showsLeaving) { Sheets.beforeLeavingAirside(walk: store.gateWalkMinutes) }
    }

    private var checked: some View {
        Text("Hours checked 11:55 JST").outfitText(12, .regular, AB.ice.opacity(0.6))
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
        .buttonStyle(.plain)
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
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
