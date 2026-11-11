import CoreText
import SwiftUI

/// Colours from the AirBorder Figma prototype (page "Prototype").
enum AB {
    static let navy = Color(hex: 0x173247)
    static let primary = Color(hex: 0x225E79)
    static let screen = Color(hex: 0xE9F0F1)
    static let card = Color(hex: 0xFDFEFF)
    static let ticket = Color(hex: 0x17364A)
    static let gateYellow = Color(hex: 0xF9CB41)
    static let gateText = Color(hex: 0x13171B)
    static let secondary = Color(hex: 0x495E6D)
    static let muted = Color(hex: 0x435C6B)
    static let border = Color(hex: 0xD9E3EB)
    static let removeRed = Color(hex: 0xA32D28)
    static let resetRed = Color(hex: 0xAD3835)
    static let chip = Color(hex: 0xD5E2E6)
    static let ice = Color(hex: 0xF6F9FC)
    static let sky = Color(hex: 0x8EC1D6)
    static let mint = Color(hex: 0x99EBB2)
    static let green = Color(hex: 0x54CC80)
    static let chipText = Color(hex: 0xE5EDF2)
    static let tagGrey = Color(hex: 0xF0F4F7)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Outfit weights used by the design.
enum OutfitWeight: CGFloat {
    case light = 300
    case regular = 400
    case medium = 500
    case semibold = 600
    case bold = 700
}

/// Outfit ships as one variable font (SIL OFL, see Resources/Fonts/OFL.txt).
enum Outfit {
    private static let weightAxis = 2_003_265_652 // 'wght'
    private static var cache: [String: Font] = [:]

    static func register() {
        guard let url = Bundle.main.url(forResource: "Outfit-Variable", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(_ size: CGFloat, _ weight: OutfitWeight) -> Font {
        let key = "\(size)-\(weight.rawValue)"
        if let cached = cache[key] { return cached }
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: "Outfit",
            kCTFontVariationAttribute: [weightAxis: weight.rawValue],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let font = Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        cache[key] = font
        return font
    }
}

extension View {
    func outfit(_ size: CGFloat, _ weight: OutfitWeight = .regular, _ color: Color = AB.navy) -> some View {
        font(Outfit.font(size, weight)).foregroundStyle(color)
    }
}

extension Text {
    func outfitText(_ size: CGFloat, _ weight: OutfitWeight = .regular, _ color: Color = AB.navy) -> Text {
        font(Outfit.font(size, weight)).foregroundColor(color)
    }
}
