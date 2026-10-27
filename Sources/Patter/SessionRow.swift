import SwiftUI
import PatterCore

/// One session. `.full` is the menu bar dropdown, `.compact` the HUD and notch.
struct SessionRow: View {
    enum Style { case full, compact }

    let session: Session
    var style: Style = .full
    var onOpen: (Session) -> Void = { _ in }

    var body: some View {
        Button { onOpen(session) } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(now: context.date)
            }
            .padding(.horizontal, style == .full ? 12 : 10)
            .padding(.vertical, style == .full ? 10 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: style == .full ? 8 : 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Bring \(session.terminal ?? "the terminal") to the front")
    }

    private var background: Color {
        session.phase == .needsInput ? Theme.orange.opacity(0.13) : Color.white.opacity(0.0001)
    }

    /// Two lines at most: name and status on top, one line of detail below.
    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                PhaseIndicator(phase: session.phase)
                Text(session.projectName)
                    .font(.system(size: style == .full ? 13 : 12, weight: .semibold))
                    .foregroundStyle(session.phase == .idle ? Theme.textSecondary : Theme.text)
                    .lineLimit(1)
                if style == .full, let branch = session.branch {
                    Chip(text: branch)
                }
                Spacer(minLength: 8)
                trailing(now: now)
                    .font(.system(size: style == .full ? 12 : 11))
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            detail
                .font(.system(size: style == .full ? 12 : 11))
                .lineLimit(1)
                .padding(.leading, PhaseIndicator.width + 8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch session.phase {
        case .needsInput:
            let title = Text(session.attention ?? "Needs your input").foregroundStyle(Theme.orangeText)
            if let detail = session.attentionDetail {
                title + Text("  ") + Text(detail).font(Theme.mono).foregroundStyle(Theme.text)
            } else {
                title
            }

        case .working:
            Text(workingDetail).foregroundStyle(Theme.textSecondary)

        case .idle:
            if let last = session.lastTurnDuration {
                Text("Done in \(Format.duration(last))").foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// "Pondering… · 3/5 tasks · +2 agents"
    private var workingDetail: String {
        var parts = [session.activity ?? "Working…"]
        if let tasks = session.tasks, tasks.total > 0 { parts.append("\(tasks.done)/\(tasks.total) tasks") }
        if session.activeSubagents > 0 {
            parts.append("+\(session.activeSubagents) agent\(session.activeSubagents == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    /// Right-hand text: time in state, then context % (orange when it's high).
    private func trailing(now: Date) -> Text {
        let since = now.timeIntervalSince(session.phaseSince)
        let time: String
        switch session.phase {
        case .needsInput:
            time = style == .full ? "waiting \(Format.shortDuration(since))" : Format.shortDuration(since)
        case .working:
            time = style == .full ? Format.duration(since) : Format.shortDuration(since)
        case .idle:
            time = "\(Format.shortDuration(since)) ago"
        }
        let base = Text(time).foregroundStyle(session.phase == .needsInput ? Theme.orangeText : Theme.textTertiary)
        guard let ctx = session.context else { return base }
        return base
            + Text(" · ").foregroundStyle(Theme.textTertiary)
            + Text("ctx \(Format.percent(ctx.usedPercentage))").foregroundStyle(ctx.isHigh ? Theme.orangeText : Theme.textTertiary)
    }
}
