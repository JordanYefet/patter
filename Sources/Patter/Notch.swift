import AppKit
import SwiftUI
import PatterCore

/// Wraps the MacBook notch: small "ears" while sessions run, wider and orange
/// when one needs you, and the full list on hover.
///
/// The panel is resized to exactly the black shape on every state change, so
/// it never sits invisibly over the menu bar eating clicks.
@MainActor
final class NotchController {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var resizeObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var wantsVisible = false

    static var hasNotch: Bool { notchScreen != nil }

    /// The built-in display, if it has a notch.
    static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
    }

    /// Notch width and height on that screen.
    static var notchSize: CGSize {
        guard let screen = notchScreen,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return CGSize(width: 190, height: 32) }
        return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    }

    init(model: AppModel) {
        self.model = model
        // Displays come and go (external monitor, lid closed or opened), so
        // re-check for the notched screen instead of deciding once at launch.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func setVisible(_ visible: Bool) {
        wantsVisible = visible
        if visible, Self.hasNotch {
            makePanelIfNeeded()
            panel?.orderFrontRegardless()
            recenter()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func screensChanged() {
        // The notch size is baked into the hosted view, so rebuild it.
        if let panel {
            panel.orderOut(nil)
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
            resizeObserver = nil
            self.panel = nil
        }
        setVisible(wantsVisible)
    }

    private func makePanelIfNeeded() {
        guard panel == nil, let model else { return }

        let hosting = NSHostingController(rootView: NotchView(notch: Self.notchSize).environmentObject(model))
        hosting.sizingOptions = .preferredContentSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.notchSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        // Above the menu bar so the shape can cover the notch area.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recenter() }
        }
        self.panel = panel
    }

    /// Keep the panel pinned to the top-center of the notched screen.
    private func recenter() {
        guard let panel, let screen = Self.notchScreen else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }
}

struct NotchView: View {
    @EnvironmentObject private var model: AppModel
    let notch: CGSize
    @State private var expanded = false

    private var blocked: Session? { model.sessions.first { $0.phase == .needsInput } }
    private var working: [Session] { model.sessions.filter { $0.phase == .working } }
    private var palette: Palette { .notch }

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                expandedContent
            } else {
                ears
            }
        }
        // Black in every theme, to match the hardware notch it extends.
        .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 24 : 12, bottomTrailingRadius: expanded ? 24 : 12))
        .overlay(alignment: .top) {
            if blocked != nil && !expanded {
                UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                    .stroke(palette.attention.opacity(0.4), lineWidth: 1.5)
            }
        }
        .fixedSize()
        .onHover { hovering in
            withAnimation(.spring(duration: 0.28)) { expanded = hovering && !model.sessions.isEmpty }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.paletteOverride, palette)
        .foregroundStyle(palette.text)
        .id(model.theme)
    }

    /// Collapsed: content to the left and right of the camera housing.
    @ViewBuilder
    private var ears: some View {
        if let blocked {
            HStack(spacing: notch.width) {
                HStack(spacing: 8) {
                    AttentionDot()
                    Text(blocked.projectName).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.attentionText).lineLimit(1)
                }
                .frame(width: 120, alignment: .leading)
                Text(shortAttention(blocked)).font(.system(size: 12)).foregroundStyle(palette.attentionText).lineLimit(1)
                    .frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(height: notch.height)
        } else if !working.isEmpty {
            HStack(spacing: notch.width) {
                HStack(spacing: 6) {
                    ClawdView(walking: true)
                    Text("\(working.count)").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                }
                .frame(width: 40, alignment: .leading)
                Text(aggregateTasks).font(.system(size: 12)).foregroundStyle(palette.accentText).monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: notch.height)
        } else {
            // Nothing running: exactly the notch, so it's invisible.
            Color.clear.frame(width: notch.width, height: notch.height)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear.frame(height: notch.height)
            UsageView(usage: model.usage, style: .compact)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            ForEach(model.sessions) { session in
                SessionRow(session: session, style: .compact) { model.open($0) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: 480)
    }

    private var aggregateTasks: String {
        let all = working.compactMap(\.tasks).filter { $0.total > 0 }
        guard !all.isEmpty else { return "" }
        return "\(all.map(\.done).reduce(0, +))/\(all.map(\.total).reduce(0, +))"
    }

    private func shortAttention(_ s: Session) -> String {
        guard let a = s.attention else { return "Needs you" }
        return a.hasPrefix("Allow ") ? "\(a)?" : ActivityDescriber.truncate(a, 18)
    }
}

extension Palette {
    /// The notch is black like the hardware it wraps, in every theme, so it
    /// always uses dark colors: dark themes keep theirs, a light theme (Paper)
    /// borrows Patter's, and glass stays flat (no glass beside a black notch;
    /// its semantic colors resolve light under the forced dark appearance).
    static var notch: Palette {
        var palette = Theme.palette.colorScheme == .light ? Palette.patter : Theme.palette
        palette.glass = false
        palette.colorScheme = .dark
        return palette
    }
}
