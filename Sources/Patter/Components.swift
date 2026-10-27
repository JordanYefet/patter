import SwiftUI
import PatterCore

/// An orange dot with a soft ring, used for "needs you".
struct AttentionDot: View {
    var body: some View {
        Circle()
            .fill(Theme.orange)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(Theme.orange.opacity(0.28), lineWidth: 3).frame(width: 14, height: 14))
            .frame(width: 12, height: 12)
            .accessibilityLabel("Needs you")
    }
}

/// The leading mark on a session row: walking Clawd, orange dot or check.
struct PhaseIndicator: View {
    let phase: SessionPhase

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
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityLabel("Idle")
            }
        }
        .frame(width: Self.width, height: 12)
    }
}

/// Horizontal progress bar.
struct Meter: View {
    let fraction: Double
    var color: Color = Theme.cyan
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}

struct Chip: View {
    let text: String
    var color: Color = Theme.textSecondary
    var background: Color = Theme.chip

    var body: some View {
        Text(text)
            .font(Theme.mono)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}
