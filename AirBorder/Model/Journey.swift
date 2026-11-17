import Foundation

/// Minutes since local midnight at the airport. Display as "HH:mm".
struct ClockTime: Comparable, Hashable, Codable, CustomStringConvertible {
    var minutes: Int

    init(_ hour: Int, _ minute: Int) { minutes = hour * 60 + minute }
    init(minutes: Int) { self.minutes = minutes }

    static func < (lhs: ClockTime, rhs: ClockTime) -> Bool { lhs.minutes < rhs.minutes }
    static func + (lhs: ClockTime, rhs: Int) -> ClockTime { ClockTime(minutes: lhs.minutes + rhs) }
    static func - (lhs: ClockTime, rhs: Int) -> ClockTime { ClockTime(minutes: lhs.minutes - rhs) }
    static func - (lhs: ClockTime, rhs: ClockTime) -> Int { lhs.minutes - rhs.minutes }

    var description: String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }
}

/// "5h 25m", "4h 53m", "45m".
func durationText(_ minutes: Int) -> String {
    let value = max(minutes, 0)
    if value < 60 { return "\(value)m" }
    return "\(value / 60)h \(value % 60)m"
}

struct Airport: Hashable {
    let code: String
    let city: String
    var displayName: String? = nil
    var shortName: String { displayName ?? city }
}

struct FlightLeg: Hashable, Identifiable {
    let id: String
    let airline: Airline
    let number: String
    let from: Airport
    let to: Airport
    let departs: ClockTime
    let arrives: ClockTime
    /// +1 when the local arrival date is the next calendar day; nil when it is the same day.
    let arrivalDayOffset: Int?
    let status: String
    let departureTerminal: String
    let departureGate: String
    let gateCloses: ClockTime?
    let arrivalTerminal: String
    let arrivalGate: String
    let baggageBelt: String?
    var cabin: String? = nil
    /// Local departure date, e.g. "2026-10-15".
    var date: String = ""
    /// Gate-to-gate time across time zones.
    var durationMinutes: Int? = nil
}

/// Presentation assets and synthetic observations must be explicitly selected, never inferred from an airport code.
enum BundledJourneyFixture: Equatable {
    case hanedaConnection, naritaTransfer
}

/// Source-provided instructions for a particular gate. No coordinates or AR are inferred.
struct GateDirections {
    let gate: String
    let instructions: [String]
}

/// The active legs determine whether an airport change is required.
struct JourneyDefinition {
    let inbound: FlightLeg
    let outbound: FlightLeg
    let planning: PlanningContext?
    let boarding: ClockTime?
    let now: ClockTime
    var fixture: BundledJourneyFixture? = nil
    /// Supplied elapsed duration, based on dated times in a common clock or otherwise confirmed.
    var layoverMinutes: Int? = nil
    var checklist: JourneyChecklist? = nil
    var airportWalks: [AirportWalk] = []
    var queueUpdate: QueueUpdate? = nil
    var syntheticGateUpdate: String? = nil
    var transfer: AirportTransferDetails? = nil
    var presentation: JourneyPresentationDetails? = nil
    var gateDirections: GateDirections? = nil

    /// Unambiguous journey persistence scope, not a display label.
    var persistenceIdentifier: String {
        [inbound.id, inbound.date, inbound.from.code, inbound.to.code, inbound.arrivalTerminal,
         outbound.id, outbound.date, outbound.from.code, outbound.to.code, outbound.departureTerminal]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }

    var changesAirports: Bool {
        inbound.to.code.caseInsensitiveCompare(outbound.from.code) != .orderedSame
    }
    var changesTerminals: Bool {
        guard !changesAirports, !inbound.arrivalTerminal.isEmpty, !outbound.departureTerminal.isEmpty else { return false }
        return inbound.arrivalTerminal.caseInsensitiveCompare(outbound.departureTerminal) != .orderedSame
    }
}

/// The traveller's trip: Bangkok → Tokyo Haneda → Los Angeles.
///
/// The app ships with one saved sample journey. Help & information and About AirBorder say so;
/// no flight status here is presented as live.
enum SampleJourney {
    static let bangkok = Airport(code: "BKK", city: "Bangkok")
    static let haneda = Airport(code: "HND", city: "Tokyo Haneda", displayName: "Haneda")
    static let losAngeles = Airport(code: "LAX", city: "Los Angeles")
    static let narita = Airport(code: "NRT", city: "Tokyo Narita", displayName: "Narita")

    static let inbound = FlightLeg(
        id: "TG660",
        airline: .thai,
        number: "TG 660",
        from: bangkok,
        to: haneda,
        departs: ClockTime(5, 15),
        arrives: ClockTime(11, 15),
        arrivalDayOffset: nil,
        status: "Arrived",
        departureTerminal: "",
        departureGate: "D5",
        gateCloses: nil,
        arrivalTerminal: "3",
        arrivalGate: "146",
        baggageBelt: nil
    )

    static let outbound = FlightLeg(
        id: "NH106",
        airline: .ana,
        number: "NH 106",
        from: haneda,
        to: losAngeles,
        departs: ClockTime(18, 0),
        arrives: ClockTime(11, 45),
        arrivalDayOffset: nil,
        status: "Scheduled",
        departureTerminal: "3",
        departureGate: "105",
        gateCloses: ClockTime(17, 25),
        arrivalTerminal: "B",
        arrivalGate: "148",
        baggageBelt: "7",
        cabin: "Business",
        date: "2026-10-15",
        durationMinutes: 9 * 60 + 45
    )

    /// NH 6 from Narita, chosen on Edit flight details (Figma "Transfer HND → NRT", 858:9828).
    static let naritaOutbound = FlightLeg(
        id: "NH6",
        airline: .ana,
        number: "NH 6",
        from: narita,
        to: losAngeles,
        departs: ClockTime(21, 0),
        arrives: ClockTime(15, 0),
        arrivalDayOffset: nil,
        status: "Scheduled",
        departureTerminal: "1",
        departureGate: "",
        gateCloses: ClockTime(20, 20),
        arrivalTerminal: "B",
        arrivalGate: "148",
        baggageBelt: "7",
        cabin: "Business",
        date: "2026-10-15",
        durationMinutes: 10 * 60
    )

    static let departures = [outbound, naritaOutbound]

    static func departure(number: String) -> FlightLeg? {
        let normalized = number.filter { !$0.isWhitespace }.uppercased()
        return departures.first { $0.number.filter { !$0.isWhitespace }.uppercased() == normalized }
    }

    static func definition(for outbound: FlightLeg) -> JourneyDefinition {
        let usesSamplePlanning = outbound.id == Self.outbound.id
            && outbound.from.code == inbound.to.code
            && outbound.departureTerminal == inbound.arrivalTerminal
        let usesTransfer = outbound.id == naritaOutbound.id
            && outbound.from.code == naritaOutbound.from.code
            && outbound.departureTerminal == naritaOutbound.departureTerminal
        let fixture: BundledJourneyFixture? = usesSamplePlanning ? .hanedaConnection : usesTransfer ? .naritaTransfer : nil
        return JourneyDefinition(
            inbound: inbound, outbound: outbound, planning: usesSamplePlanning ? planning : nil,
            boarding: usesSamplePlanning ? boarding : nil, now: now, fixture: fixture,
            layoverMinutes: fixture == nil ? nil : outbound.departs - inbound.arrives,
            checklist: usesSamplePlanning ? .haneda : usesTransfer ? .narita : nil,
            airportWalks: fixture == nil ? [] : airportWalks,
            queueUpdate: usesSamplePlanning ? QueueUpdate(stopID: .cafe, waitMinutes: 18) : nil,
            syntheticGateUpdate: usesSamplePlanning ? updatedGate : nil,
            transfer: usesTransfer ? groundTransfer : nil,
            presentation: fixture == nil ? nil : presentation
        )
    }

    /// Return flight shown from Journey details (Figma 858:13081).
    static let returnFlight = FlightLeg(
        id: "NH105",
        airline: .ana,
        number: "NH 105",
        from: losAngeles,
        to: haneda,
        departs: ClockTime(0, 50),
        arrives: ClockTime(5, 0),
        arrivalDayOffset: 1,
        status: "Nonstop",
        departureTerminal: "B",
        departureGate: "",
        gateCloses: nil,
        arrivalTerminal: "2",
        arrivalGate: "–",
        baggageBelt: nil,
        date: "2026-10-21",
        durationMinutes: 12 * 60 + 10
    )

    /// The moment the sample journey is shown at: 12:00 at Haneda, 45 minutes after landing.
    static let now = ClockTime(12, 0)

    /// The airline asks passengers to be at the gate 20 minutes before it closes.
    static let gateArrivalTarget = ClockTime(17, 5)
    static let updatedGate = "108A"
    static let mapGateAssignments: Set<String> = [outbound.departureGate, updatedGate]

    /// Layover length shown in Journey details.
    static var layoverMinutes: Int { outbound.departs - inbound.arrives }

    /// NH 106 boarding time.
    static let boarding = ClockTime(17, 0)

    /// When stops start if the traveller adds any.
    static let planStart = ClockTime(16, 0)

    /// Bundled evaluation fixture, never a fallback for another airport or unknown venue.
    static let planning = PlanningContext(
        planStart: planStart, gateArrivalTarget: gateArrivalTarget, gateCloses: outbound.gateCloses,
        timelineStart: ClockTime(15, 0), timelineMinutes: 150,
        preferredArrivals: [.anaLounge: ClockTime(16, 30), .skyLounge: ClockTime(15, 30),
                            .bento: ClockTime(16, 15), .udon: ClockTime(15, 45), .sushi: ClockTime(15, 15)]
    ) { a, b in
        let places: Set<PlaceID> = [.start, .cafe, .anaLounge, .skyLounge, .bento, .udon, .sushi, .gate]
        guard places.contains(a), places.contains(b) else { return nil }
        switch Set([a, b]) {
        case [.start, .cafe]: return 0
        case [.start, .anaLounge]: return 5
        case [.start, .skyLounge]: return 8
        case [.start, .gate]: return 12
        case [.cafe, .anaLounge]: return 5
        case [.cafe, .gate]: return 8
        case [.anaLounge, .gate]: return 4
        default: return 8  // Bundled estimate for the remaining fixture paths.
        }
    }

    /// Walks recorded on the traveller's previous trips through Haneda (Figma "Previous trips").
    static let airportWalks = [
        AirportWalk(metres: 840, minutes: 12),
        AirportWalk(metres: 630, minutes: 9),
        AirportWalk(metres: 1050, minutes: 15),
    ]

    /// Number behind "Call ANA" in the Figma Journey details screen (858:13289).
    static let anaPhone = "+81367411120"
}

/// Ground-transfer presentation data for a journey that has route coverage.
struct AirportTransferDetails {
    let arrivalName: String
    let departureName: String
    let transportName: String
    let departs: ClockTime
    let arrives: ClockTime
    let fare: String
    let recheckBy: ClockTime
    let baggageCollectionFloor: String
    let departureLocation: String
    let zoneLabel: String
    let routeImage: String?
    let entryLabel: String
    let entryInstruction: String
    let documentsURL: String
    let arrivalInstruction: String
    let boardingInstruction: String
    let groundDepartureInstruction: String
    let directions: [String]
    var elapsedMinutes: Int? = nil
    /// True only when the current journey clock and departure-airport clock share a time basis.
    var comparesWithJourneyClock: Bool = false

    var minutes: Int? { elapsedMinutes.flatMap { $0 > 0 ? $0 : nil } }
    var durationLabel: String? { minutes.map { "\($0) min" } }
}

/// Confirmed or explicitly sampled fare, directions, and baggage data; absence is unavailable.
struct BaggageAllowance {
    let checked: String
    let extraChecked: String
    let cabin: String
    let extraBagLimit: String
}

struct BoardingContact {
    let name: String
    let phone: String
    let hours: String
    var url: URL? { URL(string: "tel:\(phone)") }
}

struct AirportAirsideHelp {
    let returnMinutes: Int
    let documentLabel: String
    let documentDetail: String
    let baggageDetail: String
    let linkTitle: String
    let linkURL: String
}

struct AirportFloorGuide {
    let startLabel: String
    let startDetail: String
    let signLabel: String
    let walkDetail: String
    let buttonTitle: String
    let url: String
}

/// Presentation metadata supplied by a journey source, never inferred from an airport code.
struct JourneyPresentationDetails {
    var baggage: BaggageAllowance? = nil
    var baggageTaggedThrough: Bool? = nil
    var returnFlight: FlightLeg? = nil
    var flightContactPhone: String? = nil
    var boardingContact: BoardingContact? = nil
    var airside: AirportAirsideHelp? = nil
    var floorGuide: AirportFloorGuide? = nil

    var airsideReturnMinutes: Int? { airside?.returnMinutes }
}

/// The original recorded demonstration; these are not defaults for other journeys.
extension SampleJourney {
    static let presentation = JourneyPresentationDetails(
        baggage: BaggageAllowance(checked: "1 × 32 kg", extraChecked: "2 × 32 kg",
                                  cabin: "10 kg", extraBagLimit: "32 kg"),
        baggageTaggedThrough: true, returnFlight: returnFlight, flightContactPhone: anaPhone,
        boardingContact: BoardingContact(name: "ANA", phone: "+81366260648", hours: "07:00–19:00"),
        airside: AirportAirsideHelp(returnMinutes: 30, documentLabel: "Passport ready",
                                  documentDetail: "For Japan arrival checks", baggageDetail: "Stays with the airline",
                                  linkTitle: "Japan entry information ↗",
                                  linkURL: "https://www.mofa.go.jp/j_info/visit/visa/index.html"),
        floorGuide: AirportFloorGuide(startLabel: "Start after transfer security", startDetail: "Terminal 3, 3F",
                                     signLabel: "Follow Gates 105–109", walkDetail: "Same level, no stairs",
                                     buttonTitle: "Open Haneda floor guide",
                                     url: "https://tokyo-haneda.com/en/floor/floor-guide.html?area=9&tab=terminal3&floor=3F")
    )

    static let groundTransfer = AirportTransferDetails(
        arrivalName: "Haneda", departureName: "Narita", transportName: "Airport bus",
        departs: ClockTime(13, 10), arrives: ClockTime(14, 45), fare: "JPY 3,600",
        recheckBy: ClockTime(20, 0), baggageCollectionFloor: "2F", departureLocation: "1F bus stops",
        zoneLabel: "JST", routeImage: "busRouteHNDNRT", entryLabel: "Entry document, Japan",
        entryInstruction: "Have your passport ready",
        documentsURL: "https://www.mofa.go.jp/j_info/visit/visa/index.html",
        arrivalInstruction: "Go through passport control, collect your bag, then pass through customs.",
        boardingInstruction: "Pass through security and departure passport control.",
        groundDepartureInstruction: "Follow the Bus signs from the 2F access hall to the 1F bus stops.",
        directions: ["Follow Bus signs", "Continue to the 1F buses", "Stop 5, Narita Airport"],
        elapsedMinutes: 95, comparesWithJourneyClock: true
    )
}
