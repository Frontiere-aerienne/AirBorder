import SwiftUI

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
                    if let routeImage = transfer.routeImage {
                        Image(routeImage).resizable().scaledToFit().frame(maxWidth: .infinity).accessibilityHidden(true)
                    }
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
