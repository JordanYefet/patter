import SwiftUI
import PulseCore

/// 5-hour and weekly limits. Only Pro/Max subscriptions report these, and only
/// after the first response in a session, so this view hides when there's no data.
struct UsageView: View {
    enum Style { case card, compact }

    let usage: UsageLimits?
    var style: Style = .card

    var body: some View {
        if let usage, usage.fiveHour != nil || usage.sevenDay != nil {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                switch style {
                case .card:
                    HStack(alignment: .top, spacing: 16) {
                        if let w = usage.fiveHour { LimitBar(title: "5-hour window", window: w, now: context.date) }
                        if let w = usage.sevenDay { LimitBar(title: "Weekly", window: w, now: context.date) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                case .compact:
                    HStack(spacing: 12) {
                        if let w = usage.fiveHour { MiniLimit(title: "5h", window: w, now: context.date) }
                        if let w = usage.sevenDay { MiniLimit(title: "Week", window: w, now: context.date) }
                    }
                }
            }
        }
    }
}

private struct LimitBar: View {
    let title: String
    let window: LimitWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(Format.percent(window.usedPercentage))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(window.isHigh ? Theme.orangeText : Theme.text)
                    .monospacedDigit()
            }
            Meter(fraction: window.usedPercentage / 100, color: window.isHigh ? Theme.orange : Theme.cyan, height: 5)
            if let resets = Format.resets(window.resetsAt, now: now) {
                Text(resets).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MiniLimit: View {
    let title: String
    let window: LimitWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(Format.percent(window.usedPercentage))
                    .foregroundStyle(window.isHigh ? Theme.orangeText : Theme.text)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.system(size: 10))
            Meter(fraction: window.usedPercentage / 100, color: window.isHigh ? Theme.orange : Theme.cyan, height: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private var label: String {
        guard let resets = Format.resets(window.resetsAt, now: now) else { return title }
        return "\(title) · \(resets.replacingOccurrences(of: "Resets in ", with: "resets "))"
    }
}
