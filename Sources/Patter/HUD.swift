import AppKit
import SwiftUI
import PatterCore

/// A small always-on-top panel. Never takes focus, follows you across Spaces,
/// drag it anywhere (the position is remembered).
@MainActor
final class HUDController {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var sizer: PanelSizer?
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

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: HUDView.maxWidth, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let sizer = PanelSizer(panel: panel)
        sizer.host(HUDView().environmentObject(model), alignment: .topLeading)
        self.sizer = sizer
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
            panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - HUDView.maxWidth - 24, y: visible.maxY - 16))
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
    static let maxWidth: CGFloat = 360
    /// Narrow enough to tuck away; the project name and time still fit.
    static let minWidth: CGFloat = 250

    @EnvironmentObject private var model: AppModel
    @AppStorage("hudCollapsed") private var collapsed = false
    /// The expanded card's width, set by dragging its right edge.
    @AppStorage("hudWidth") private var storedWidth = Double(HUDView.maxWidth)
    /// Where the pointer is over the card, for the resize grip.
    @State private var hover: CGPoint?

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

    private var width: CGFloat {
        min(max(CGFloat(storedWidth), Self.minWidth), Self.maxWidth)
    }

    private func setCollapsed(_ value: Bool) {
        collapsed = value
    }

    private var title: some View {
        HStack(spacing: 8) {
            PatterLogo(size: 18)
            Text("Patter").font(.system(size: 12, weight: .bold))
        }
    }

    /// As the card narrows it drops information rather than squashing it:
    /// context %, then reset times, then Claude's word, then the active count.
    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                title
                Spacer(minLength: 8)
                if width >= 270 {
                    Text(model.summary.active == 0 ? "idle" : "\(model.summary.active) active")
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    iconButton("chevron.up", label: "Collapse") { setCollapsed(true) }
                    iconButton("xmark", label: "Close") { model.showHUD = false }
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 2)
            .padding(.bottom, 2)

            UsageView(usage: model.usage, style: .compact, showsResets: width >= 310)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            if model.sessions.isEmpty {
                Text("No sessions").font(.system(size: 11)).foregroundStyle(Theme.textTertiary).padding(10)
            }
            ForEach(model.sessions) { session in
                SessionRow(
                    session: session, style: .compact,
                    showsDetail: width >= 280, showsContext: width >= 340
                ) { model.open($0) }
                .transition(.sessionRow)
            }
        }
        .animatesSessions(model.sessions)
        .padding(8)
        .frame(width: width)
        // Drag to move; drag the right edge (inside the card's padding, so
        // it never covers a row or a button) to resize.
        .background(WindowDragArea(resize: .init(width: width, range: Self.minWidth...Self.maxWidth) { storedWidth = Double($0) }))
        .overlay(alignment: .trailing) { resizeGrip }
        .onContinuousHover { phase in
            if case .active(let point) = phase { hover = point } else { hover = nil }
        }
        .panelSurface(RoundedRectangle(cornerRadius: 14))
    }

    /// Shows that the right edge resizes. The resize cursor alone isn't
    /// enough: the HUD never makes Patter the active app, and macOS mostly
    /// ignores cursor changes from an inactive app.
    private var resizeGrip: some View {
        let onEdge = (hover?.x ?? 0) >= width - WindowDragArea.edge
        return Capsule()
            .fill(onEdge ? Theme.textSecondary : Theme.textTertiary.opacity(0.5))
            .frame(width: onEdge ? 4 : 3, height: 28)
            .padding(.trailing, 3)
            .opacity(hover == nil ? 0 : 1)
            .animation(.easeOut(duration: 0.15), value: onEdge)
            .animation(.easeOut(duration: 0.2), value: hover == nil)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
    /// Lets the right edge resize the content's width instead of moving the window.
    struct Resize {
        var width: CGFloat
        var range: ClosedRange<CGFloat>
        var onChange: (CGFloat) -> Void
    }

    var onClick: (() -> Void)?
    var resize: Resize?
    /// How far in from the right edge a drag resizes.
    static let edge: CGFloat = 10

    init(resize: Resize? = nil, onClick: (() -> Void)? = nil) {
        self.resize = resize
        self.onClick = onClick
    }

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.onClick = onClick
        view.resize = resize
    }

    final class DragView: NSView {
        var onClick: (() -> Void)?
        var resize: Resize?
        private var edge: CGFloat { WindowDragArea.edge }
        private enum Drag { case move(mouse: NSPoint, origin: NSPoint), resize(mouseX: CGFloat, width: CGFloat) }
        private var drag: Drag?
        private var moved = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private func onEdge(_ event: NSEvent) -> Bool {
            resize != nil && convert(event.locationInWindow, from: nil).x >= bounds.maxX - edge
        }

        // The panel never becomes key, so cursor rects don't apply: set the
        // cursor by hand from an always-active tracking area.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
            ))
        }

        override func mouseMoved(with event: NSEvent) {
            guard drag == nil else { return }
            (onEdge(event) ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
        }

        override func mouseExited(with event: NSEvent) {
            if drag == nil { NSCursor.arrow.set() }
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            moved = false
            if let resize, onEdge(event) {
                drag = .resize(mouseX: NSEvent.mouseLocation.x, width: resize.width)
            } else {
                drag = .move(mouse: NSEvent.mouseLocation, origin: window.frame.origin)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let drag else { return }
            let mouse = NSEvent.mouseLocation
            switch drag {
            case .resize(let startX, let width):
                guard let resize else { return }
                moved = true
                let proposed = (width + mouse.x - startX).rounded()
                resize.onChange(min(max(proposed, resize.range.lowerBound), resize.range.upperBound))
            case .move(let start, let origin):
                let dx = mouse.x - start.x, dy = mouse.y - start.y
                // A few points of slop so a slightly shaky click still counts as a click.
                if !moved && hypot(dx, dy) < 3 { return }
                moved = true
                window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            }
        }

        override func mouseUp(with event: NSEvent) {
            if moved { window?.keepOnScreen() } else { onClick?() }
            drag = nil
            (onEdge(event) ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
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
