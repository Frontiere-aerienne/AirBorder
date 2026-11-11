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

/// The traveller's trip: Bangkok → Tokyo Haneda → Los Angeles.
///
/// The app ships with one saved sample journey. Help & information and About AirBorder say so;
/// no flight status here is presented as live.
enum SampleJourney {
    static let bangkok = Airport(code: "BKK", city: "Bangkok")
    static let haneda = Airport(code: "HND", city: "Tokyo Haneda")
    static let losAngeles = Airport(code: "LAX", city: "Los Angeles")
    static let narita = Airport(code: "NRT", city: "Tokyo Narita")

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

    /// Layover length shown in Journey details.
    static var layoverMinutes: Int { outbound.departs - inbound.arrives }

    /// NH 106 boarding time.
    static let boarding = ClockTime(17, 0)

    /// When stops start if the traveller adds any.
    static let planStart = ClockTime(16, 0)

    /// Walks recorded on the traveller's previous trips through Haneda (Figma "Previous trips").
    static let airportWalks = [
        AirportWalk(metres: 840, minutes: 12),
        AirportWalk(metres: 630, minutes: 9),
        AirportWalk(metres: 1050, minutes: 15),
    ]

    /// Number behind "Call ANA" in the Figma Journey details screen (858:13289).
    static let anaPhone = "+81367411120"
}
