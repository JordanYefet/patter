import AppKit
import SwiftUI
import PatterCore

/// A small always-on-top panel. Never takes focus, follows you across Spaces,
/// drag it anywhere (the position is remembered).
@MainActor
final class HUDController {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        // A display can disappear from under the HUD; bring it back.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.keepOnScreen() }
        })
    }

    func setVisible(_ visible: Bool) {
        if visible {
            makePanelIfNeeded()
            panel?.keepOnScreen()
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
            contentRect: NSRect(x: 0, y: 0, width: HUDView.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Dragging is done by WindowDragArea: NSHostingView never reports
        // mouseDownCanMoveWindow, so isMovableByWindowBackground has no effect.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        if !panel.setFrameUsingName("PatterHUD"), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - HUDView.width - 24, y: visible.maxY - 16))
        }
        panel.setFrameAutosaveName("PatterHUD")
        // Expanding near a screen edge would grow the card off screen.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            MainActor.assumeIsolated { panel?.keepOnScreen() }
        })
        self.panel = panel
    }
}

struct HUDView: View {
    /// Wide enough for a one-line session row: name, Claude's word, time, context.
    static let width: CGFloat = 360

    @EnvironmentObject private var model: AppModel
    @AppStorage("hudCollapsed") private var collapsed = false

    /// Every theme has the same structure; Liquid Glass only changes the
    /// material behind the card and the pill.
    var body: some View {
        Group {
            if collapsed { pill } else { card }
        }
        .themeColorScheme()
        .foregroundStyle(Theme.text)
        .fixedSize()
        // Theme is a static the views below don't observe: rebuild on change.
        .id(model.theme)
    }

    private func setCollapsed(_ value: Bool) {
        collapsed = value
    }

    private var title: some View {
        HStack(spacing: 8) {
            Text("Patter").font(.system(size: 12, weight: .bold))
            Text(model.summary.active == 0 ? "idle" : "\(model.summary.active) active")
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                title
                Spacer()
                iconButton("chevron.up", label: "Collapse") { setCollapsed(true) }
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
        .frame(width: Self.width)
        .background(WindowDragArea())
        .panelSurface(RoundedRectangle(cornerRadius: 14))
    }

    private var pill: some View {
        HStack(spacing: 10) {
            if model.summary.working > 0 {
                HStack(spacing: 6) {
                    clawd
                    Text("\(model.summary.working)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            if model.summary.working > 0, let first = firstBlocked {
                Rectangle().fill(Theme.palette.separator).frame(width: 1, height: 14)
                blocked(first)
            } else if let first = firstBlocked {
                blocked(first)
            }
            if model.summary.active == 0 || (model.summary.working == 0 && firstBlocked == nil) {
                clawd
                Text("Idle").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(minHeight: 44)
        .panelSurface(Capsule())
        // Drag to move, click to expand, anywhere on the pill: on top, since
        // the text and Clawd would otherwise take the click. The pill has no
        // buttons of its own. (A Button would swallow the drag.)
        .overlay(WindowDragArea { setCollapsed(false) }.clipShape(Capsule()))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Expand Patter")
        .accessibilityAction { setCollapsed(false) }
    }

    /// For the collapsed pill. Walks while any session works; grey with no sessions.
    private var clawd: some View {
        ClawdView(
            walking: model.summary.working > 0,
            color: model.summary.active == 0 ? Theme.textTertiary.opacity(0.6) : Theme.clawd
        )
    }

    private var firstBlocked: Session? { model.sessions.first { $0.phase == .needsInput } }

    private func blocked(_ s: Session) -> some View {
        HStack(spacing: 6) {
            AttentionDot()
            Text(s.projectName).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.attentionText)
        }
    }

    /// A rounded square chip.
    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .chipSurface(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Moves the window when dragged; calls `onClick` (if any) when clicked without
/// moving. Put it behind content: SwiftUI buttons on top keep their clicks.
struct WindowDragArea: NSViewRepresentable {
    var onClick: (() -> Void)?

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.onClick = onClick
    }

    final class DragView: NSView {
        var onClick: (() -> Void)?
        private var start: (mouse: NSPoint, origin: NSPoint)?
        private var moved = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            start = (NSEvent.mouseLocation, window.frame.origin)
            moved = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let start else { return }
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - start.mouse.x, dy = mouse.y - start.mouse.y
            // A few points of slop so a slightly shaky click still counts as a click.
            if !moved && hypot(dx, dy) < 3 { return }
            moved = true
            window.setFrameOrigin(NSPoint(x: start.origin.x + dx, y: start.origin.y + dy))
        }

        override func mouseUp(with event: NSEvent) {
            if moved { window?.keepOnScreen() } else { onClick?() }
            start = nil
        }
    }
}

extension NSWindow {
    /// Pulls the window fully inside a screen's usable area (clear of the
    /// menu bar and Dock), so it can't get stranded off screen.
    func keepOnScreen() {
        let fixed = Geometry.keepInside(frame, screens: NSScreen.screens.map(\.visibleFrame))
        if fixed.origin != frame.origin { setFrameOrigin(fixed.origin) }
    }
}
