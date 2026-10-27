import SwiftUI
import PatterCore

/// The cyan palette from the mockups. Panels are always dark, like the menu bar.
enum Theme {
    static let panel = Color(hex: 0x0F1A1E)
    static let card = Color(hex: 0x13242A)
    static let chip = Color(hex: 0x1A2A2F)
    static let track = Color(hex: 0x24383E)
    static let border = Color(hex: 0x24383E)

    static let text = Color(hex: 0xEEF6F7)
    static let textSecondary = Color(hex: 0xC3D3D7)
    static let textTertiary = Color(hex: 0x93AAB0)

    /// Working / progress.
    static let cyan = Color(hex: 0x22D3EE)
    static let cyanText = Color(hex: 0x67E8F9)
    /// Needs you / warnings.
    static let orange = Color(hex: 0xFB923C)
    static let orangeText = Color(hex: 0xFDBA74)
    static let onOrange = Color(hex: 0x1A1206)

    /// Menu bar mascot (Clawd) and its badges. The menu bar can be light or
    /// dark, so these are chosen to read on both.
    static let clawd = Color(hex: 0xD97757)
    static let badgeNeedsYou = Color(hex: 0xFACC15)
    static let onBadgeNeedsYou = Color(hex: 0x1A1206)
    static let badgeLimit = Color(hex: 0xF87171)
    static let onBadgeLimit = Color(hex: 0x1A0606)

    static let mono = Font.system(size: 11, design: .monospaced)

    static func color(for phase: SessionPhase) -> Color {
        switch phase {
        case .needsInput: return orange
        case .working: return cyan
        case .idle: return textTertiary
        }
    }
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
