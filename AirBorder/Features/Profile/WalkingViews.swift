import SwiftUI

/// Figma "Connected accounts" (858:11910) and its Apple Health states (1030:16899, 1030:16937).
struct ConnectedAccountsView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Connected accounts") { dismiss() }
            SectionLabel(text: "Flight import")
            GroupedList {
                AccountRow(title: "Gmail", detail: "Not connected, view only", action: "Connect") {
                    BrandTile(asset: "logoGmail", width: 20, height: 15.9)
                } perform: { open(.connectGmail) }
                RowDivider()
                AccountRow(title: "Google Calendar", detail: "Not connected, view only", action: "Connect") {
                    Image("logoGoogleCalendar").resizable().scaledToFit().frame(width: 32, height: 32)
                } perform: { open(.connectCalendar) }
            }
            SectionLabel(text: "Walking data")
            GroupedList {
                AccountRow(
                    title: "Apple Health",
                    detail: healthDetail,
                    action: store.health == .connected ? "Remove" : "Connect",
                    actionColor: store.health == .connected ? AB.removeRed : AB.primary
                ) {
                    Image("icWalkTile").resizable().frame(width: 20, height: 20)
                        .frame(width: 32, height: 32)
                        .background(AB.primary, in: RoundedRectangle(cornerRadius: 8))
                } perform: {
                    open(store.health == .connected ? .removeHealth : .healthPermission)
                }
                .accessibilityIdentifier("appleHealthRow")
            }
        }
    }

    private var healthDetail: String {
        switch store.health {
        case .connected:
            guard store.walkingSpeedKmh != nil else { return "Speed and distance · No walks yet" }
            if let sync = store.lastHealthSync, Date().timeIntervalSince(sync) > 60 {
                return "Speed and distance · Synced \(sync.formatted(date: .omitted, time: .shortened))"
            }
            return "Speed and distance · Synced just now"
        case .removed: return "Removed · Using average times"
        case .notConnected: return store.healthAvailable ? "Not connected" : "Not available on this device"
        }
    }
}

private struct BrandTile: View {
    let asset: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Image(asset).resizable().frame(width: width, height: height)
            .frame(width: 32, height: 32)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0xDEE5EB), lineWidth: 1))
    }
}

private struct AccountRow<Icon: View>: View {
    let title: String
    let detail: String
    let action: String
    var actionColor: Color = AB.primary
    @ViewBuilder let icon: Icon
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            icon.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).outfitText(16, .semibold)
                Text(detail).outfitText(13, .regular, AB.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: perform) {
                Text(action).outfitText(15, .semibold, actionColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(action) \(title)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// Figma "Remove Apple Health" (1030:16976).
struct RemoveHealthView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Remove Apple Health?").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            InfoCard {
                Text("Stop sharing walking data").outfitText(18, .bold)
                Text("Estimates will use your airport walks or average times.").outfitText(15, .regular, AB.secondary)
            }
            CTAButton(title: "Remove", style: .destructive) {
                store.removeHealth()
                dismiss()
            }
            .accessibilityIdentifier("confirmRemoveHealth")
            Button { dismiss() } label: {
                Text("Keep connected").outfitText(13, .regular)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().strokeBorder(AB.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Figma "Airport walking" (997:31920) and "Average estimate" (997:31940).
/// Pace is read from the connected Apple Health account; it is never labelled slow or fast.
struct AirportWalkingView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Airport walking").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            if case let .personal(kmh) = store.pace {
                InfoCard {
                    Text("Your average pace").outfitText(14, .semibold, AB.secondary)
                    Text(PaceText.kmh(kmh)).outfitText(32, .bold).accessibilityIdentifier("paceValue")
                    Text(source).outfitText(15, .regular, AB.secondary)
                }
                if !healthUsed {
                    CTAButton(title: "Connect walking data") { open(.connectedAccounts) }
                }
            } else {
                InfoCard {
                    Text("No personal walking data").outfitText(18, .bold)
                    Text("Using average walking times").outfitText(15, .regular, AB.secondary)
                }
                .accessibilityIdentifier("averagePace")
                CTAButton(title: "Connect walking data") { open(.connectedAccounts) }
            }
        }
    }
}

extension AirportWalkingView {
    private var healthUsed: Bool { store.health == .connected && store.walkingSpeedKmh != nil }

    private var source: String {
        let walks = SampleJourney.airportWalks.count
        if walks == 0 { return "From Apple Health" }
        return healthUsed ? "From \(walks) airport walks and Apple Health" : "From \(walks) airport walks · walking only"
    }
}

/// Figma "Health permission" (997:31930).
struct HealthPermissionView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Connect walking data").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            InfoCard {
                Text("Walking speed and distance").outfitText(18, .bold)
                Text("You can disconnect at any time.").outfitText(15, .regular, AB.secondary)
            }
            CTAButton(title: "Allow walking data") {
                Task {
                    await store.connectHealth()
                    dismiss()
                }
            }
            .accessibilityIdentifier("allowWalkingData")
            Button { dismiss() } label: {
                Text("Continue without connecting").outfitText(13, .regular)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().strokeBorder(AB.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Figma "Previous trips" (997:31915).
struct PreviousTripsView: View {
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss

    private struct Trip: Identifiable {
        let id = UUID()
        let date: String
        let gate: String?
        let gateDirection: SignDirection
        let flight: String
        let walk: String
    }

    private let trips = [
        Trip(date: "12 Aug 2026", gate: "105", gateDirection: .departure, flight: "NH 106 · HND → LAX", walk: "Haneda · 12 min walk · 840 m"),
        Trip(date: "3 Jun 2026", gate: "108A", gateDirection: .departure, flight: "NH 106 · HND → LAX", walk: "Haneda · 9 min walk · 630 m"),
        Trip(date: "21 Mar 2026", gate: nil, gateDirection: .arrival, flight: "NH 105 · LAX → HND", walk: "Haneda arrival · 15 min walk · 1.05 km"),
    ]

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Previous trips").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            InfoCard {
                Text("These walks shape your estimates").outfitText(16, .regular)
            }
            VStack(spacing: 12) {
                ForEach(trips) { trip in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(trip.date).outfitText(13, .semibold, AB.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            TerminalSign(terminal: "3")
                            if let gate = trip.gate { GateSign(gate: gate, direction: trip.gateDirection) }
                        }
                        Text(trip.flight).outfitText(18, .bold)
                        Text(trip.walk).outfitText(15, .regular, AB.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(AB.card, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityElement(children: .combine)
                }
            }
            CTAButton(title: "View walking pace") { open(.airportWalking) }
                .accessibilityIdentifier("viewWalkingPace")
        }
    }
}
