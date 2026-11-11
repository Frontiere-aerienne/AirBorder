import SwiftUI

/// Navy flight ticket with the "Ticket pass" (Figma 862:16342).
/// With `previous`, the route row shows the whole trip (BKK → HND → LAX) as on the Flight tab.
struct TicketCard: View {
    let flight: FlightLeg
    var previous: FlightLeg?
    /// Live values from the flight-status feed, when they differ from the ticket.
    var status: String?
    var gate: String?

    var body: some View {
        VStack(alignment: .leading, spacing: previous == nil ? 18 : 8) {
            header
            if let previous {
                tripRoute(previous)
            } else {
                legRoute
            }
            pass
        }
        .padding(previous == nil ? 22 : 24)
        .background(AB.ticket, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ticket-\(flight.id)")
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                AirlineBadge(airline: flight.airline)
                Text(flight.number).outfitText(16, .semibold, AB.ice)
            }
            Spacer()
            Text(status ?? flight.status).outfitText(12, .semibold, AB.sky)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AB.sky.opacity(0.18), in: Capsule())
        }
    }

    /// BKK → HND → LAX with the flown leg and the next leg.
    private func tripRoute(_ previous: FlightLeg) -> some View {
        VStack(spacing: 4) {
            ZStack {
                HStack(spacing: 0) {
                    Image("pathFlown").resizable().frame(height: 20.4)
                    Image("pathNextLeg").resizable().frame(height: 20.85)
                }
                .padding(.horizontal, 16)
                Image("icPlane").resizable().frame(width: 18, height: 18).rotationEffect(.degrees(34.67))
            }
            .frame(height: 34)
            .accessibilityHidden(true)
            HStack(alignment: .bottom) {
                airport(previous.from, size: 18, alignment: .leading, dimmed: true)
                Spacer()
                if previous.to.code != flight.from.code {
                    VStack(alignment: .center, spacing: 4) {
                        Text("\(previous.to.code) → \(flight.from.code)").outfitText(22, .bold, AB.ice)
                        Text("Airport transfer").outfitText(13, .regular, AB.ice.opacity(0.6))
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    airport(flight.from, size: 30, alignment: .center, dimmed: false)
                }
                Spacer()
                airport(flight.to, size: 30, alignment: .trailing, dimmed: false)
            }
        }
    }

    /// HND → LAX on Journey details (Figma 858:13261).
    private var legRoute: some View {
        HStack(spacing: 12) {
            airport(flight.from, size: 44, alignment: .leading, dimmed: false, cityColor: AB.ice.opacity(0.55), citySize: 15)
            ZStack(alignment: .topLeading) {
                Image("pathDotDark").resizable().frame(width: 9, height: 9).offset(y: 26.5)
                Image("pathNextLeg").resizable().frame(height: 19).padding(.horizontal, 4.5).offset(y: 12)
                Image("icPlane").resizable().frame(width: 18, height: 18).rotationEffect(.degrees(34.67)).offset(x: 12, y: 12)
                HStack { Spacer(); Image("pathDotDark").resizable().frame(width: 9, height: 9) }.offset(y: 26.5)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            airport(flight.to, size: 44, alignment: .trailing, dimmed: false, cityColor: AB.ice.opacity(0.55), citySize: 15)
        }
    }

    private func airport(_ airport: Airport, size: CGFloat, alignment: HorizontalAlignment, dimmed: Bool, cityColor: Color = AB.ice.opacity(0.55), citySize: CGFloat = 12) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(airport.code).outfitText(size, .bold, dimmed ? AB.ice.opacity(0.6) : AB.ice)
                .tracking(size >= 44 ? -1.5 : 0)
            Text(airport.city).outfitText(citySize, .regular, dimmed ? AB.ice : cityColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(airport.code), \(airport.city)")
    }

    private var pass: some View {
        VStack(alignment: .leading, spacing: 12) {
            perforation
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DEPARTS").outfitText(11, .medium, AB.sky).tracking(0.88)
                    Text(flight.departs.description).outfitText(30, .bold, AB.ice)
                    if previous == nil, let closes = flight.gateCloses {
                        Text("Gate closes \(closes)").outfitText(13, .regular, AB.ice.opacity(0.7))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if flight.departureGate.isEmpty {
                        TerminalSign(terminal: flight.departureTerminal, size: 26)
                    } else {
                        GateSign(gate: gate ?? flight.departureGate, size: 26, previous: gate.flatMap { $0 == flight.departureGate ? nil : flight.departureGate })
                        if !flight.departureTerminal.isEmpty {
                            Text("Terminal \(flight.departureTerminal)").outfitText(13, .medium, AB.ice.opacity(0.7))
                        }
                    }
                }
            }
            Rectangle().fill(AB.ice.opacity(0.12)).frame(height: 1)
            HStack(alignment: .top) {
                detail("ARRIVES", flight.arrives.description + (flight.arrivalDayOffset.map { " +\($0)" } ?? ""))
                Spacer()
                detail("TERMINAL", flight.arrivalTerminal)
                Spacer()
                detail("GATE", flight.arrivalGate)
                Spacer()
                detail("BAGS", flight.baggageBelt ?? "–")
            }
        }
    }

    private var perforation: some View {
        let inset: CGFloat = previous == nil ? 22 : 24
        return ZStack {
            Image("ticketTearLine").resizable().frame(height: 1)
            HStack {
                Image("ticketNotch").resizable().frame(width: 20, height: 20).offset(x: -inset - 10)
                Spacer()
                Image("ticketNotch").resizable().frame(width: 20, height: 20).offset(x: inset + 10)
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).outfitText(10, .medium, AB.sky.opacity(0.8)).tracking(0.8)
            Text(value).outfitText(16, .semibold, AB.ice.opacity(0.9))
        }
        .accessibilityElement(children: .combine)
    }
}
