import SwiftUI
import PatterCore

/// 5-hour and weekly limits. Only Pro/Max subscriptions report these, and only
/// after the first response in a session, so this view hides when there's no data.
struct UsageView: View {
    enum Style {
        case card, compact
        /// Compact meters pushed apart by `gap`, one each side of the notch.
        /// Each keeps its side even when the other window is missing.
        case split(gap: CGFloat)
    }

    let usage: UsageLimits?
    var style: Style = .card
    /// Compact only: the HUD drops the reset times when it's narrow.
    var showsResets = true
    @ThemePalette private var palette

    var body: some View {
        if let usage, usage.fiveHour != nil || usage.sevenDay != nil {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                switch style {
                case .card:
                    HStack(alignment: .top, spacing: 14) {
                        if let w = usage.fiveHour { LimitBar(title: "5-hour window", window: w, now: context.date) }
                        if usage.fiveHour != nil && usage.sevenDay != nil { divider }
                        if let w = usage.sevenDay { LimitBar(title: "Weekly", window: w, now: context.date) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .modifier(CardSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)))
                case .compact:
                    // Top-aligned with one-line labels, so both meters sit at the same height.
                    HStack(alignment: .top, spacing: 10) {
                        if let w = usage.fiveHour { MiniLimit(title: "5h", window: w, now: context.date, showsResets: showsResets) }
                        if usage.fiveHour != nil && usage.sevenDay != nil { divider }
                        if let w = usage.sevenDay { MiniLimit(title: "Week", window: w, now: context.date, showsResets: showsResets) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                case .split(let gap):
                    HStack(alignment: .top, spacing: gap) {
                        if let w = usage.fiveHour {
                            MiniLimit(title: "5h", window: w, now: context.date, showsResets: showsResets)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                        }
                        if let w = usage.sevenDay {
                            MiniLimit(title: "Week", window: w, now: context.date, showsResets: showsResets)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension UsageView {
    /// Separates the 5-hour and weekly windows so they don't read as one bar.
    private var divider: some View {
        Rectangle().fill(palette.separator).frame(width: 1).frame(maxHeight: .infinity)
    }
}

/// The card behind the limits in the menu.
private struct CardSurface<S: Shape>: ViewModifier {
    let shape: S
    @ThemePalette private var palette

    func body(content: Content) -> some View {
        content.background(palette.card, in: shape)
    }
}

private struct LimitBar: View {
    let title: String
    let window: LimitWindow
    let now: Date
    @ThemePalette private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(Format.percent(window.usedPercentage))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(window.isHigh ? palette.attentionText : palette.text)
                    .monospacedDigit()
            }
            Meter(fraction: window.usedPercentage / 100, color: window.isHigh ? palette.attention : palette.accent, height: 5)
            if let resets = Format.resets(window.resetsAt, now: now) {
                Text(resets).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MiniLimit: View {
    let title: String
    let window: LimitWindow
    let now: Date
    let showsResets: Bool
    @ThemePalette private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                Spacer(minLength: 4)
                Text(Format.percent(window.usedPercentage))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(window.isHigh ? palette.attentionText : palette.text)
                    .monospacedDigit()
                    .layoutPriority(1)
            }
            .font(.system(size: 12))
            Meter(fraction: window.usedPercentage / 100, color: window.isHigh ? palette.attention : palette.accent, height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    /// "5h · 2h 14m": the window and the time until it resets.
    private var label: String {
        guard showsResets, let resets = Format.resets(window.resetsAt, now: now) else { return title }
        return "\(title) · \(resets.replacingOccurrences(of: "Resets in ", with: ""))"
    }
}
