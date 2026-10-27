import AppKit
import SwiftUI
import PulseCore

/// What the menu bar icon shows, highest priority first.
enum MenuBarState: Equatable {
    /// A usage limit is used up: grey Clawd, red "!", countdown to the reset.
    case limited(until: Date)
    case needsInput(count: Int)
    case working
    case idle
    case noSessions

    init(summary: PulseSummary, usage: UsageLimits?, now: Date) {
        if let until = usage?.blockedUntil(now: now) {
            self = .limited(until: until)
        } else {
            switch summary.dominantPhase {
            case .needsInput?: self = .needsInput(count: summary.needsInput)
            case .working?: self = .working
            case .idle?: self = .idle
            case nil: self = .noSessions
            }
        }
    }
}

/// The MenuBarExtra label. Clawd walks while a session works; a slow tick
/// keeps the countdown fresh and clears the limit state once it resets.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @StateObject private var clock = MenuBarClock()

    private var state: MenuBarState {
        MenuBarState(summary: model.summary, usage: model.usage, now: clock.now)
    }

    private var mode: MenuBarClock.Mode {
        switch state {
        case .working: return .walking
        case .limited: return .countdown
        default: return .stopped
        }
    }

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: state, frame: clock.frame, now: clock.now))
            .onAppear { clock.run(mode) }
            .onChange(of: mode) { _, mode in clock.run(mode) }
    }
}

/// Drives the label's redraws. Separate from AppModel so only the label
/// redraws at animation rate, not every view observing the model.
@MainActor
final class MenuBarClock: ObservableObject {
    enum Mode: Equatable { case stopped, walking, countdown }

    /// Walk cycle frame, 0..<4.
    @Published private(set) var frame = 0
    @Published private(set) var now = Date()
    private var timer: Timer?
    private var mode: Mode?

    func run(_ mode: Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        timer?.invalidate()
        timer = nil
        frame = 0
        now = Date()

        let interval: TimeInterval
        switch mode {
        case .stopped: return
        case .walking: interval = 1 / 7   // 7 steps a second
        case .countdown: interval = 20     // minute-resolution countdown
        }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.mode == .walking { self.frame = (self.frame + 1) % 4 }
                // Walking redraws plenty; only the countdown needs a fresh clock.
                if self.mode == .countdown { self.now = Date() }
            }
        }
        // .common so it keeps ticking while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// Draws Clawd, the Claude Code mascot, as the menu bar icon.
///
/// MenuBarExtra renders SF Symbols as template (monochrome) images, which
/// can't be orange, so this is a non-template NSImage. Grey Clawd and the
/// countdown use label colors resolved at draw time, so they follow the menu
/// bar's light/dark appearance.
enum MenuBarIcon {
    private static let height: CGFloat = 18
    /// Clawd's pixels are twice as tall as wide, like the quadrant characters
    /// of its terminal art. cell = pixel width.
    private static let cell: CGFloat = 1.15
    private static let clawdWidth: CGFloat = 21
    private static let badgeCenter = NSPoint(x: 18.5, y: 12.5)
    private static let badgeRadius: CGFloat = 4.4
    private static let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    // Pixel columns per row, from the startup art. Row 1 has the eye holes.
    private static let body: [[Int]] = [
        Array(3...14),
        [3, 4] + Array(6...11) + [13, 14],
        Array(1...16),
        Array(3...14),
    ]
    private static let outerLegs = [4, 13], innerLegs = [6, 11]

    static func image(for state: MenuBarState, frame: Int, now: Date) -> NSImage {
        var countdown: NSAttributedString?
        if case .limited(let until) = state {
            countdown = NSAttributedString(string: Format.countdown(until.timeIntervalSince(now)), attributes: [
                .font: countdownFont,
                .foregroundColor: NSColor.labelColor,
            ])
        }
        let hasBadge: Bool
        switch state {
        case .limited, .needsInput: hasBadge = true
        default: hasBadge = false
        }
        var width = hasBadge ? badgeCenter.x + badgeRadius * 1.65 + 0.5 : clawdWidth
        if let countdown { width += 3 + ceil(countdown.size().width) }

        // Flipped, so the art below reads top to bottom.
        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: true) { _ in
            switch state {
            case .working:
                drawClawd(color: NSColor(Theme.clawd), frame: frame)
            case .idle:
                drawClawd(color: NSColor(Theme.clawd), frame: nil)
            case .noSessions:
                drawClawd(color: .tertiaryLabelColor, frame: nil)
            case .needsInput(let count):
                drawClawd(color: NSColor(Theme.clawd), frame: nil)
                drawBadge(count > 9 ? "9+" : "\(count)", fill: NSColor(Theme.badgeNeedsYou), text: NSColor(Theme.onBadgeNeedsYou))
            case .limited:
                drawClawd(color: .tertiaryLabelColor, frame: nil)
                drawBadge("!", fill: NSColor(Theme.badgeLimit), text: NSColor(Theme.onBadgeLimit))
            }
            if let countdown {
                let size = countdown.size()
                countdown.draw(at: NSPoint(x: badgeCenter.x + badgeRadius * 1.65 + 3, y: (height - size.height) / 2))
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilityText(state, now: now)
        return image
    }

    static func accessibilityText(_ state: MenuBarState, now: Date) -> String {
        switch state {
        case .limited(let until): return "Claude Code: usage limit reached, resets in \(Format.countdown(until.timeIntervalSince(now)))"
        case .needsInput(let n): return "Claude Code: \(n) session(s) need you"
        case .working: return "Claude Code: working"
        case .idle: return "Claude Code: idle"
        case .noSessions: return "Claude Code: no sessions"
        }
    }

    /// `frame` nil = standing still; otherwise one of 4 walk-cycle frames:
    /// leg pairs alternate, the body bobs on every other step and sways.
    private static func drawClawd(color: NSColor, frame: Int?) {
        let w = cell, h = cell * 2
        let origin = NSPoint(x: 0, y: (height - 5 * h) / 2)
        let step = (frame ?? 0) % 2
        let bob: CGFloat = frame != nil && step == 1 ? -w / 2 : 0
        let sway: CGFloat = frame.map { $0 % 4 < 2 ? -w / 2 : w / 2 } ?? 0
        let x0 = origin.x + w / 2 + sway  // half a cell of room for the sway

        // One path, filled once: filling each pixel separately leaves
        // anti-aliased seams between them at fractional coordinates.
        let path = NSBezierPath()
        for (row, cols) in body.enumerated() {
            for col in cols {
                path.appendRect(NSRect(x: x0 + CGFloat(col) * w, y: origin.y + CGFloat(row) * h + bob, width: w, height: h))
            }
        }
        func legs(_ cols: [Int], up: Bool) {
            for col in cols {
                // A lifted leg is shorter; planted legs stretch to the ground while the body bobs.
                path.appendRect(NSRect(x: x0 + CGFloat(col) * w, y: origin.y + 4 * h + bob, width: w, height: up ? h * 0.45 : h - bob))
            }
        }
        if frame == nil {
            legs(outerLegs, up: false)
            legs(innerLegs, up: false)
        } else {
            legs(outerLegs, up: step == 1)
            legs(innerLegs, up: step == 0)
        }
        color.setFill()
        path.fill()
    }

    /// Docker-style: a round badge over the bottom-right corner, with a
    /// transparent ring punched out of Clawd around it.
    private static func drawBadge(_ text: String, fill: NSColor, text textColor: NSColor) {
        let c = badgeCenter, r = badgeRadius
        let wide = text.count > 1  // "9+" gets a pill
        let rect = wide
            ? NSRect(x: c.x - r * 1.3, y: c.y - r, width: r * 2.6, height: r * 2)
            : NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        let gap = r * 0.35
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(roundedRect: rect.insetBy(dx: -gap, dy: -gap), xRadius: r + gap, yRadius: r + gap).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()

        let str = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: wide ? 5.5 : 6.5, weight: .heavy),
            .foregroundColor: textColor,
        ])
        let size = str.size()
        str.draw(at: NSPoint(x: c.x - size.width / 2, y: c.y - size.height / 2))
    }
}
