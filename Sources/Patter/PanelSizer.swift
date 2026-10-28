import AppKit
import SwiftUI

/// Sizes a clear, borderless panel to its SwiftUI content, keeping the top
/// edge where it is. It grows at once but shrinks a moment later: SwiftUI
/// animates the content getting smaller (a session row leaving, the notch
/// folding up), and a window that snapped to the final size first would clip
/// that animation. The panel is clear, so the spare room is invisible.
///
/// The hosting view's own sizing is off (it would resize the window the
/// instant the content's size changes); the content reports its size instead.
@MainActor
final class PanelSizer {
    /// A bit longer than the session animations.
    static let shrinkDelay: TimeInterval = 0.5

    private weak var panel: NSPanel?
    private var target: CGSize = .zero
    private var pendingShrink: DispatchWorkItem?

    init(panel: NSPanel) {
        self.panel = panel
    }

    /// Makes `content` the panel's content, pinned to `alignment` (the window
    /// can briefly be bigger than it).
    func host<Content: View>(_ content: Content, alignment: Alignment) {
        let root = content
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { [weak self] in self?.fit(geo.size) }
                    .onChange(of: geo.size) { [weak self] _, size in self?.fit(size) }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        let view = NSHostingView(rootView: root)
        view.sizingOptions = []
        view.autoresizingMask = [.width, .height]
        panel?.contentView = view
    }

    private func fit(_ size: CGSize) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        target = size
        pendingShrink?.cancel()
        pendingShrink = nil
        let current = panel.frame.size
        let grown = CGSize(width: max(current.width, size.width), height: max(current.height, size.height))
        if grown != current { setSize(grown) }
        guard grown != size else { return }
        let shrink = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.setSize(self.target)
            self.pendingShrink = nil
        }
        pendingShrink = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: shrink)
    }

    private func setSize(_ size: CGSize) {
        guard let panel else { return }
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }
}
