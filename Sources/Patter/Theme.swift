import AppKit
import SwiftUI
import PatterCore

/// The themes you can pick in Settings → Appearance.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case patter, liquidGlass, claude, graphite, paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .patter: return "Patter"
        case .liquidGlass: return "Liquid Glass"
        case .claude: return "Claude"
        case .graphite: return "Graphite"
        case .paper: return "Paper"
        }
    }

    /// Liquid Glass needs macOS 26.
    var isAvailable: Bool {
        self != .liquidGlass || LiquidGlass.isAvailable
    }

    var palette: Palette {
        switch self {
        case .patter: return .patter
        case .liquidGlass: return .liquidGlass
        case .claude: return .claude
        case .graphite: return .graphite
        case .paper: return .paper
        }
    }
}

/// One theme's colors. Views read them through `Theme`, never directly.
struct Palette {
    var panel: Color
    var card: Color
    var chip: Color
    var track: Color
    var border: Color

    var text: Color
    var textSecondary: Color
    var textTertiary: Color

    /// Working / progress.
    var accent: Color
    var accentText: Color
    /// Needs you / warnings.
    var attention: Color
    var attentionText: Color
    var onAttention: Color

    /// Panels are Liquid Glass instead of a solid fill.
    var glass = false
    /// A light wash over the glass in each appearance, so text stays readable
    /// over busy wallpapers. Plain colors, not a dynamic one: glass resolves
    /// its tint itself.
    var glassTint: (light: Color, dark: Color) = (.clear, .clear)
    /// The appearance panels force; nil follows the system (glass adapts to
    /// what's behind it, so its text must too).
    var colorScheme: ColorScheme? = .dark

    /// The original cyan-on-dark-teal palette from the mockups.
    static let patter = Palette(
        panel: Color(hex: 0x0F1A1E), card: Color(hex: 0x13242A), chip: Color(hex: 0x1A2A2F),
        track: Color(hex: 0x24383E), border: Color(hex: 0x24383E),
        text: Color(hex: 0xEEF6F7), textSecondary: Color(hex: 0xC3D3D7), textTertiary: Color(hex: 0x93AAB0),
        accent: Color(hex: 0x22D3EE), accentText: Color(hex: 0x67E8F9),
        attention: Color(hex: 0xFB923C), attentionText: Color(hex: 0xFDBA74), onAttention: Color(hex: 0x1A1206)
    )

    /// System glass that follows the system appearance. Glass lets the
    /// wallpaper through, so the text tiers are stronger than the system's
    /// secondary/tertiary labels, and the accents are dark on light glass and
    /// pale on dark glass.
    static let liquidGlass = Palette(
        panel: .clear, card: Color.primary.opacity(0.06), chip: Color.primary.opacity(0.08),
        track: Color.primary.opacity(0.16), border: Color.white.opacity(0.22),
        text: .primary, textSecondary: Color.primary.opacity(0.85), textTertiary: Color.primary.opacity(0.68),
        accent: Color(light: 0x0891B2, dark: 0x22D3EE), accentText: Color(light: 0x0E7490, dark: 0x67E8F9),
        attention: Color(light: 0xEA580C, dark: 0xFB923C), attentionText: Color(light: 0xC2410C, dark: 0xFDBA74),
        onAttention: .white,
        glass: true, glassTint: (Color(hex: 0xFFFFFF, opacity: 0.32), Color(hex: 0x0B1214, opacity: 0.32)), colorScheme: nil
    )

    /// Warm charcoal with Claude's clay orange as the accent.
    static let claude = Palette(
        panel: Color(hex: 0x1F1E1D), card: Color(hex: 0x2A2826), chip: Color(hex: 0x34312E),
        track: Color(hex: 0x3D3935), border: Color(hex: 0x3D3935),
        text: Color(hex: 0xF5F0E8), textSecondary: Color(hex: 0xD6CFC4), textTertiary: Color(hex: 0xA39E93),
        accent: Color(hex: 0xD97757), accentText: Color(hex: 0xE8A48A),
        attention: Color(hex: 0xFBBF24), attentionText: Color(hex: 0xFCD34D), onAttention: Color(hex: 0x1A1206)
    )

    /// Neutral greys with an indigo accent.
    static let graphite = Palette(
        panel: Color(hex: 0x18181B), card: Color(hex: 0x232326), chip: Color(hex: 0x2C2C30),
        track: Color(hex: 0x3A3A3F), border: Color(hex: 0x34343A),
        text: Color(hex: 0xF4F4F5), textSecondary: Color(hex: 0xD4D4D8), textTertiary: Color(hex: 0xA1A1AA),
        accent: Color(hex: 0x818CF8), accentText: Color(hex: 0xA5B4FC),
        attention: Color(hex: 0xFB923C), attentionText: Color(hex: 0xFDBA74), onAttention: Color(hex: 0x1A1206)
    )

    /// Light: warm paper with dark teal and burnt orange.
    static let paper = Palette(
        panel: Color(hex: 0xFBF8F3), card: Color(hex: 0xF2EDE4), chip: Color(hex: 0xEAE3D7),
        track: Color(hex: 0xE0D8CA), border: Color(hex: 0xE0D8CA),
        text: Color(hex: 0x1F2328), textSecondary: Color(hex: 0x3D434A), textTertiary: Color(hex: 0x6B7178),
        accent: Color(hex: 0x0E7490), accentText: Color(hex: 0x0E7490),
        attention: Color(hex: 0xC2410C), attentionText: Color(hex: 0xC2410C), onAttention: .white,
        colorScheme: .light
    )
}

/// The current theme's colors, plus the few that never change with the theme.
///
/// `palette` is swapped by AppModel when the theme changes; the root views
/// key themselves on the theme (`.id(model.theme)`) so everything redraws.
enum Theme {
    nonisolated(unsafe) static var palette = Palette.patter

    static var panel: Color { palette.panel }
    static var card: Color { palette.card }
    static var chip: Color { palette.chip }
    static var track: Color { palette.track }
    static var border: Color { palette.border }

    static var text: Color { palette.text }
    static var textSecondary: Color { palette.textSecondary }
    static var textTertiary: Color { palette.textTertiary }

    static var accent: Color { palette.accent }
    static var accentText: Color { palette.accentText }
    static var attention: Color { palette.attention }
    static var attentionText: Color { palette.attentionText }
    static var onAttention: Color { palette.onAttention }

    static var isGlass: Bool { palette.glass }
    static var colorScheme: ColorScheme? { palette.colorScheme }

    /// Menu bar mascot (Clawd) and its badges, the same in every theme. The
    /// menu bar can be light or dark, so these are chosen to read on both.
    static let clawd = Color(hex: 0xD97757)
    static let badgeNeedsYou = Color(hex: 0xFACC15)
    static let onBadgeNeedsYou = Color(hex: 0x1A1206)
    static let badgeLimit = Color(hex: 0xF87171)
    static let onBadgeLimit = Color(hex: 0x1A0606)

    static let mono = Font.system(size: 11, design: .monospaced)

    static func color(for phase: SessionPhase) -> Color {
        switch phase {
        case .needsInput: return attention
        case .working: return accent
        case .idle: return textTertiary
        }
    }
}

extension View {
    /// Forces the theme's appearance, or leaves the system's (Liquid Glass).
    @ViewBuilder
    func themeColorScheme() -> some View {
        if let scheme = Theme.colorScheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}

extension Color {
    /// A color that follows the light/dark appearance it's drawn in.
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light, opacity: opacity))
        })
    }

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
