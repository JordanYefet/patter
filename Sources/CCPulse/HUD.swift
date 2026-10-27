import AppKit
import SwiftUI
import PulseCore

/// A small always-on-top panel. Never takes focus, follows you across Spaces,
/// drag it anywhere (the position is remembered).
@MainActor
final class HUDController {
    private weak var model: AppModel?
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func setVisible(_ visible: Bool) {
        if visible {
            makePanelIfNeeded()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func makePanelIfNeeded() {
        guard panel == nil, let model else { return }

        let hosting = NSHostingController(rootView: HUDView().environmentObject(model))
        hosting.sizingOptions = .preferredContentSize

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        if !panel.setFrameUsingName("CCPulseHUD"), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - 300 - 24, y: visible.maxY - 16))
        }
        panel.setFrameAutosaveName("CCPulseHUD")
        self.panel = panel
    }
}

struct HUDView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("hudCollapsed") private var collapsed = false

    var body: some View {
        Group {
            if collapsed { pill } else { card }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(Theme.text)
        .fixedSize()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Claude Code").font(.system(size: 12, weight: .bold))
                Text(model.summary.active == 0 ? "idle" : "\(model.summary.active) active")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                Spacer()
                iconButton("chevron.up", label: "Collapse") { collapsed = true }
            }
            .padding(.leading, 8)
            .padding(.trailing, 2)
            .padding(.bottom, 2)

            UsageView(usage: model.usage, style: .compact)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            if model.sessions.isEmpty {
                Text("No sessions").font(.system(size: 11)).foregroundStyle(Theme.textTertiary).padding(10)
            }
            ForEach(model.sessions) { session in
                SessionRow(session: session, style: .compact) { model.open($0) }
            }
        }
        .padding(8)
        .frame(width: 300)
        .background(Theme.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }

    private var pill: some View {
        Button { collapsed = false } label: {
            HStack(spacing: 10) {
                if model.summary.working > 0 {
                    HStack(spacing: 5) {
                        Spinner()
                        Text("\(model.summary.working)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                if model.summary.working > 0, let first = firstBlocked {
                    Rectangle().fill(Theme.border).frame(width: 1, height: 14)
                    blocked(first)
                } else if let first = firstBlocked {
                    blocked(first)
                }
                if model.summary.active == 0 || (model.summary.working == 0 && firstBlocked == nil) {
                    PhaseIndicator(phase: .idle)
                    Text("Idle").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(minHeight: 44)
            .background(Theme.panel.opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand Claude Code status")
    }

    private var firstBlocked: Session? { model.sessions.first { $0.phase == .needsInput } }

    private func blocked(_ s: Session) -> some View {
        HStack(spacing: 6) {
            AttentionDot()
            Text(s.projectName).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.orangeText)
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityLabel(label)
        .help(label)
    }
}
