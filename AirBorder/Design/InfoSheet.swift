import SwiftUI

/// One row in a Figma bottom sheet: tinted icon tile, label and detail.
struct SheetRow: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    var detail: String?
}

/// Figma bottom sheets (section "Popups"): grabber, title, close, rows, optional link and button.
struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let title: String
    let rows: [SheetRow]
    var link: (title: String, url: String)?
    var button: (title: String, action: () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule().fill(AB.border).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 10)
            HStack {
                Text(title).outfitText(22, .bold).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: {
                    Image("sheetClose").resizable().frame(width: 14, height: 14)
                        .frame(width: 36, height: 36)
                        .background(AB.navy.opacity(0.06), in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("sheetClose")
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 14) {
                        Image(row.icon).resizable().frame(width: 20, height: 20)
                            .frame(width: 40, height: 40)
                            .background(AB.sky.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label).outfitText(16, .semibold)
                            if let detail = row.detail { Text(detail).outfitText(14, .regular, AB.muted) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
            }
            if let link {
                Button { if let url = URL(string: link.url) { openURL(url) } } label: {
                    Text(link.title).outfitText(15, .semibold, AB.primary).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            if let button {
                CTAButton(title: button.title, height: 52) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { button.action() }
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(AB.card)
    }

    private var sheetHeight: CGFloat {
        var height: CGFloat = 92 + CGFloat(rows.count) * 64
        if link != nil { height += 52 }
        if button != nil { height += 76 }
        return height + 24
    }
}

/// The sheets used across the app, copied from the Figma "Popups" section.
enum Sheets {
    static func whyAirside(returnMinutes: Int? = nil) -> InfoSheet {
        InfoSheet(title: "Airside or landside?", rows: [
            SheetRow(icon: "tileShield", label: "Airside", detail: returnMinutes == nil ? "After security" : "After security, near your gate"),
            SheetRow(icon: "tileTransfer", label: "Landside", detail: returnMinutes.map { "Before security, \($0) min to get back" } ?? "Before security; check how to return to your gate"),
        ])
    }

    static func baggage(
        allowance: BaggageAllowance? = nil, arrival: Airport? = nil, destination: Airport? = nil,
        update: @escaping () -> Void
    ) -> InfoSheet {
        let rows: [SheetRow]
        if let allowance, let arrival, let destination {
            rows = [
                SheetRow(icon: "tileBag", label: "Checked to \(destination.code)", detail: "Stays with the airline at \(arrival.shortName)"),
                SheetRow(icon: "tileInfo", label: "Allowance", detail: "\(allowance.checked) checked, \(allowance.cabin) cabin"),
            ]
        } else {
            rows = [SheetRow(icon: "tileInfo", label: "Baggage details unavailable", detail: "Check your ticket or ask your airline.")]
        }
        return InfoSheet(title: "Your bag", rows: rows, button: ("Update baggage preference", update))
    }

    static func beforeLeavingAirside(walk: Int?, details: JourneyPresentationDetails? = nil) -> InfoSheet {
        guard let airside = details?.airside else {
            return InfoSheet(title: "Leaving airside", rows: [
                SheetRow(icon: "tileShield", label: "Check requirements before leaving", detail: "Confirm entry, security and baggage rules with official sources and your airline."),
            ])
        }
        return InfoSheet(title: "Leaving airside", rows: [
            SheetRow(icon: "tileClock", label: "\(airside.returnMinutes) min to get back", detail: walk.map { "Security plus a \($0) min walk" }),
            SheetRow(icon: "tileShield", label: airside.documentLabel, detail: airside.documentDetail),
            SheetRow(icon: "tileBag", label: "Your bag", detail: airside.baggageDetail),
        ], link: (airside.linkTitle, airside.linkURL))
    }

    static func aboutMap(walk: Int?, details: JourneyPresentationDetails? = nil) -> InfoSheet {
        guard let guide = details?.floorGuide else {
            return InfoSheet(title: "Your route", rows: [
                SheetRow(icon: "tileMap", label: "Indoor directions unavailable", detail: "Check your airport’s map or follow airport signs."),
            ])
        }
        return InfoSheet(title: "Your route", rows: [
            SheetRow(icon: "tileMap", label: guide.startLabel, detail: guide.startDetail),
            SheetRow(icon: "tileGate", label: guide.signLabel),
            SheetRow(icon: "tileWalk", label: walk.map { "\($0) min walk" } ?? "Walk time unavailable", detail: guide.walkDetail),
        ], button: (guide.buttonTitle, {
            if let url = URL(string: guide.url) { UIApplication.shared.open(url) }
        }))
    }

    static func aboutAirBorder() -> InfoSheet {
        InfoSheet(title: "AirBorder", rows: [
            SheetRow(icon: "tileMap", label: "Flight", detail: "Your gate, deadline and return route"),
            SheetRow(icon: "tileRest", label: "Layover", detail: "Stops that fit your time"),
            SheetRow(icon: "icProfileRow", label: "Profile", detail: "Language and step-free routes"),
        ])
    }

    static func privacy() -> InfoSheet {
        InfoSheet(title: "Privacy", rows: [
            SheetRow(icon: "tileShield", label: "Stays on this phone", detail: "Route needs and bag choices"),
        ])
    }
}

/// Figma "Usual baggage" (858:10357).
struct UsualBaggageSheet: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule().fill(AB.border).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 10)
            HStack {
                Text("Usual baggage").outfitText(22, .bold).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: {
                    Image("sheetClose").resizable().frame(width: 14, height: 14)
                        .frame(width: 36, height: 36)
                        .background(AB.navy.opacity(0.06), in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            ForEach(BaggagePreference.allCases, id: \.self) { option in
                Button {
                    store.baggagePreference = option
                    dismiss()
                } label: {
                    HStack {
                        Text(option.title).outfitText(15, .medium)
                        Spacer()
                        if store.baggagePreference == option {
                            Image("icCheckList").resizable().frame(width: 18, height: 18)
                        }
                    }
                    .padding(.horizontal, 17)
                    .frame(height: 52)
                    .background(AB.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AB.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.baggagePreference == option ? .isSelected : [])
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(AB.card)
    }
}

enum BaggagePreference: String, CaseIterable, Codable {
    case taggedThrough, collectAndRecheck, none

    var title: String {
        switch self {
        case .taggedThrough: return "Tagged to final destination"
        case .collectAndRecheck: return "Collect and recheck"
        case .none: return "No checked baggage"
        }
    }
}

/// Figma toasts (section "Toasts").
struct ToastMessage: Equatable {
    let text: String
    var action: String?
}

struct ToastView: View {
    let toast: ToastMessage
    var perform: (() -> Void)?

    var body: some View {
        Button { perform?() } label: {
            HStack(spacing: 12) {
                Text(toast.text).outfitText(15, .medium, Color(hex: 0xF6F9FB))
                if let action = toast.action { Text(action).outfitText(15, .semibold, AB.sky) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(perform == nil)
        .accessibilityIdentifier("toast")
    }
}
