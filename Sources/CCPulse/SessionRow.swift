import SwiftUI
import PulseCore

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

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                Text(trailing(now: now))
                    .font(.system(size: style == .full ? 12 : 11))
                    .foregroundStyle(session.phase == .needsInput ? Theme.orangeText : Theme.textTertiary)
                    .monospacedDigit()
            }

            detail
                .padding(.leading, PhaseIndicator.width + 8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch session.phase {
        case .needsInput:
            VStack(alignment: .leading, spacing: 6) {
                Text(session.attention ?? "Needs your input")
                    .font(.system(size: style == .full ? 12 : 11))
                    .foregroundStyle(Theme.orangeText)
                    .lineLimit(1)
                if let detail = session.attentionDetail {
                    Text(detail)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.text)
                        .lineLimit(style == .full ? 3 : 1)
                        .padding(style == .full ? 7 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(style == .full ? Theme.chip : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
                if style == .full, let ctx = session.context { ContextBadge(context: ctx) }
            }

        case .working:
            VStack(alignment: .leading, spacing: 6) {
                if let activity = session.activity {
                    Text(activity)
                        .font(.system(size: style == .full ? 12 : 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if let tasks = session.tasks, tasks.total > 0 {
                    HStack(spacing: 8) {
                        Meter(fraction: tasks.fraction, height: style == .full ? 4 : 3)
                        if style == .full {
                            Text("\(tasks.done)/\(tasks.total) tasks")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                                .monospacedDigit()
                        }
                        if style == .full, session.activeSubagents > 0 {
                            Chip(text: "+\(session.activeSubagents) agent\(session.activeSubagents == 1 ? "" : "s")",
                                 color: Theme.cyanText, background: Theme.cyan.opacity(0.14))
                        }
                    }
                }
                if style == .full, let ctx = session.context { ContextBadge(context: ctx) }
            }

        case .idle:
            VStack(alignment: .leading, spacing: 6) {
                if let last = session.lastTurnDuration {
                    Text("Done in \(Format.duration(last))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                if style == .full, let ctx = session.context { ContextBadge(context: ctx) }
            }
        }
    }

    /// Right-hand text: time in state, plus tasks/context in compact mode.
    private func trailing(now: Date) -> String {
        let since = now.timeIntervalSince(session.phaseSince)
        switch session.phase {
        case .needsInput:
            let base = "waiting \(Format.shortDuration(since))"
            guard style == .compact, let ctx = session.context else { return base }
            return "\(Format.shortDuration(since)) · ctx \(Format.percent(ctx.usedPercentage))"
        case .working:
            guard style == .compact else { return Format.duration(since) }
            var parts: [String] = []
            if let t = session.tasks, t.total > 0 { parts.append("\(t.done)/\(t.total)") }
            if let ctx = session.context { parts.append("ctx \(Format.percent(ctx.usedPercentage))") }
            return parts.isEmpty ? Format.shortDuration(since) : parts.joined(separator: " · ")
        case .idle:
            let base = "\(Format.shortDuration(since)) ago"
            guard style == .compact, let ctx = session.context else { return base }
            return "\(base) · ctx \(Format.percent(ctx.usedPercentage))"
        }
    }
}
