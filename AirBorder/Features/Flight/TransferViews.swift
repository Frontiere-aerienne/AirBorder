import SwiftUI

/// Haneda → Narita ground transfer for NH 6 (Figma section "Transfer HND → NRT").
enum NaritaTransfer {
    static let busDeparts = ClockTime(13, 10)
    static let busArrives = ClockTime(14, 45)
    static let fare = "JPY 3,600"
    /// Check in and recheck the bag at Narita Terminal 1 by this time.
    static let recheckBy = ClockTime(20, 0)
    static var busMinutes: Int { busArrives - busDeparts }
    static let documentsURL = "https://www.mofa.go.jp/j_info/visit/visa/index.html"
}

/// Flight tab "Your plan" area for the transfer (Figma 858:9828).
struct TransferPlanSection: View {
    @EnvironmentObject private var store: JourneyStore
    @State private var showsSteps = false
    @State private var showsBag = false

    var body: some View {
        let closes = store.outbound.gateCloses ?? store.outbound.departs
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                TimeChip(text: durationText(closes - store.now))
                Text("before Narita gate closes.").outfitText(22, .regular, AB.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("transferCountdown")
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
            Text("HND → NRT, ground transfer").outfitText(17, .semibold)
                .padding(.top, 8)
            VStack(spacing: 0) {
                Button { showsBag = true } label: {
                    row("tileBag", "Baggage, collect at HND", "Bag tag: HND, recheck at Narita T1")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("transferBag")
                RowDivider()
                row("tileShield", "Entry document, Japan", "Japanese ePassport, expires 12 Jun 2031")
                RowDivider()
                row("tileMap", "Airport bus, \(NaritaTransfer.busDeparts)", "NRT T1 arrival \(NaritaTransfer.busArrives), fare \(NaritaTransfer.fare)")
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
        InfoSheet(
            title: "Haneda to Narita",
            rows: [
                SheetRow(icon: "tileBag", label: "Collect your bag", detail: "Terminal \(SampleJourney.inbound.arrivalTerminal), 2F"),
                SheetRow(icon: "tileBus", label: "Airport bus", detail: "\(NaritaTransfer.busDeparts) to \(NaritaTransfer.busArrives), \(NaritaTransfer.fare)"),
                SheetRow(icon: "tileTransfer", label: "Recheck at Narita", detail: "Terminal \(store.outbound.departureTerminal) by \(NaritaTransfer.recheckBy), gate closes \(store.outbound.gateCloses?.description ?? "–")"),
            ],
            link: ("Travel documents", NaritaTransfer.documentsURL)
        )
    }
}

/// Figma "Baggage (Transfer)" sheet (858:10176), from Journey details › Baggage for this flight.
struct TransferBaggageSheet: View {
    @EnvironmentObject private var store: JourneyStore

    var body: some View {
        InfoSheet(
            title: "Your bag",
            rows: [
                SheetRow(icon: "tileBag", label: "Collect at Haneda", detail: "Terminal \(SampleJourney.inbound.arrivalTerminal), 2F"),
                SheetRow(icon: "tileTransfer", label: "Recheck at Narita", detail: "Terminal \(store.outbound.departureTerminal), by \(NaritaTransfer.recheckBy)"),
                SheetRow(icon: "tileInfo", label: "Allowance", detail: "1 × 32 kg checked, 10 kg cabin"),
            ],
            button: ("Update baggage preference", { store.tab = .profile })
        )
    }
}

/// Route tab for the transfer: "Route to Narita" (Figma 858:9995).
struct TransferRouteContent: View {
    @EnvironmentObject private var store: JourneyStore

    /// Figma ground-transport steps (858:11315, 858:11335, 858:11375).
    static let steps = ["Follow Bus signs", "Continue to the 1F buses", "Stop 5, Narita Airport"]

    var body: some View {
        let flight = store.outbound
        VStack(alignment: .leading, spacing: 14) {
            card {
                Text("Haneda → Narita").outfitText(22, .bold)
                Text("Airport bus, \(NaritaTransfer.busMinutes) min, \(NaritaTransfer.fare)").outfitText(14, .regular, AB.muted)
                VStack(alignment: .leading, spacing: 8) {
                    Text("HND, Terminal \(SampleJourney.inbound.arrivalTerminal)").outfitText(18, .bold)
                    Text("\(NaritaTransfer.busDeparts) departure, 1F bus stops").outfitText(14, .regular, AB.muted)
                }
                Image("busRouteHNDNRT").resizable().scaledToFit().frame(maxWidth: .infinity).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("NRT, Terminal \(flight.departureTerminal)").outfitText(18, .bold)
                    Text("\(NaritaTransfer.busArrives) arrival, \(flight.number) departs at \(flight.departs)").outfitText(14, .regular, AB.muted)
                }
            }
            .accessibilityIdentifier("transferOverview")
            card {
                Text("Your checked bag").outfitText(18, .bold)
                Text("Collect at Haneda. Recheck at Narita by \(NaritaTransfer.recheckBy).").outfitText(14, .regular, AB.muted)
            }
            Text("All times are local, JST").outfitText(14, .regular, AB.muted)
            card {
                Text("Your airport transfer").outfitText(22, .bold)
                stage(1, "Collect your bag at Haneda", "Arrive HND T\(SampleJourney.inbound.arrivalTerminal) at \(SampleJourney.inbound.arrives). Go through passport control, collect your bag, then pass through customs.")
                stage(2, "Go to the airport bus", "Follow the Bus signs from the 2F access hall to the 1F bus stops. Departs \(NaritaTransfer.busDeparts), \(NaritaTransfer.fare).")
                stage(3, "Ride to Narita Terminal \(flight.departureTerminal)", "\(NaritaTransfer.busDeparts)–\(NaritaTransfer.busArrives), \(NaritaTransfer.busMinutes) min on the airport bus.")
                stage(4, "Recheck your bag", "At NRT T\(flight.departureTerminal), check in for \(flight.number) and recheck your bag by \(NaritaTransfer.recheckBy).")
                stage(5, "Go to your departure gate", "Pass through security and departure passport control. Gate closes \(flight.gateCloses?.description ?? "–"), Flight departs \(flight.departs).")
            }
            .padding(.top, 10)
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
