import AppKit
import PulseCore

/// Draws the menu bar icon: a terminal glyph plus a state mark.
///
/// MenuBarExtra renders SF Symbols as template (monochrome) images, which
/// can't show an orange badge, so we draw a non-template NSImage. The glyph
/// uses `labelColor`, resolved at draw time, so it follows the menu bar's
/// light/dark appearance.
enum MenuBarIcon {
    static func image(for summary: PulseSummary) -> NSImage {
        let phase = summary.dominantPhase
        let hasMark = phase == .needsInput || phase == .working
        let width: CGFloat = hasMark ? (phase == .needsInput ? 32 : 28) : 18
        let size = NSSize(width: width, height: 18)

        let image = NSImage(size: size, flipped: false) { _ in
            let glyphColor: NSColor = phase == nil ? .tertiaryLabelColor : .labelColor
            drawTerminal(in: NSRect(x: 1, y: 2, width: 16, height: 14), color: glyphColor)

            switch phase {
            case .needsInput?:
                drawBadge(count: summary.needsInput, in: NSRect(x: 18, y: 2, width: 14, height: 14))
            case .working?:
                drawArc(in: NSRect(x: 19, y: 4.5, width: 9, height: 9))
            default:
                break
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilityText(summary)
        return image
    }

    static func accessibilityText(_ s: PulseSummary) -> String {
        if s.needsInput > 0 { return "Claude Code: \(s.needsInput) session(s) need you" }
        if s.working > 0 { return "Claude Code: \(s.working) working" }
        return "Claude Code: idle"
    }

    private static func drawTerminal(in rect: NSRect, color: NSColor) {
        color.setStroke()
        let frame = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3, yRadius: 3)
        frame.lineWidth = 1.5
        frame.stroke()

        // ">" prompt and "_" cursor (AppKit's y axis points up).
        let prompt = NSBezierPath()
        prompt.move(to: NSPoint(x: rect.minX + 3.5, y: rect.midY + 2.5))
        prompt.line(to: NSPoint(x: rect.minX + 6.0, y: rect.midY))
        prompt.line(to: NSPoint(x: rect.minX + 3.5, y: rect.midY - 2.5))
        prompt.move(to: NSPoint(x: rect.minX + 7.5, y: rect.midY - 2.5))
        prompt.line(to: NSPoint(x: rect.minX + 11.5, y: rect.midY - 2.5))
        prompt.lineWidth = 1.5
        prompt.lineCapStyle = .round
        prompt.lineJoinStyle = .round
        prompt.stroke()
    }

    private static func drawBadge(count: Int, in rect: NSRect) {
        NSColor(srgbRed: 0xFB / 255, green: 0x92 / 255, blue: 0x3C / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()

        let text = count > 9 ? "9+" : "\(count)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor(srgbRed: 0x1A / 255, green: 0x12 / 255, blue: 0x06 / 255, alpha: 1),
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let s = str.size()
        str.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2))
    }

    private static func drawArc(in rect: NSRect) {
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = 2
        NSColor.labelColor.withAlphaComponent(0.25).setStroke()
        track.stroke()

        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: 90, endAngle: 0, clockwise: true)
        arc.lineWidth = 2
        arc.lineCapStyle = .round
        NSColor(srgbRed: 0x22 / 255, green: 0xD3 / 255, blue: 0xEE / 255, alpha: 1).setStroke()
        arc.stroke()
    }
}
