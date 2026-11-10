import SwiftUI

/// Saved flights: the flights in the traveller's trip.
struct SavedFlightsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Saved flights").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            ForEach([SampleJourney.inbound, SampleJourney.outbound]) { flight in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        AirlineBadge(airline: flight.airline)
                        Text(flight.number).outfitText(15, .semibold)
                        Spacer()
                        Text(flight.status).outfitText(12, .semibold, AB.muted)
                    }
                    Text("\(flight.from.code) \(flight.departs) → \(flight.to.code) \(flight.arrives)").outfitText(18, .bold)
                    Text("\(flight.from.city) → \(flight.to.city)").outfitText(15, .regular, AB.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(AB.card, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct LanguageView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Language").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            GroupedList(radius: 16, bordered: true) {
                HStack {
                    Text("English").outfitText(15, .medium)
                    Spacer()
                    Image(systemName: "checkmark").foregroundStyle(AB.primary)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isSelected)
            }
            Text("Japanese and French are on the way.").outfitText(15, .regular, AB.secondary)
        }
    }
}

/// About AirBorder and Help & information. States where the trip data comes from.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("About AirBorder").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            InfoCard {
                Text("Your layover, planned to the minute").outfitText(18, .bold)
                Text("See how long you have, how to reach your gate, and what fits in between.")
                    .outfitText(15, .regular, AB.secondary)
            }
            InfoCard {
                Text("Where the details come from").outfitText(18, .bold)
                Text("The trip in this version is a saved sample journey through Tokyo Haneda. Flight times, gates, venues, queues and previous trips are not live.")
                    .outfitText(15, .regular, AB.secondary)
                Text("Walking times use your Apple Health walking speed when you connect it, and average walking times otherwise.")
                    .outfitText(15, .regular, AB.secondary)
            }
            .accessibilityIdentifier("dataSources")
        }
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Privacy").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            InfoCard {
                Text("Walking data").outfitText(18, .bold)
                Text("With your permission, AirBorder reads your walking speed from Apple Health to time your walks. It stays on this iPhone. Remove it anytime in Connected accounts, or change access in the Health app.")
                    .outfitText(15, .regular, AB.secondary)
            }
            InfoCard {
                Text("Camera").outfitText(18, .bold)
                Text("Camera view shows directions over what is in front of you. Frames stay on this iPhone.")
                    .outfitText(15, .regular, AB.secondary)
            }
        }
    }
}

struct EditProfileView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Edit profile").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                Text("Name").outfitText(13, .semibold, AB.muted)
                TextField("Your name", text: $name)
                    .font(Outfit.font(16, .regular))
                    .foregroundStyle(AB.navy)
                    .textContentType(.name)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(AB.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AB.border, lineWidth: 1))
                    .accessibilityIdentifier("nameField")
            }
            CTAButton(title: "Save") {
                store.travellerName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                dismiss()
            }
        }
        .onAppear { name = store.travellerName }
    }
}

/// Figma onboarding (858:8332). Runs once; Profile › Replay tutorial shows it again.
struct TutorialView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss
    var onFinish: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(action: finish) {
                    Text("Skip").outfitText(14, .semibold, .white).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            Text("Your layover, planned to the minute.").outfitText(36, .bold, .white)
                .frame(maxWidth: 270, alignment: .leading)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
            Text("See how long you have, how to reach your gate, and what fits in between!")
                .outfitText(15, .regular, .white)
                .padding(.top, 14)
            journeyArc.padding(.top, 110)
            Spacer()
            CTAButton(title: "Continue", style: .light, height: 52, action: finish)
                .accessibilityIdentifier("tutorialContinue")
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 24)
        .background(AB.primary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var journeyArc: some View {
        HStack(alignment: .bottom) {
            stop("Departure", bold: false)
            Spacer()
            stop("Layover", bold: true)
            Spacer()
            stop("Destination", bold: false)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 0) {
                Image("pathFlown").resizable().frame(height: 46)
                Image("pathNextLeg").resizable().frame(height: 46).opacity(0.7)
            }
            .padding(.horizontal, 24)
            .offset(y: -44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Departure, layover, destination")
    }

    private func stop(_ label: String, bold: Bool) -> some View {
        VStack(spacing: 10) {
            Circle().fill(.white).frame(width: bold ? 12 : 8, height: bold ? 12 : 8)
            Text(label).outfitText(15, bold ? .semibold : .regular, .white.opacity(bold ? 1 : 0.85))
        }
    }

    private func finish() {
        store.onboardingSeen = true
        if let onFinish { onFinish() } else { dismiss() }
    }
}

/// Figma "Add a flight" (858:11655).
struct AddFlightView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var unavailable: String?
    @State private var entersManually = false
    @State private var flightNumber = ""
    @State private var result: String?

    private struct Source: Identifiable {
        var id: String { title }
        let title: String
        let detail: String
        let icon: String?
        let symbol: String?
    }

    private let sources = [
        Source(title: "Camera", detail: "Scan your ticket", icon: nil, symbol: "camera"),
        Source(title: "PDF", detail: "PDF ticket or itinerary", icon: nil, symbol: "doc.text"),
        Source(title: "Apple Wallet", detail: "Boarding pass", icon: nil, symbol: "wallet.pass"),
        Source(title: "Google Wallet", detail: "Boarding pass", icon: nil, symbol: "creditcard"),
        Source(title: "Gmail", detail: "Booking email", icon: "logoGmail", symbol: nil),
        Source(title: "Google Calendar", detail: "Flight event", icon: "logoGoogleCalendar", symbol: nil),
    ]

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Add a flight").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            Text("Where is your ticket?").outfitText(15, .regular, AB.secondary)
            GroupedList(radius: 16, bordered: true) {
                ForEach(sources) { source in
                    row(source.title, source.detail) {
                        if let icon = source.icon {
                            Image(icon).resizable().scaledToFit().frame(width: source.title == "Gmail" ? 20 : 32, height: source.title == "Gmail" ? 16 : 32)
                        } else if let symbol = source.symbol {
                            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(AB.navy)
                        }
                    } perform: { unavailable = source.title }
                    RowDivider()
                }
                row("Add manually", "Enter flight number") {
                    Image("icPlusDark").resizable().frame(width: 18, height: 18)
                } perform: { entersManually = true }
                .accessibilityIdentifier("addManually")
            }
            if entersManually {
                TextField("Flight number, e.g. NH 106", text: $flightNumber)
                    .font(Outfit.font(16, .regular))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(find)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(AB.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AB.border, lineWidth: 1))
                    .accessibilityIdentifier("flightNumberField")
                CTAButton(title: "Find flight", action: find)
                if let result {
                    Text(result).outfitText(15, .regular, result.hasPrefix("Enter") || result.hasPrefix("We") ? AB.removeRed : AB.secondary)
                        .accessibilityIdentifier("addFlightResult")
                }
            }
        }
        .alert(
            "\(unavailable ?? "") isn't available yet",
            isPresented: Binding(get: { unavailable != nil }, set: { if !$0 { unavailable = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use Add manually to enter your flight number.")
        }
    }

    private func row<Icon: View>(_ title: String, _ detail: String, @ViewBuilder icon: () -> Icon, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 14) {
                icon()
                    .frame(width: 32, height: 32)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0xDEE5EB), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).outfitText(16, .semibold)
                    Text(detail).outfitText(13, .regular, AB.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image("icRowArrow").resizable().frame(width: 16, height: 16)
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func find() {
        let entered = flightNumber.uppercased().filter { !$0.isWhitespace }
        guard !entered.isEmpty else {
            result = "Enter a flight number, like NH 106."
            return
        }
        let saved = [SampleJourney.inbound, SampleJourney.outbound]
        if let match = saved.first(where: { $0.number.filter { !$0.isWhitespace } == entered }) {
            result = "\(match.number) is already in your trip."
        } else {
            result = "We couldn't find \(flightNumber.uppercased()). Check the number on your ticket."
        }
    }
}
