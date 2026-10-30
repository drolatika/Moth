import SwiftUI

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: Color
    let surface: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let onAccent: Color
    let isDark: Bool
    /// Optional full-screen artwork drawn behind the library (asset name).
    var backdrop: String? = nil

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? all[0]
    }

    static let all: [Theme] = [
        Theme(id: "moth", name: "Moth",
              background: Color(hex: 0x131213), surface: Color(hex: 0x1D1B1C),
              text: Color(hex: 0xECE3D0), secondaryText: Color(hex: 0x9A9084),
              accent: Color(hex: 0xC2483A), onAccent: Color(hex: 0xF4EAD8), isDark: true),
        Theme(id: "divine", name: "Divine Comedy",
              background: Color(hex: 0xEADCC0), surface: Color(hex: 0xF4ECDA),
              text: Color(hex: 0x2A1E14), secondaryText: Color(hex: 0x7C6A55),
              accent: Color(hex: 0x8C2A1A), onAccent: Color(hex: 0xF4ECDA), isDark: false,
              backdrop: "DivineComedyBackdrop"),
        Theme(id: "paper", name: "Paper",
              background: Color(hex: 0xF7F3EA), surface: Color(hex: 0xFFFFFF),
              text: Color(hex: 0x1E1B16), secondaryText: Color(hex: 0x7A7266),
              accent: Color(hex: 0xC2410C), onAccent: .white, isDark: false),
        Theme(id: "midnight", name: "Midnight",
              background: Color(hex: 0x0B1020), surface: Color(hex: 0x151C35),
              text: Color(hex: 0xE6EAF5), secondaryText: Color(hex: 0x7D88A8),
              accent: Color(hex: 0x6C8CFF), onAccent: Color(hex: 0x0B1020), isDark: true),
        Theme(id: "vinyl", name: "Vinyl",
              background: Color(hex: 0x0A0A0A), surface: Color(hex: 0x181818),
              text: Color(hex: 0xFAFAFA), secondaryText: Color(hex: 0x8A8A8A),
              accent: Color(hex: 0xE11D2E), onAccent: .white, isDark: true),
        Theme(id: "cassette", name: "Cassette",
              background: Color(hex: 0xEFE4CF), surface: Color(hex: 0xF9F1E1),
              text: Color(hex: 0x3B2A1A), secondaryText: Color(hex: 0x8A6F52),
              accent: Color(hex: 0xD9822B), onAccent: Color(hex: 0x2A1C0F), isDark: false),
        Theme(id: "neon", name: "Synthwave",
              background: Color(hex: 0x14061F), surface: Color(hex: 0x23103B),
              text: Color(hex: 0xF6E9FF), secondaryText: Color(hex: 0x9C7DB8),
              accent: Color(hex: 0xFF3CAC), onAccent: Color(hex: 0x14061F), isDark: true),
        Theme(id: "forest", name: "Forest",
              background: Color(hex: 0x0F1A14), surface: Color(hex: 0x19281F),
              text: Color(hex: 0xE7F0E9), secondaryText: Color(hex: 0x7F9886),
              accent: Color(hex: 0x5FD08A), onAccent: Color(hex: 0x0F1A14), isDark: true),
        Theme(id: "ocean", name: "Ocean",
              background: Color(hex: 0x06222E), surface: Color(hex: 0x0D3343),
              text: Color(hex: 0xE3F4F8), secondaryText: Color(hex: 0x7AA6B4),
              accent: Color(hex: 0x2EC4E6), onAccent: Color(hex: 0x06222E), isDark: true),
        Theme(id: "sunset", name: "Sunset",
              background: Color(hex: 0x1F0F12), surface: Color(hex: 0x2F181C),
              text: Color(hex: 0xFFE9DE), secondaryText: Color(hex: 0xB48A80),
              accent: Color(hex: 0xFF8A3D), onAccent: Color(hex: 0x1F0F12), isDark: true),
        Theme(id: "lavender", name: "Lavender",
              background: Color(hex: 0xF3EFFA), surface: Color(hex: 0xFFFFFF),
              text: Color(hex: 0x2A2238), secondaryText: Color(hex: 0x857B99),
              accent: Color(hex: 0x7C5CDB), onAccent: .white, isDark: false),
        Theme(id: "mono", name: "Mono",
              background: Color(hex: 0xFFFFFF), surface: Color(hex: 0xF1F1F1),
              text: Color(hex: 0x000000), secondaryText: Color(hex: 0x6E6E6E),
              accent: Color(hex: 0x000000), onAccent: .white, isDark: false),
        Theme(id: "nord", name: "Nord",
              background: Color(hex: 0x2E3440), surface: Color(hex: 0x3B4252),
              text: Color(hex: 0xECEFF4), secondaryText: Color(hex: 0x9AA3B5),
              accent: Color(hex: 0x88C0D0), onAccent: Color(hex: 0x2E3440), isDark: true),
        Theme(id: "espresso", name: "Espresso",
              background: Color(hex: 0x1A130F), surface: Color(hex: 0x281D17),
              text: Color(hex: 0xF2E6DA), secondaryText: Color(hex: 0xA08B7A),
              accent: Color(hex: 0xD4A373), onAccent: Color(hex: 0x1A130F), isDark: true),
        Theme(id: "mint", name: "Mint",
              background: Color(hex: 0xEEF8F3), surface: Color(hex: 0xFFFFFF),
              text: Color(hex: 0x12352A), secondaryText: Color(hex: 0x5E8577),
              accent: Color(hex: 0x0F9D76), onAccent: .white, isDark: false),
        Theme(id: "rose", name: "Rosé",
              background: Color(hex: 0xFDF0F2), surface: Color(hex: 0xFFFFFF),
              text: Color(hex: 0x3A1820), secondaryText: Color(hex: 0x9A6F78),
              accent: Color(hex: 0xE0466E), onAccent: .white, isDark: false),
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.all[0]
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    func themed(_ theme: Theme) -> some View {
        environment(\.theme, theme)
            .tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
    }
}
