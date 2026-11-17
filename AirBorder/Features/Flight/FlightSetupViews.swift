import SwiftUI

// MARK: - Shared pieces

/// Compact navy ticket used by Add a flight, Review flight, Your flights and the edit flow.
struct TicketSummary: View {
    let number: String
    var pill: String?
    var savedPill = false
    let from: String
    let to: String
    var departs: String?
    var arrives: String?
    var pills: [String] = []
    var airline: Airline? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    if let airline { AirlineBadge(airline: airline) }
                    Text(number).outfitText(16, .semibold, AB.ice)
                }
                Spacer()
                if savedPill {
                    HStack(spacing: 4) {
                        Image("savedCheck").resizable().frame(width: 12, height: 12)
                        Text("Saved").outfitText(12, .semibold, AB.mint)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(AB.green.opacity(0.18), in: Capsule())
                } else if let pill {
                    SummaryPill(text: pill, size: pills.isEmpty ? 14 : 12)
                }
            }
            HStack(alignment: .top) {
                end(from, departs, alignment: .leading)
                Spacer()
                Image("ticketArrow").resizable().frame(width: 20, height: 20).padding(.top, departs == nil ? 7 : 17)
                    .accessibilityHidden(true)
                Spacer()
                end(to, arrives, alignment: .trailing)
            }
            if !pills.isEmpty {
                HStack(spacing: 6) { ForEach(pills, id: \.self) { SummaryPill(text: $0, size: 12) } }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.ticket, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func end(_ code: String, _ time: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(code).outfitText(26, .bold, AB.ice)
            if let time { Text(time).outfitText(14, .semibold, AB.ice.opacity(0.8)) }
        }
    }
}

struct SummaryPill: View {
    let text: String
    var size: CGFloat = 12
    var body: some View {
        Text(text).outfitText(size, .semibold, AB.sky)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(AB.sky.opacity(0.18), in: Capsule())
    }
}

/// Centred 200 pt button used across the flight setup screens.
struct CenteredButton: View {
    let title: String
    var filled = true
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).outfitText(15, .semibold, filled ? .white : AB.navy)
                .padding(.horizontal, 20)
                .frame(minWidth: 200, minHeight: 52)
                .background(filled ? AB.primary : .white, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Back icon above a 30 pt title (Add a flight, Review flight, Baggage).
struct LargeTitleHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: back) {
                Image("icBack").resizable().frame(width: 26, height: 26).frame(width: 44, height: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("back")
            Text(title).outfitText(30, .bold).accessibilityAddTraits(.isHeader)
        }
        .padding(.bottom, 22)
    }
}

struct FlightStack<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, 18)
                .padding(.top, 0)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ListRow: View {
    let title: String
    var detail: String?
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).outfitText(16, .semibold)
                    if let detail { Text(detail).outfitText(13, .regular, AB.muted) }
                }
                Spacer()
                Image(selected ? "icCheckList" : "icRowArrow").resizable().frame(width: 16, height: 16)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: detail == nil ? 48 : 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Add a flight (858:10577)

struct AddFlightSummaryView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let trip = store.tripFlight
        let flight = store.outbound
        FlightStack {
            LargeTitleHeader(title: "Add a flight") { dismiss() }
            TicketSummary(number: trip.number, pill: flight.cabin, from: flight.from.code, to: flight.to.code,
                          pills: [flight.airline.name, TripDate.format(trip.date, "d MMM")], airline: flight.airline)
            CenteredButton(title: "Import ticket", identifier: "importTicket") { open(.importFlight) }
            CenteredButton(title: "Check flight details", filled: false) {
                store.beginEditingFlight()
                open(.editFlight)
            }
        }
    }
}

// MARK: - Your saved flights (858:12057)

struct SavedFlightsView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let trip = store.tripFlight
        let flight = store.outbound
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Your flights") { dismiss() }
            TicketSummary(number: trip.number, pill: flight.durationMinutes.map(durationText),
                          from: flight.from.code, to: flight.to.code, departs: flight.departs.description, arrives: flight.arrives.description,
                          pills: [TripDate.format(trip.date, "d MMM")], airline: flight.airline)
            if !store.manualFlights.isEmpty { ManualFlightsCard(flights: store.manualFlights) }
            CenteredButton(title: "Edit this flight") {
                store.beginEditingFlight()
                open(.editFlight)
            }
            CenteredButton(title: "Add another flight") { open(.importFlight) }
        }
    }
}

// MARK: - Edit flight details (858:11929) and choosers

struct EditFlightView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let draft = store.flightDraft
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Edit flight") { dismiss() }
            GroupedList {
                let leg = store.departure(number: draft.number)
                let title = leg.map { "\(draft.number), \($0.from.code) → \($0.to.code)" } ?? draft.number
                ListRow(title: title, detail: "Flight") { open(.chooseFlight) }
                RowDivider()
                ListRow(title: TripDate.format(draft.date, "d MMM yyyy"), detail: "Departure date") { open(.chooseDate) }
                RowDivider()
                ListRow(title: draft.purpose, detail: "Travel purpose") { open(.choosePurpose) }
            }
            CenteredButton(title: "Review flight", identifier: "reviewCorrected") { open(.checkFlight) }
        }
    }
}

struct ChooseFlightView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Choose flight") { dismiss() }
            GroupedList {
                ForEach(Array(store.availableDepartures.enumerated()), id: \.offset) { index, flight in
                    if index > 0 { RowDivider() }
                    ListRow(title: flight.number, detail: "\(flight.from.code) → \(flight.to.code)", selected: store.flightDraft.number == flight.number) {
                        store.flightDraft.number = flight.number
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ChooseDateView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Departure date") { dismiss() }
            GroupedList {
                ForEach(Array(store.availableTripDates.enumerated()), id: \.offset) { index, date in
                    if index > 0 { RowDivider() }
                    ListRow(title: TripDate.format(date, "d MMMM yyyy"), selected: store.flightDraft.date == date) {
                        store.flightDraft.date = date
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ChoosePurposeView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Travel purpose") { dismiss() }
            GroupedList {
                ForEach(Array(TripFlight.purposes.enumerated()), id: \.offset) { index, purpose in
                    if index > 0 { RowDivider() }
                    ListRow(title: purpose, selected: store.flightDraft.purpose == purpose) {
                        store.flightDraft.purpose = purpose
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Check corrected flight (858:12004) and Flight saved (858:12033)

struct CheckFlightView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.popTo) private var popTo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let draft = store.flightDraft
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Check flight details") { dismiss() }
            draftTicket(draft, leg: store.departure(number: draft.number), saved: false)
            Text("Local times. Check your ticket for baggage allowance.").outfitText(13, .regular, AB.muted)
            CenteredButton(title: "Save flight", identifier: "saveFlight") {
                store.saveFlightDraft()
                open(.flightSaved)
            }
            CenteredButton(title: "Cancel", filled: false) {
                store.beginEditingFlight()
                popTo(.savedFlights)
            }
        }
    }
}

struct FlightSavedView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.popTo) private var popTo

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            Color.clear.frame(height: 44)
            Text("Flight saved").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            Text("\(store.tripFlight.number) is now in Your flight.")
                .outfitText(15, .regular, AB.muted)
            draftTicket(store.tripFlight, leg: store.outbound, saved: true)
            CenteredButton(title: "View saved flights") { popTo(.savedFlights) }
        }
        .navigationBarBackButtonHidden()
    }
}

/// Display only the routing and timing data attached to the selected flight.
@ViewBuilder
private func draftTicket(_ trip: TripFlight, leg: FlightLeg?, saved: Bool) -> some View {
    TicketSummary(
        number: trip.number,
        pill: leg?.durationMinutes.map(durationText),
        savedPill: saved,
        from: leg?.from.code ?? "–",
        to: leg?.to.code ?? "–",
        departs: leg?.departs.description,
        arrives: leg?.arrives.description,
        pills: saved ? [TripDate.format(trip.date, "d MMM")] : [TripDate.format(trip.date, "d MMM"), trip.purpose],
        airline: leg?.airline
    )
}

// MARK: - Manual flight entry (858:13121, 858:13138, 858:13151)

struct ManualEntryView: View {
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var date = ""
    @State private var errors: (number: String?, date: String?) = (nil, nil)

    var body: some View {
        SubScreen(spacing: 16, top: 40) {
            StackedHeader(title: "Add a flight") { dismiss() }
            field("Flight number", hint: "e.g. BA123", text: $number, error: errors.number, id: "manualNumber", keyboard: .asciiCapable)
            field("Departure date", hint: "YYYY-MM-DD", text: $date, error: errors.date, id: "manualDate", keyboard: .numbersAndPunctuation)
            CenteredButton(title: "Review flight", identifier: "reviewEntered", action: review)
        }
    }

    private func field(_ label: String, hint: String, text: Binding<String>, error: String?, id: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).outfitText(15, .regular, AB.secondary)
            TextField("", text: text)
                .font(Outfit.font(20, .regular))
                .foregroundStyle(AB.navy)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 17)
                .frame(height: 52)
                .background(AB.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(error == nil ? AB.border : AB.removeRed, lineWidth: 1))
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
            Text(error ?? hint).outfitText(13, .regular, error == nil ? AB.secondary : AB.removeRed)
        }
        .padding(.bottom, 0)
    }

    private func review() {
        let cleaned = number.uppercased().filter { !$0.isWhitespace }
        let validNumber = cleaned.range(of: #"^[A-Z0-9]{2}[0-9]{1,4}[A-Z]?$"#, options: .regularExpression) != nil
        let trimmedDate = date.trimmingCharacters(in: .whitespaces)
        errors = (
            validNumber ? nil : "Enter the airline code and number, like BA123.",
            TripDate.isValid(trimmedDate) ? nil : "Enter the date as YYYY-MM-DD, like 2026-10-15."
        )
        guard errors.number == nil, errors.date == nil else { return }
        let spaced = String(cleaned.prefix(2)) + " " + String(cleaned.dropFirst(2))
        open(.reviewEntered(ManualFlight(number: spaced, date: trimmedDate)))
    }
}

struct ReviewEnteredView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss
    let flight: ManualFlight

    var body: some View {
        SubScreen(spacing: 16, top: 40) {
            StackedHeader(title: "Review flight") { dismiss() }
            VStack(alignment: .leading, spacing: 16) {
                labelled("Flight number", flight.number)
                labelled("Departure date", TripDate.format(flight.date, "d MMM yyyy"))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: 20))
            CenteredButton(title: "Save flight", identifier: "saveEntered") {
                store.addManualFlight(flight)
                open(.manualFlights)
            }
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).outfitText(12, .semibold, AB.sky)
            Text(value).outfitText(26, .bold, AB.ice)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ManualFlightsView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.popTo) private var popTo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 16, top: 40) {
            StackedHeader(title: "Your flights") { dismiss() }
            ManualFlightsCard(flights: store.manualFlights)
            CenteredButton(title: "Add another flight") { popTo(.manualEntry) }
        }
    }
}

struct ManualFlightsCard: View {
    let flights: [ManualFlight]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SAVED FLIGHTS").outfitText(12, .semibold, AB.sky)
            ForEach(flights) { flight in
                Text("\(flight.number), \(TripDate.format(flight.date, "d MMM yyyy"))").outfitText(20, .bold, AB.ice)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.ticket, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("manualFlights")
    }
}

// MARK: - Baggage (858:10639, 858:10672, 858:10683)

struct BaggageView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FlightStack {
            LargeTitleHeader(title: store.extraBagDeclared ? "Baggage updated" : "Baggage for this flight") { dismiss() }
            if !store.extraBagDeclared {
                TicketSummary(number: store.outbound.number, pill: store.outbound.cabin, from: store.outbound.from.code, to: store.outbound.to.code, airline: store.outbound.airline)
            }
            if let allowance = store.baggageAllowance {
                AllowanceCard(checked: store.extraBagDeclared ? allowance.extraChecked : allowance.checked,
                              cabin: allowance.cabin, note: store.extraBagDeclared ? "Includes 1 extra bag" : nil)
                if store.transferDetails != nil || (!store.isAirportTransfer && store.journey.presentation?.baggageTaggedThrough == true) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("BAG TAG").outfitText(12, .semibold, AB.muted)
                            Text(store.isAirportTransfer ? store.inbound.to.code : store.outbound.to.code).outfitText(22, .bold)
                        }
                        Rectangle().fill(AB.navy.opacity(0.12)).frame(width: 1, height: 40)
                        Text(baggageInstructions).outfitText(15, .regular, AB.muted)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AB.card, in: RoundedRectangle(cornerRadius: 14))
                }
                CenteredButton(title: store.extraBagDeclared ? "Edit extra baggage" : "Add extra baggage", identifier: "extraBaggage") {
                    open(.declareBaggage)
                }
            } else {
                Text("Baggage details unavailable. Check your ticket or ask your airline.")
                    .outfitText(15, .regular, AB.muted)
            }
        }
    }

    private var baggageInstructions: String {
        if let transfer = store.transferDetails {
            return "Collect at \(transfer.arrivalName) T\(store.inbound.arrivalTerminal) \(transfer.baggageCollectionFloor). Recheck at \(transfer.departureName) T\(store.outbound.departureTerminal) by \(transfer.recheckBy)."
        }
        return "Stays with the airline at \(store.inbound.to.shortName). Collect in \(store.outbound.to.city)."
    }
}

struct AllowanceCard: View {
    let checked: String
    let cabin: String
    var note: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Checked").outfitText(16, .semibold)
                Text(checked).outfitText(24, .bold)
                if let note { Text(note).outfitText(14, .semibold, Color(hex: 0x218047)).padding(.top, 6) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(AB.border).frame(width: 1).padding(.trailing, 20)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cabin + personal").outfitText(16, .semibold)
                Text(cabin).outfitText(24, .bold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct DeclareBaggageView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FlightStack {
            LargeTitleHeader(title: "Extra baggage") { dismiss() }
            if let allowance = store.baggageAllowance {
                VStack(alignment: .leading, spacing: 4) {
                    Text("+1 checked bag").outfitText(24, .bold)
                    Text("Up to \(allowance.extraBagLimit), \(store.outbound.number)").outfitText(15, .regular, AB.muted)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
                CenteredButton(title: store.extraBagDeclared ? "Remove extra bag" : "Save", identifier: "saveExtraBag") {
                    store.extraBagDeclared.toggle()
                    dismiss()
                }
            } else {
                Text("Baggage limits unavailable. Ask your airline about extra bags.")
                    .outfitText(15, .regular, AB.muted)
            }
        }
    }
}

// MARK: - Return flight (858:13081)

struct ReturnFlightView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    BackButton { dismiss() }
                    Spacer()
                    Text("Return flight").outfitText(18, .semibold).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                if let flight = store.returnFlight {
                    Text("RETURN FLIGHT, \(TripDate.format(flight.date, "d MMM").uppercased())").outfitText(12, .semibold, AB.muted).tracking(0.96)
                    TicketCard(flight: flight)
                    let arrivalDate = TripDate.adding(days: flight.arrivalDayOffset ?? 0, to: flight.date)
                    let arrival = arrivalDate.map { " Arrives \(TripDate.format($0, "d MMM"))." } ?? ""
                    let duration = flight.durationMinutes.map { " Flight time \(durationText($0))." } ?? ""
                    Text("Local times.\(arrival)\(duration)")
                        .outfitText(13, .regular, AB.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Return flight details unavailable.").outfitText(15, .regular, AB.muted)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}


extension JourneyStore {
    var baggageAllowance: BaggageAllowance? { journey.presentation?.baggage }
    var returnFlight: FlightLeg? { journey.presentation?.returnFlight }
    var flightContactPhone: String? { journey.presentation?.flightContactPhone }
}

extension TripDate {
    static func adding(days: Int, to iso: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = formatter.date(from: iso),
              let adjusted = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return formatter.string(from: adjusted)
    }
}
