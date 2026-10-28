import SwiftUI

/// Clawd, the Claude Code mascot, as a path. Shared by the menu bar icon
/// (AppKit) and the HUD (SwiftUI) so both draw the same pixels.
///
/// The pixels are twice as tall as wide, like the quadrant characters of its
/// terminal art. Coordinates are y-down from the top-left of `size(cell:)`,
/// which leaves half a cell of room on each side for the sway and on top for
/// the bob.
enum Clawd {
    /// Walk cycle frames per second.
    static let stepsPerSecond: Double = 7

    // Pixel columns per row, from the startup art. Row 1 has the eye holes.
    private static let body: [[Int]] = [
        Array(3...14),
        [3, 4] + Array(6...11) + [13, 14],
        Array(1...16),
        Array(3...14),
    ]
    private static let outerLegs = [4, 13], innerLegs = [6, 11]

    static func size(cell w: CGFloat) -> CGSize {
        CGSize(width: 18 * w, height: 10.5 * w)
    }

    /// The walk frame (0..<4) to show at `date`.
    static func frame(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate * stepsPerSecond) % 4
    }

    /// `frame` nil = standing still; otherwise one of 4 walk-cycle frames:
    /// leg pairs alternate, the body bobs on every other step and sways.
    ///
    /// One path, filled once: filling each pixel separately leaves
    /// anti-aliased seams between them at fractional coordinates.
    static func path(cell w: CGFloat, frame: Int?) -> CGPath {
        let h = w * 2
        let step = (frame ?? 0) % 2
        let bob: CGFloat = frame != nil && step == 1 ? -w / 2 : 0
        let sway: CGFloat = frame.map { $0 % 4 < 2 ? -w / 2 : w / 2 } ?? 0
        let x0 = w / 2 + sway, y0 = w / 2

        let path = CGMutablePath()
        for (row, cols) in body.enumerated() {
            for col in cols {
                path.addRect(CGRect(x: x0 + CGFloat(col) * w, y: y0 + CGFloat(row) * h + bob, width: w, height: h))
            }
        }
        func legs(_ cols: [Int], up: Bool) {
            for col in cols {
                // A lifted leg is shorter; planted legs stretch to the ground while the body bobs.
                path.addRect(CGRect(x: x0 + CGFloat(col) * w, y: y0 + 4 * h + bob, width: w, height: up ? h * 0.45 : h - bob))
            }
        }
        if frame == nil {
            legs(outerLegs, up: false)
            legs(innerLegs, up: false)
        } else {
            legs(outerLegs, up: step == 1)
            legs(innerLegs, up: step == 0)
        }
        return path
    }

    /// Fills `path` as an outline `width` thick along its silhouette (and
    /// around the eye holes), in the current fill color of `ctx`.
    ///
    /// The path is a union of pixel rects, so stroking it would draw the seams
    /// between them. Instead: fill it, then clear its interior, i.e. the path
    /// eroded by `width`: the intersection of copies shifted by ±width in x, y
    /// and diagonally (the diagonals keep inner corners square). One cell
    /// keeps the 1-cell legs and the strips beside the eyes solid.
    static func fillOutline(_ path: CGPath, width t: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.fillPath()
        for dx in [-t, 0, t] {
            for dy in [-t, 0, t] where dx != 0 || dy != 0 {
                var shift = CGAffineTransform(translationX: dx, y: dy)
                guard let shifted = path.copy(using: &shift) else { continue }
                ctx.addPath(shifted)
                ctx.clip()
            }
        }
        ctx.setBlendMode(.clear)
        ctx.fill(path.boundingBoxOfPath)
        ctx.restoreGState()
    }
}

/// Clawd in SwiftUI: walks while `walking`, otherwise stands still.
struct ClawdView: View {
    var walking: Bool
    var color: Color = Theme.clawd
    var cell: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if walking && !reduceMotion {
                TimelineView(.periodic(from: .now, by: 1 / Clawd.stepsPerSecond)) { context in
                    shape(frame: Clawd.frame(at: context.date))
                }
            } else {
                shape(frame: nil)
            }
        }
        .accessibilityLabel(walking ? "Working" : "Idle")
    }

    private func shape(frame: Int?) -> some View {
        let size = Clawd.size(cell: cell)
        return Path(Clawd.path(cell: cell, frame: frame))
            .fill(color)
            .frame(width: size.width, height: size.height)
    }
}
