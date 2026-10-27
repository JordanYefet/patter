import Foundation

/// One file from the spool directory: the envelope written by `pulse-hook.sh`
/// plus the raw Claude Code payload.
///
/// File shape:
/// ```json
/// {"_pulse": {"v":1, "ts":1793106794106795, "pid":4242, "kind":"hook", "term":"iTerm.app"},
///  "payload": { ...whatever Claude Code sent on stdin... }}
/// ```
/// The payload is parsed loosely on purpose: Claude Code adds fields often,
/// and an unknown or missing field must never break the app.
public struct SpoolEvent {
    public enum Kind: String, Sendable {
        /// A hook event (`hook_event_name` in the payload).
        case hook
        /// A status line snapshot (context window, rate limits, model).
        case status
    }

    public var time: Date
    public var pid: Int32
    public var kind: Kind
    public var terminal: String?
    public var payload: JSONObject

    public init(time: Date, pid: Int32 = 0, kind: Kind, terminal: String? = nil, payload: JSONObject) {
        self.time = time
        self.pid = pid
        self.kind = kind
        self.terminal = terminal
        self.payload = payload
    }

    public var sessionID: String? { payload.string("session_id") }
    public var hookName: String? { payload.string("hook_event_name") }
    public var cwd: String? { payload.string("cwd") }

    /// Decodes one spool file. Returns nil for anything malformed.
    public static func decode(_ data: Data) -> SpoolEvent? {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let meta = root["_pulse"] as? [String: Any],
            let payload = root["payload"] as? [String: Any]
        else { return nil }

        let meta_ = JSONObject(meta)
        guard let micros = meta_.double("ts") else { return nil }
        let kind = Kind(rawValue: meta_.string("kind") ?? "hook") ?? .hook
        let term = meta_.string("term").flatMap { $0.isEmpty ? nil : $0 }

        return SpoolEvent(
            time: Date(timeIntervalSince1970: micros / 1_000_000),
            pid: Int32(clamping: Int(meta_.double("pid") ?? 0)),
            kind: kind,
            terminal: term,
            payload: JSONObject(payload)
        )
    }
}

/// A thin, forgiving wrapper over a `JSONSerialization` dictionary.
public struct JSONObject {
    public let raw: [String: Any]

    public init(_ raw: [String: Any]) { self.raw = raw }

    public subscript(key: String) -> Any? { raw[key] }

    public func string(_ key: String) -> String? {
        raw[key] as? String
    }

    public func double(_ key: String) -> Double? {
        switch raw[key] {
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String: return Double(s)
        default: return nil
        }
    }

    public func int(_ key: String) -> Int? {
        double(key).map { Int($0) }
    }

    public func object(_ key: String) -> JSONObject? {
        (raw[key] as? [String: Any]).map(JSONObject.init)
    }

    public func array(_ key: String) -> [JSONObject]? {
        (raw[key] as? [[String: Any]]).map { $0.map(JSONObject.init) }
    }
}
