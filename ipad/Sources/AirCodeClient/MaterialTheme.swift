@preconcurrency import CodeEditorView
import SwiftUI

#if os(iOS) || os(visionOS)
import UIKit
private typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
private typealias PlatformColor = NSColor
#endif

public enum AirCodeThemeID: String, CaseIterable, Identifiable {
    case materialOceanic
    case materialLighter
    case materialPalenight
    case materialDarker

    public var id: String { rawValue }

    public var theme: AirCodeTheme {
        switch self {
        case .materialOceanic:
            return AirCodeTheme(
                id: self,
                name: "Material Oceanic",
                isLight: false,
                background: Color(hex: 0x0F171A),
                panel: Color(hex: 0x172328),
                elevated: Color(hex: 0x223338),
                editor: Color(hex: 0x172328),
                foreground: Color(hex: 0xEEFFFF),
                muted: Color(hex: 0xB0BEC5),
                border: Color(hex: 0x31454B),
                accent: Color(hex: 0x80CBC4),
                green: Color(hex: 0xC3E88D),
                red: Color(hex: 0xFF5370),
                yellow: Color(hex: 0xFFCB6B),
                orange: Color(hex: 0xF78C6C),
                blue: Color(hex: 0x82AAFF),
                cursorHex: 0xFFE082
            )
        case .materialLighter:
            return AirCodeTheme(
                id: self,
                name: "Material Lighter",
                isLight: true,
                background: Color(hex: 0xFAFAFA),
                panel: Color(hex: 0xFFFFFF),
                elevated: Color(hex: 0xEEF3F5),
                editor: Color(hex: 0xFFFFFF),
                foreground: Color(hex: 0x546E7A),
                muted: Color(hex: 0x90A4AE),
                border: Color(hex: 0xD8E2E7),
                accent: Color(hex: 0x39ADB5),
                green: Color(hex: 0x91B859),
                red: Color(hex: 0xE53935),
                yellow: Color(hex: 0xF6A434),
                orange: Color(hex: 0xF76D47),
                blue: Color(hex: 0x6182B8),
                cursorHex: 0xF6A434
            )
        case .materialPalenight:
            return AirCodeTheme(
                id: self,
                name: "Material Palenight",
                isLight: false,
                background: Color(hex: 0x202331),
                panel: Color(hex: 0x292D3E),
                elevated: Color(hex: 0x34394F),
                editor: Color(hex: 0x292D3E),
                foreground: Color(hex: 0xA6ACCD),
                muted: Color(hex: 0x717CB4),
                border: Color(hex: 0x3E445F),
                accent: Color(hex: 0x80CBC4),
                green: Color(hex: 0xC3E88D),
                red: Color(hex: 0xFF5370),
                yellow: Color(hex: 0xFFCB6B),
                orange: Color(hex: 0xF78C6C),
                blue: Color(hex: 0x82AAFF),
                cursorHex: 0xFFE082
            )
        case .materialDarker:
            return AirCodeTheme(
                id: self,
                name: "Material Darker",
                isLight: false,
                background: Color(hex: 0x15191C),
                panel: Color(hex: 0x1F272A),
                elevated: Color(hex: 0x2A3438),
                editor: Color(hex: 0x1F272A),
                foreground: Color(hex: 0xEEFFFF),
                muted: Color(hex: 0x8796A1),
                border: Color(hex: 0x354147),
                accent: Color(hex: 0x80CBC4),
                green: Color(hex: 0xC3E88D),
                red: Color(hex: 0xFF5370),
                yellow: Color(hex: 0xFFCB6B),
                orange: Color(hex: 0xF78C6C),
                blue: Color(hex: 0x82AAFF),
                cursorHex: 0xFFE082
            )
        }
    }
}

public struct AirCodeTheme: Equatable, @unchecked Sendable {
    public let id: AirCodeThemeID
    public let name: String
    public let isLight: Bool
    public let background: Color
    public let panel: Color
    public let elevated: Color
    public let editor: Color
    public let foreground: Color
    public let muted: Color
    public let border: Color
    public let accent: Color
    public let green: Color
    public let red: Color
    public let yellow: Color
    public let orange: Color
    public let blue: Color
    public let cursorHex: UInt32
}

public extension AirCodeTheme {
    var codeEditorTheme: Theme {
        id.codeEditorTheme
    }

    var terminalBackground: Color {
        editor
    }

    var promptInputBackground: Color {
        switch id {
        case .materialOceanic:
            return Color(hex: 0x263238)
        case .materialLighter:
            return Color(hex: 0xFFFFFF)
        case .materialPalenight:
            return Color(hex: 0x292D3E)
        case .materialDarker:
            return Color(hex: 0x212121)
        }
    }

    var cursor: Color {
        Color(hex: cursorHex)
    }
}

public extension AirCodeThemeID {
    var codeEditorTheme: Theme {
        switch self {
        case .materialOceanic:
            return .airCodeMaterialOceanic
        case .materialLighter:
            return .airCodeMaterialLighter
        case .materialPalenight:
            return .airCodeMaterialPalenight
        case .materialDarker:
            return .airCodeMaterialDarker
        }
    }
}

private struct AirCodeThemeKey: EnvironmentKey {
    static let defaultValue = AirCodeThemeID.materialOceanic.theme
}

public extension EnvironmentValues {
    var airCodeTheme: AirCodeTheme {
        get { self[AirCodeThemeKey.self] }
        set { self[AirCodeThemeKey.self] = newValue }
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex & 0xFF0000) >> 16) / 255,
            green: Double((hex & 0x00FF00) >> 8) / 255,
            blue: Double(hex & 0x0000FF) / 255
        )
    }
}

private extension Theme {
    static var airCodeMaterialOceanic: Theme {
        Theme(
            colourScheme: .dark,
            fontName: "SFMono-Regular",
            fontSize: 14,
            textColour: color(0xEEFFFF),
            commentColour: color(0x546E7A),
            stringColour: color(0xC3E88D),
            characterColour: color(0xC3E88D),
            numberColour: color(0xF78C6C),
            identifierColour: color(0xEEFFFF),
            operatorColour: color(0x89DDFF),
            keywordColour: color(0xC792EA),
            symbolColour: color(0x89DDFF),
            typeColour: color(0xFFCB6B),
            fieldColour: color(0x82AAFF),
            caseColour: color(0xF07178),
            backgroundColour: color(0x172328),
            currentLineColour: color(0x223338),
            selectionColour: color(0xFFE082, alpha: 0.28),
            cursorColour: color(0xFFE082),
            invisiblesColour: color(0x546E7A)
        )
    }

    static var airCodeMaterialLighter: Theme {
        Theme(
            colourScheme: .light,
            fontName: "SFMono-Regular",
            fontSize: 14,
            textColour: color(0x546E7A),
            commentColour: color(0x90A4AE),
            stringColour: color(0x91B859),
            characterColour: color(0x91B859),
            numberColour: color(0xF76D47),
            identifierColour: color(0x546E7A),
            operatorColour: color(0x39ADB5),
            keywordColour: color(0x7C4DFF),
            symbolColour: color(0x39ADB5),
            typeColour: color(0xF6A434),
            fieldColour: color(0x6182B8),
            caseColour: color(0xE53935),
            backgroundColour: color(0xFFFFFF),
            currentLineColour: color(0xEEF3F5),
            selectionColour: color(0xF7E7BD),
            cursorColour: color(0xF6A434),
            invisiblesColour: color(0xCFD8DC)
        )
    }

    static var airCodeMaterialPalenight: Theme {
        Theme(
            colourScheme: .dark,
            fontName: "SFMono-Regular",
            fontSize: 14,
            textColour: color(0xA6ACCD),
            commentColour: color(0x676E95),
            stringColour: color(0xC3E88D),
            characterColour: color(0xC3E88D),
            numberColour: color(0xF78C6C),
            identifierColour: color(0xA6ACCD),
            operatorColour: color(0x89DDFF),
            keywordColour: color(0xC792EA),
            symbolColour: color(0x89DDFF),
            typeColour: color(0xFFCB6B),
            fieldColour: color(0x82AAFF),
            caseColour: color(0xF07178),
            backgroundColour: color(0x292D3E),
            currentLineColour: color(0x34394F),
            selectionColour: color(0xFFE082, alpha: 0.28),
            cursorColour: color(0xFFE082),
            invisiblesColour: color(0x4E5579)
        )
    }

    static var airCodeMaterialDarker: Theme {
        Theme(
            colourScheme: .dark,
            fontName: "SFMono-Regular",
            fontSize: 14,
            textColour: color(0xEEFFFF),
            commentColour: color(0x4A4A4A),
            stringColour: color(0xC3E88D),
            characterColour: color(0xC3E88D),
            numberColour: color(0xF78C6C),
            identifierColour: color(0xEEFFFF),
            operatorColour: color(0x89DDFF),
            keywordColour: color(0xC792EA),
            symbolColour: color(0x89DDFF),
            typeColour: color(0xFFCB6B),
            fieldColour: color(0x82AAFF),
            caseColour: color(0xF07178),
            backgroundColour: color(0x1F272A),
            currentLineColour: color(0x2A3438),
            selectionColour: color(0xFFE082, alpha: 0.28),
            cursorColour: color(0xFFE082),
            invisiblesColour: color(0x4A4A4A)
        )
    }

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> PlatformColor {
        PlatformColor(
            red: CGFloat((hex & 0xFF0000) >> 16) / 255,
            green: CGFloat((hex & 0x00FF00) >> 8) / 255,
            blue: CGFloat(hex & 0x0000FF) / 255,
            alpha: alpha
        )
    }
}
