import SwiftUI
import PatterCore

/// One session. `.full` is the menu bar dropdown, `.compact` the HUD and notch.
struct SessionRow: View {
    enum Style { case full, compact }

    let session: Session
    var style: Style = .full
    var onOpen: (Session) -> Void = { _ in }

    @ThemePalette private var palette
    @State private var hovering = false

    var body: some View {
        Button { onOpen(session) } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(now: context.date)
            }
            .padding(.horizontal, style == .full ? 12 : 10)
            .padding(.vertical, style == .full ? 9 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(RowSurface(
                shape: RoundedRectangle(cornerRadius: style == .full ? 10 : 12, style: .continuous),
                needsYou: session.phase == .needsInput,
                hovering: hovering
            ))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }

    /// One line: name, then what it's up to, then time and context on the
    /// right. When space runs out the detail gives way first.
    private func content(now: Date) -> some View {
        HStack(spacing: 8) {
            PhaseIndicator(phase: session.phase)
            Text(session.projectName)
                .font(.system(size: style == .full ? 13 : 12, weight: .semibold))
                .foregroundStyle(session.phase == .idle ? palette.textSecondary : palette.text)
                .lineLimit(1)
                .layoutPriority(2)
            detail
                .font(.system(size: style == .full ? 12 : 11))
                .lineLimit(1)
            Spacer(minLength: 6)
            trailing(now: now)
                .font(.system(size: style == .full ? 12 : 11))
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    /// The branch has no room in the row, so it lives in the tooltip.
    private var help: String {
        let open = "Click to bring \(session.terminal ?? "the terminal") to the front"
        guard let branch = session.branch else { return open }
        return "\(session.projectName) on \(branch)\n\(open)"
    }

    @ViewBuilder
    private var detail: some View {
        switch session.phase {
        case .needsInput:
            let title = Text(session.attention ?? "Needs your input").foregroundStyle(palette.attentionText)
            if let detail = session.attentionDetail {
                title + Text("  ") + Text(detail).font(Theme.mono).foregroundStyle(palette.text)
            } else {
                title
            }

        case .working:
            Text(workingDetail).foregroundStyle(palette.textSecondary)

        case .idle:
            if let last = session.lastTurnDuration {
                Text("Done in \(Format.duration(last))").foregroundStyle(palette.textTertiary)
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
        let base = Text(time).foregroundStyle(session.phase == .needsInput ? palette.attentionText : palette.textTertiary)
        guard let ctx = session.context else { return base }
        return base
            + Text(" · ").foregroundStyle(palette.textTertiary)
            + Text("ctx \(Format.percent(ctx.usedPercentage))").foregroundStyle(ctx.isHigh ? palette.attentionText : palette.textTertiary)
    }
}

/// A row's background: an orange wash when it needs you and a faint
/// highlight on hover. Flat in every theme; in Liquid Glass the glass is the
/// panel behind the rows, never the rows themselves.
private struct RowSurface<S: Shape>: ViewModifier {
    let shape: S
    let needsYou: Bool
    let hovering: Bool
    @ThemePalette private var palette

    func body(content: Content) -> some View {
        content.background(fill, in: shape)
    }

    private var fill: Color {
        if needsYou { return palette.attention.opacity(hovering ? 0.18 : 0.13) }
        return hovering ? palette.card : .clear
    }
}
