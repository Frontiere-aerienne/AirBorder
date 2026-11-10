import SwiftUI

// MARK: - Gate and terminal signs (Figma component "Gate sign", 862:16319)

enum SignDirection {
    case departure // ↗
    case arrival // ↘

    var rotation: Angle { self == .departure ? .degrees(-45) : .degrees(45) }
}

/// Yellow airport gate sign: arrow, "Gate" and the full gate identifier.
struct GateSign: View {
    let gate: String
    var direction: SignDirection = .departure
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: size >= 26 ? 8 : 4) {
            Image(size >= 22 ? "icArrowDark22" : "icArrowGate14")
                .resizable()
                .frame(width: arrowSize, height: arrowSize)
                .rotationEffect(direction.rotation)
            Text("Gate").outfitText(size, .medium, AB.gateText)
            Text(gate).outfitText(size, .bold, AB.gateText)
        }
        .padding(.horizontal, size >= 26 ? 12 : 8)
        .padding(.vertical, size >= 26 ? 6 : 4)
        .background(AB.gateYellow, in: RoundedRectangle(cornerRadius: size >= 26 ? 8 : 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gate \(gate)")
    }

    private var arrowSize: CGFloat { size >= 26 ? 22 : (size >= 18 ? 17 : 14) }
}

struct TerminalSign: View {
    let terminal: String
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 4) {
            Text("Terminal").outfitText(size, .medium, AB.gateText)
            Text(terminal).outfitText(size, .bold, AB.gateText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AB.gateYellow, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Terminal \(terminal)")
    }
}

// MARK: - Airline badges

enum Airline: String, Codable {
    case ana, thai

    var logoAsset: String { self == .ana ? "logoANA" : "logoTHAI" }
    var logoWidth: CGFloat { self == .ana ? 46 : 39 }
    var name: String { self == .ana ? "ANA" : "Thai Airways" }
}

struct AirlineBadge: View {
    let airline: Airline

    var body: some View {
        Image(airline.logoAsset)
            .resizable()
            .scaledToFit()
            .frame(width: airline.logoWidth, height: 12)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(airline.name)
    }
}

// MARK: - Buttons (Figma "CTA", "Secondary Button", "Text Button")

enum CTAStyle {
    case filled, outline, plain, light, destructive, translucent
}

struct CTAButton: View {
    let title: String
    var style: CTAStyle = .filled
    var height: CGFloat = 48
    var fullWidth = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .outfitText(14, style == .translucent ? .regular : .semibold, foreground)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minHeight: max(height, 44))
                .padding(.horizontal, 18)
                .background(background, in: Capsule())
                .overlay {
                    if style == .outline { Capsule().strokeBorder(AB.border, lineWidth: 1) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .filled, .destructive: return .white
        case .outline, .plain: return AB.primary
        case .light: return AB.navy
        case .translucent: return AB.ice
        }
    }

    private var background: Color {
        switch style {
        case .filled: return AB.primary
        case .outline: return .white
        case .plain: return .clear
        case .light: return AB.ice
        case .destructive: return AB.removeRed
        case .translucent: return AB.ice.opacity(0.12)
        }
    }
}

/// "Journey details →" style link.
struct TextLink: View {
    let title: String
    var color: Color = AB.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).outfitText(13, .semibold, color)
                Image("icArrowRightLink16").resizable().frame(width: 16, height: 16)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One back icon per screen (Figma "Back", 862:15938), 44 pt target.
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("icBack").resizable().frame(width: 26, height: 26)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("back")
    }
}

/// Sub-screen header used by My plan, Edit stop and similar screens.
struct HeaderWithBack: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            BackButton(action: back)
            Text(title).outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }
}

/// Back icon above a large title (Journey steps, Connected accounts, Airport walking).
struct StackedHeader: View {
    let title: String
    var spacing: CGFloat = 16
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            BackButton(action: back)
            Text(title).outfitText(28, .bold).accessibilityAddTraits(.isHeader)
        }
    }
}

// MARK: - Cards and chips

struct InfoCard<Content: View>: View {
    var padding: CGFloat = 20
    var radius: CGFloat = 20
    var background: Color = AB.card
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(background, in: RoundedRectangle(cornerRadius: radius))
    }
}

enum ChipTone {
    case info, open, leaveBy

    var foreground: Color {
        switch self {
        case .info: return AB.chipText
        case .open: return AB.mint
        case .leaveBy: return AB.sky
        }
    }

    var background: Color {
        switch self {
        case .info: return AB.ice.opacity(0.1)
        case .open: return AB.green.opacity(0.18)
        case .leaveBy: return AB.sky.opacity(0.2)
        }
    }
}

struct Chip: View {
    let text: String
    var tone: ChipTone = .info

    var body: some View {
        Text(text)
            .outfitText(12, .semibold, tone.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tone.background, in: Capsule())
    }
}

/// Wrapping row for chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows.removeLast()
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows.append(row)
        }
        return rows
    }
}

/// White grouped list used by Profile, Journey steps and Connected accounts.
struct GroupedList<Content: View>: View {
    var radius: CGFloat = 18
    var bordered = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(AB.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                if bordered { RoundedRectangle(cornerRadius: radius).strokeBorder(AB.border, lineWidth: 1) }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(AB.border).frame(height: 1) }
}

/// Section label above grouped lists ("Settings", "Flight import").
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).outfitText(13, .semibold, AB.muted).accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Toast (Figma "Toast (Plan updated, Undo)")

struct UndoToast: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        Button(action: undo) {
            HStack(spacing: 12) {
                Text(message).outfitText(15, .medium, AB.ice)
                Text("Undo").outfitText(15, .semibold, AB.sky)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(message). Undo")
        .accessibilityIdentifier("undoToast")
    }
}

// MARK: - Screen scaffold for pushed screens

struct SubScreen<Content: View>: View {
    var spacing: CGFloat = 12
    var top: CGFloat = 40
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.horizontal, 24)
                .padding(.top, top - 40)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
