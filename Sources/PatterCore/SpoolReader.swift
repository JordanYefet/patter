import Foundation

/// Reads and removes event files from the spool directory, oldest first.
public final class SpoolReader {
    public let directory: URL
    private let fileManager: FileManager

    /// Payloads above this are skipped (a huge Write tool input, say).
    public var maxFileSize = 2_000_000

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// `~/.patter/spool`, or `$PATTER_HOME/spool`.
    public static var defaultDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        let home = env["PATTER_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".patter")
        return home.appendingPathComponent("spool")
    }

    public func ensureDirectory() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns all complete events and deletes their files. Malformed files are
    /// deleted too, so one bad payload can't wedge the queue.
    public func drain() -> [SpoolEvent] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }

        let files = names
            .filter { !$0.hasPrefix(".") && $0.hasSuffix(".json") }
            .sorted { Self.sortKey($0) < Self.sortKey($1) }

        var events: [SpoolEvent] = []
        events.reserveCapacity(files.count)
        for name in files {
            let url = directory.appendingPathComponent(name)
            defer { try? fileManager.removeItem(at: url) }
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size <= maxFileSize, let data = fileManager.contents(atPath: url.path) else { continue }
            if let event = SpoolEvent.decode(data) { events.append(event) }
        }
        return events
    }

    /// File names are `<microseconds>-<pid>.<kind>.json`.
    static func sortKey(_ name: String) -> (Int64, String) {
        let ts = name.split(separator: "-", maxSplits: 1).first.flatMap { Int64($0) } ?? 0
        return (ts, name)
    }
}
