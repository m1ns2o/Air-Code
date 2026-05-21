import SwiftUI

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
                editor: Color(hex: 0x263238),
                foreground: Color(hex: 0xEEFFFF),
                muted: Color(hex: 0xB0BEC5),
                border: Color(hex: 0x31454B),
                accent: Color(hex: 0x80CBC4),
                green: Color(hex: 0xC3E88D),
                red: Color(hex: 0xFF5370),
                yellow: Color(hex: 0xFFCB6B),
                orange: Color(hex: 0xF78C6C),
                blue: Color(hex: 0x82AAFF)
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
                blue: Color(hex: 0x6182B8)
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
                blue: Color(hex: 0x82AAFF)
            )
        case .materialDarker:
            return AirCodeTheme(
                id: self,
                name: "Material Darker",
                isLight: false,
                background: Color(hex: 0x15191C),
                panel: Color(hex: 0x1F272A),
                elevated: Color(hex: 0x2A3438),
                editor: Color(hex: 0x212121),
                foreground: Color(hex: 0xEEFFFF),
                muted: Color(hex: 0x8796A1),
                border: Color(hex: 0x354147),
                accent: Color(hex: 0x80CBC4),
                green: Color(hex: 0xC3E88D),
                red: Color(hex: 0xFF5370),
                yellow: Color(hex: 0xFFCB6B),
                orange: Color(hex: 0xF78C6C),
                blue: Color(hex: 0x82AAFF)
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
