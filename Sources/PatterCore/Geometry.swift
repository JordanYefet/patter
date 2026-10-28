import CoreGraphics

/// Window placement maths, kept pure so it can be tested.
public enum Geometry {
    /// Moves `frame` so it sits fully inside one of `screens` (their usable
    /// areas): the one it overlaps most, or the nearest if it overlaps none.
    /// Nothing changes when it already fits, or when there are no screens.
    public static func keepInside(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        guard let screen = bestScreen(for: frame, in: screens) else { return frame }
        var f = frame
        f.origin.x = min(max(f.minX, screen.minX), screen.maxX - f.width)
        f.origin.y = min(max(f.minY, screen.minY), screen.maxY - f.height)
        return f
    }

    private static func bestScreen(for frame: CGRect, in screens: [CGRect]) -> CGRect? {
        func overlap(_ s: CGRect) -> CGFloat {
            let i = s.intersection(frame)
            return i.isNull ? 0 : i.width * i.height
        }
        if let best = screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 {
            return best
        }
        // Off every screen: the one closest to the frame's centre.
        let c = CGPoint(x: frame.midX, y: frame.midY)
        func distance(_ s: CGRect) -> CGFloat {
            let dx = max(s.minX - c.x, 0, c.x - s.maxX)
            let dy = max(s.minY - c.y, 0, c.y - s.maxY)
            return dx * dx + dy * dy
        }
        return screens.min(by: { distance($0) < distance($1) })
    }
}
