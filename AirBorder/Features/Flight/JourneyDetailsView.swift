import SwiftUI

/// Figma "Journey details" (858:13224) with the checkpoint line (1034:17020).
struct JourneyDetailsView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showsTransferBaggage = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    BackButton { dismiss() }
                    Spacer()
                    Text("Journey details").outfitText(18, .semibold).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.bottom, 8)
                if let condition = store.primaryCondition {
                    TravelUpdateBanner(condition: condition, place: .details)
                }
                legLabel("FLIGHT 1 OF 2")
                InboundCard(flight: SampleJourney.inbound)
                layover
                legLabel("FLIGHT 2 OF 2")
                TicketCard(flight: store.outbound, status: store.flightStatus, gate: store.gate)
                Color.clear.frame(height: 24)
                CTAButton(title: "Baggage for this flight", height: 52, fullWidth: false) {
                    if store.isAirportTransfer { showsTransferBaggage = true } else { open(.baggage) }
                }
                    .frame(width: 216)
                CTAButton(title: "View return flight", height: 52, fullWidth: false) { open(.returnFlight) }
                    .frame(width: 206)
                    .accessibilityIdentifier("viewReturnFlight")
                Button {
                    if let url = URL(string: "tel:\(SampleJourney.anaPhone)") { openURL(url) }
                } label: {
                    HStack(spacing: 8) {
                        Image("icPhone").resizable().frame(width: 18, height: 18)
                        Text("Call ANA").outfitText(14, .semibold, AB.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("callANA")
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsTransferBaggage) { TransferBaggageSheet() }
    }

    private func legLabel(_ text: String) -> some View {
        Text(text).outfitText(12, .semibold, AB.muted).tracking(0.96)
    }

    private var layover: some View {
        HStack(spacing: 12) {
            Rectangle().fill(AB.primary.opacity(0.3)).frame(width: 2)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(durationText(store.layoverMinutes)).outfitText(14, .medium, AB.muted)
                    Text(store.isAirportTransfer ? "layover, change to Narita" : "layover at \(SampleJourney.haneda.city)").outfitText(14, .regular, AB.muted)
                }
                JourneyProgressStrip(checklist: store.checklist)
                    .padding(.top, 4)
                Button { open(.journeySteps) } label: {
                    Text("See all steps →").outfitText(14, .semibold, AB.primary)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("checkpointLine")
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 24)
        .padding(.vertical, 11)
    }
}

/// White card for the arrived inbound flight (Figma "Flight 1", 858:13233).
private struct InboundCard: View {
    let flight: FlightLeg

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    AirlineBadge(airline: flight.airline)
                    Text(flight.number).outfitText(15, .semibold)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image("icCheckSmall").resizable().frame(width: 13, height: 13)
                    Text(flight.status).outfitText(12, .semibold, AB.muted).tracking(0.2)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AB.tagGrey, in: RoundedRectangle(cornerRadius: 6))
            }
            HStack(spacing: 10) {
                end(flight.from, flight.departs, alignment: .leading)
                ZStack {
                    Image("pathFlownLight").resizable().frame(height: 16).padding(.horizontal, 4.5).offset(y: -4)
                    HStack {
                        Image("pathDotLight").resizable().frame(width: 9, height: 9)
                        Spacer()
                        Image("pathDotLight").resizable().frame(width: 9, height: 9)
                    }
                    .offset(y: 11)
                }
                .frame(height: 30)
                .accessibilityHidden(true)
                end(flight.to, flight.arrives, alignment: .trailing)
            }
            ZStack {
                Image("ticketTearLineLight").resizable().frame(height: 1)
                HStack {
                    Image("ticketNotchLight").resizable().frame(width: 16, height: 16).offset(x: -28)
                    Spacer()
                    Image("ticketNotchLight").resizable().frame(width: 16, height: 16).offset(x: 28)
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            HStack {
                GateSign(gate: flight.departureGate)
                Spacer()
                TerminalSign(terminal: flight.arrivalTerminal)
                GateSign(gate: flight.arrivalGate, direction: .arrival)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
    }

    private func end(_ airport: Airport, _ time: ClockTime, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text("\(airport.code) \(time)").outfitText(18, .bold).tracking(-0.3)
            Text(airport.city).outfitText(12, .regular, AB.secondary)
        }
        .fixedSize()
    }
}
