import SwiftUI

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
    let routeImage: String
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

extension JourneyStore {
    var transferDetails: AirportTransferDetails? { journey.transfer }

    var transferArrivalName: String { transferDetails?.arrivalName ?? inbound.to.shortName }
    var transferDepartureName: String { transferDetails?.departureName ?? outbound.from.shortName }
}

/// Flight tab "Your plan" area for the transfer (Figma 858:9828).
struct TransferPlanSection: View {
    @EnvironmentObject private var store: JourneyStore
    @State private var showsSteps = false
    @State private var showsBag = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let closes = store.outbound.gateCloses, store.transferDetails?.comparesWithJourneyClock == true {
                HStack(spacing: 6) {
                    TimeChip(text: durationText(closes - store.now))
                    Text("before \(store.transferDepartureName) gate closes.").outfitText(22, .regular, AB.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("transferCountdown")
            } else if let closes = store.outbound.gateCloses {
                Text("Departure gate closes at \(closes), local time.")
                    .outfitText(15, .regular, AB.muted)
            }
            if store.transferDetails != nil {
                Button { showsSteps = true } label: {
                    HStack(spacing: 9) {
                        Image("icTransferWhite").resizable().frame(width: 21, height: 21)
                        Text("Route").outfitText(14, .semibold, .white)
                    }
                    .frame(width: 222, height: 47)
                    .background(AB.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("routeButton")
            }
            Text("\(store.inbound.to.code) → \(store.outbound.from.code), ground transfer").outfitText(17, .semibold)
                .padding(.top, 8)
            VStack(spacing: 0) {
                if let transfer = store.transferDetails {
                    Button { showsBag = true } label: {
                        row("tileBag", "Baggage, collect at \(store.inbound.to.code)",
                            "Bag tag: \(store.inbound.to.code), recheck at \(transfer.departureName) T\(store.outbound.departureTerminal)")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("transferBag")
                    RowDivider()
                    row("tileShield", transfer.entryLabel, transfer.entryInstruction)
                    RowDivider()
                    row("tileMap", "\(transfer.transportName), \(transfer.departs)",
                        "\(store.outbound.from.code) T\(store.outbound.departureTerminal) arrival \(transfer.arrives), fare \(transfer.fare)")
                } else {
                    row("tileMap", "Transfer directions unavailable",
                        "Check the airports’ transport information and confirm baggage and check-in requirements with your airline.")
                }
            }
            .background(AB.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AB.border, lineWidth: 1))
            .accessibilityIdentifier("beforeYouTransfer")
        }
        .sheet(isPresented: $showsSteps) { TransferStepsSheet() }
        .sheet(isPresented: $showsBag) { TransferBaggageSheet() }
    }

    private func row(_ icon: String, _ label: String, _ detail: String) -> some View {
        HStack(spacing: 16) {
            Image(icon).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).outfitText(15, .semibold)
                Text(detail).outfitText(13, .regular, AB.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .accessibilityElement(children: .combine)
    }
}

/// Figma "Transfer steps" sheet (858:10234).
struct TransferStepsSheet: View {
    @EnvironmentObject private var store: JourneyStore

    var body: some View {
        if let transfer = store.transferDetails {
            InfoSheet(
                title: "\(transfer.arrivalName) to \(transfer.departureName)",
                rows: [
                    SheetRow(icon: "tileBag", label: "Collect your bag", detail: "Terminal \(store.inbound.arrivalTerminal), \(transfer.baggageCollectionFloor)"),
                    SheetRow(icon: "tileBus", label: transfer.transportName, detail: "\(transfer.departs) to \(transfer.arrives), \(transfer.fare)"),
                    SheetRow(icon: "tileTransfer", label: "Recheck at \(transfer.departureName)", detail: "Terminal \(store.outbound.departureTerminal) by \(transfer.recheckBy), gate closes \(store.outbound.gateCloses?.description ?? "–")"),
                ],
                link: ("Travel documents", transfer.documentsURL)
            )
        } else {
            InfoSheet(title: "Airport transfer", rows: [
                SheetRow(icon: "tileMap", label: "Transfer directions unavailable", detail: "Check official airport transport information.")
            ])
        }
    }
}

/// Figma "Baggage (Transfer)" sheet (858:10176), from Journey details › Baggage for this flight.
struct TransferBaggageSheet: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open

    var body: some View {
        InfoSheet(
            title: "Your bag",
            rows: details,
            button: ("Baggage for this flight", { open(.baggage) })
        )
    }

    private var details: [SheetRow] {
        guard let transfer = store.transferDetails else {
            return [SheetRow(icon: "tileInfo", label: "Baggage details unavailable", detail: "Confirm collection and recheck instructions with your airline.")]
        }
        return [
            SheetRow(icon: "tileBag", label: "Collect at \(transfer.arrivalName)", detail: "Terminal \(store.inbound.arrivalTerminal), \(transfer.baggageCollectionFloor)"),
            SheetRow(icon: "tileTransfer", label: "Recheck at \(transfer.departureName)", detail: "Terminal \(store.outbound.departureTerminal), by \(transfer.recheckBy)"),
        ] + (store.baggageAllowance.map {
            [SheetRow(icon: "tileInfo", label: "Allowance", detail: "\($0.checked) checked, \($0.cabin) cabin")]
        } ?? [])
    }
}

/// Route tab for ground transfers (Figma 858:9995).
struct TransferRouteContent: View {
    @EnvironmentObject private var store: JourneyStore

    var body: some View {
        let flight = store.outbound
        let inbound = store.inbound
        VStack(alignment: .leading, spacing: 14) {
            if let transfer = store.transferDetails {
                card {
                    Text("\(transfer.arrivalName) → \(transfer.departureName)").outfitText(22, .bold)
                    Text([transfer.transportName, transfer.durationLabel, transfer.fare].compactMap { $0 }.joined(separator: ", ")).outfitText(14, .regular, AB.muted)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(inbound.to.code), Terminal \(inbound.arrivalTerminal)").outfitText(18, .bold)
                        Text("\(transfer.departs) departure, \(transfer.departureLocation)").outfitText(14, .regular, AB.muted)
                    }
                    Image(transfer.routeImage).resizable().scaledToFit().frame(maxWidth: .infinity).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(flight.from.code), Terminal \(flight.departureTerminal)").outfitText(18, .bold)
                        Text("\(transfer.arrives) arrival, \(flight.number) departs at \(flight.departs)").outfitText(14, .regular, AB.muted)
                    }
                }
                .accessibilityIdentifier("transferOverview")
                card {
                    Text("Your checked bag").outfitText(18, .bold)
                    Text("Collect at \(transfer.arrivalName). Recheck at \(transfer.departureName) by \(transfer.recheckBy).").outfitText(14, .regular, AB.muted)
                }
                Text("All times are local, \(transfer.zoneLabel)").outfitText(14, .regular, AB.muted)
                card {
                    Text("Your airport transfer").outfitText(22, .bold)
                    stage(1, "Collect your bag at \(transfer.arrivalName)", "Arrive \(inbound.to.code) T\(inbound.arrivalTerminal) at \(inbound.arrives). \(transfer.arrivalInstruction)")
                    stage(2, "Go to the \(transfer.transportName.lowercased())", "\(transfer.groundDepartureInstruction) Departs \(transfer.departs), \(transfer.fare).")
                    let duration = transfer.durationLabel.map { ", \($0)" } ?? ""
                    stage(3, "Ride to \(transfer.departureName) Terminal \(flight.departureTerminal)",
                          "\(transfer.departs)–\(transfer.arrives)\(duration) on the \(transfer.transportName.lowercased()).")
                    stage(4, "Recheck your bag", "At \(flight.from.code) T\(flight.departureTerminal), check in for \(flight.number) and recheck your bag by \(transfer.recheckBy).")
                    stage(5, "Go to your departure gate", "\(transfer.boardingInstruction) Gate closes \(flight.gateCloses?.description ?? "–"), Flight departs \(flight.departs).")
                }
                .padding(.top, 10)
            } else {
                card {
                    Text("\(inbound.to.code) → \(flight.from.code)").outfitText(22, .bold)
                    Text("Transfer directions unavailable").outfitText(18, .bold)
                    Text("Check official airport transport information and confirm your flight’s check-in and baggage rules.").outfitText(14, .regular, AB.muted)
                }
                .accessibilityIdentifier("transferOverview")
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private func stage(_ number: Int, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(number)  \(title)").outfitText(17, .bold)
            Text(detail).outfitText(14, .regular, AB.muted).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
