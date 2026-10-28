import SwiftUI
import PatterCore

/// An orange dot with a soft ring, used for "needs you".
struct AttentionDot: View {
    @ThemePalette private var palette

    var body: some View {
        Circle()
            .fill(palette.attention)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(palette.attention.opacity(0.28), lineWidth: 3).frame(width: 14, height: 14))
            .frame(width: 12, height: 12)
            .accessibilityLabel("Needs you")
    }
}

/// The leading mark on a session row: walking Clawd, orange dot or check.
struct PhaseIndicator: View {
    let phase: SessionPhase
    @ThemePalette private var palette

    /// Wide enough for Clawd; SessionRow indents its detail line to match.
    static let width: CGFloat = 16

    var body: some View {
        Group {
            switch phase {
            case .needsInput:
                AttentionDot()
            case .working:
                ClawdView(walking: true, cell: 0.85)
            case .idle:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityLabel("Idle")
            }
        }
        .frame(width: Self.width, height: 12)
    }
}

/// Horizontal progress bar.
struct Meter: View {
    let fraction: Double
    /// nil = the theme's accent.
    var color: Color?
    var height: CGFloat = 4
    @ThemePalette private var palette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule().fill(color ?? palette.accent).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}

/// A small text tag (the branch on a session row). Always a flat fill, even
/// in the glass theme: it sits inside rows that can be glass themselves, and
/// glass nested in glass melts into it.
struct Chip: View {
    let text: String
    @ThemePalette private var palette

    var body: some View {
        Text(text)
            .font(Theme.mono)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, palette.glass ? 7 : 6)
            .padding(.vertical, 1)
            .background(palette.chip, in: palette.glass ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 4)))
    }
}

struct SectionLabel: View {
    let text: String
    @ThemePalette private var palette

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

enum LiquidGlass {
    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

/// The palette the views below read: `Theme.palette`, unless a subtree
/// overrides it (the notch stays dark in every theme). The shared pieces
/// (rows, meters, chips) read this rather than `Theme.*` so they can sit in
/// the notch too.
@propertyWrapper
struct ThemePalette: DynamicProperty {
    @Environment(\.paletteOverride) private var override

    var wrappedValue: Palette { override ?? Theme.palette }
}

extension Palette {
    /// Hairline separators. Glass's `border` is a white edge light that
    /// vanishes on light backgrounds, so glass separates with the track color.
    var separator: Color { glass ? track : border }
}

private struct PaletteOverrideKey: EnvironmentKey {
    static var defaultValue: Palette? { nil }
}

extension EnvironmentValues {
    var paletteOverride: Palette? {
        get { self[PaletteOverrideKey.self] }
        set { self[PaletteOverrideKey.self] = newValue }
    }
}

extension View {
    /// The HUD card and pill: a solid fill with a hairline border, or one
    /// pane of Liquid Glass. Glass gets only a light legibility tint (it takes
    /// its color from what's behind it, and the text follows the system
    /// appearance to match) and no stroke, since the system draws its own
    /// edge highlight. Never nest these: glass inside glass is what crashed
    /// SwiftUI's material resolution.
    func panelSurface<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(PanelSurface(shape: shape, interactive: interactive))
    }

    /// Small standalone controls: a flat chip fill in every theme.
    func chipSurface<S: Shape>(_ shape: S) -> some View {
        modifier(ChipSurface(shape: shape))
    }
}

private struct PanelSurface<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if Theme.isGlass, #available(macOS 26, *) {
            let tint = scheme == .dark ? Theme.palette.glassTint.dark : Theme.palette.glassTint.light
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(Theme.panel.opacity(0.94), in: shape)
                .overlay(shape.stroke(Theme.border, lineWidth: 1))
        }
    }
}

private struct ChipSurface<S: Shape>: ViewModifier {
    let shape: S
    @ThemePalette private var palette

    func body(content: Content) -> some View {
        content.background(palette.chip, in: shape)
    }
}
