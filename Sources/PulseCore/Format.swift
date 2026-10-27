import Foundation

/// Small, locale-independent formatters for the compact UI.
public enum Format {
    /// 42 -> "42s", 372 -> "6m 12s", 8040 -> "2h 14m"
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m \(s % 60)s" }
        let h = m / 60
        if h < 24 { return "\(h)h \(m % 60)m" }
        return "\(h / 24)d \(h % 24)h"
    }

    /// Like `duration` but without seconds once past a minute: "6m", "2h 14m".
    public static func shortDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return duration(seconds)
    }

    /// 124_312 -> "124k", 1_000_000 -> "1M", 950 -> "950"
    public static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            let v = Double(n) / 1_000_000
            return v == v.rounded() ? "\(Int(v))M" : String(format: "%.1fM", v)
        }
        if n >= 1_000 { return "\(Int((Double(n) / 1_000).rounded()))k" }
        return "\(n)"
    }

    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// "Resets in 2h 14m"
    public static func resets(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let left = date.timeIntervalSince(now)
        if left <= 0 { return "Resetting" }
        return "Resets in \(shortDuration(left))"
    }
}
