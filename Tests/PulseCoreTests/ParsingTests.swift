import Foundation
import Testing
@testable import PulseCore

@Suite("Parsing and formatting")
struct ParsingTests {
    @Test func decodesEnvelopeWrittenByHookScript() throws {
        let json = #"{"_pulse":{"v":1,"ts":1793106794106795,"pid":4242,"kind":"status","term":"ghostty"},"payload":{"session_id":"abc","hook_event_name":"Stop"}}"#
        let e = try #require(SpoolEvent.decode(Data(json.utf8)))
        #expect(e.kind == .status)
        #expect(e.pid == 4242)
        #expect(e.terminal == "ghostty")
        #expect(e.sessionID == "abc")
        #expect(abs(e.time.timeIntervalSince1970 - 1_793_106_794.106795) < 0.000_01)
    }

    @Test func rejectsMalformedAndNullPayloads() {
        #expect(SpoolEvent.decode(Data("not json".utf8)) == nil)
        #expect(SpoolEvent.decode(Data(#"{"_pulse":{"ts":1},"payload":null}"#.utf8)) == nil)
    }

    @Test(arguments: [
        ("Bash", ["command": "npm test\necho done"], "Running npm test"),
        ("Read", ["file_path": "/a/b/main.tf"], "Reading main.tf"),
        ("WebFetch", ["url": "https://code.claude.com/docs"], "Fetching code.claude.com"),
        ("mcp__linear__list_issues", [:], "Using linear · list_issues"),
        ("SomethingNew", [:], "Using SomethingNew"),
    ] as [(String, [String: String], String)])
    func activityDescriptions(tool: String, input: [String: String], expected: String) {
        #expect(ActivityDescriber.describe(tool: tool, input: JSONObject(input)) == expected)
    }

    @Test func formatting() {
        #expect(Format.duration(42) == "42s")
        #expect(Format.duration(372) == "6m 12s")
        #expect(Format.duration(8040) == "2h 14m")
        #expect(Format.shortDuration(372) == "6m")
        #expect(Format.tokens(124_312) == "124k")
        #expect(Format.tokens(1_000_000) == "1M")
        #expect(Format.tokens(950) == "950")
        #expect(Format.countdown(8040) == "2h 14m")
        #expect(Format.countdown(840) == "14m")
        #expect(Format.countdown(285_000) == "3d 7h")
        #expect(Format.countdown(42) == "<1m")
    }

    @Test func blockedUntilNeedsAFullWindowThatHasNotReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let soon = now.addingTimeInterval(3_600), later = now.addingTimeInterval(86_400)
        func limits(_ five: LimitWindow?, _ week: LimitWindow?) -> UsageLimits {
            UsageLimits(fiveHour: five, sevenDay: week, updatedAt: now)
        }

        #expect(limits(LimitWindow(usedPercentage: 99, resetsAt: soon), nil).blockedUntil(now: now) == nil)
        #expect(limits(LimitWindow(usedPercentage: 100, resetsAt: soon), nil).blockedUntil(now: now) == soon)
        #expect(limits(nil, LimitWindow(usedPercentage: 100, resetsAt: later)).blockedUntil(now: now) == later)
        // Both used up: you're back only when the later one resets.
        #expect(limits(LimitWindow(usedPercentage: 100, resetsAt: soon),
                       LimitWindow(usedPercentage: 100, resetsAt: later)).blockedUntil(now: now) == later)
        // Past the reset time the snapshot is stale: no longer blocked.
        #expect(limits(LimitWindow(usedPercentage: 100, resetsAt: soon), nil)
            .blockedUntil(now: soon.addingTimeInterval(1)) == nil)
        // No reset time means no countdown to show.
        #expect(limits(LimitWindow(usedPercentage: 100), nil).blockedUntil(now: now) == nil)
    }

    @Test func spoolReaderDrainsInTimestampOrder() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("cc-pulse-test-\(UUID().uuidString)")
        let reader = SpoolReader(directory: dir)
        reader.ensureDirectory()
        defer { try? fm.removeItem(at: dir) }

        func write(_ ts: Int64, _ name: String) throws {
            let json = #"{"_pulse":{"v":1,"ts":\#(ts),"pid":1,"kind":"hook","term":""},"payload":{"session_id":"s","hook_event_name":"\#(name)"}}"#
            try Data(json.utf8).write(to: dir.appendingPathComponent("\(ts)-1.hook.json"))
        }
        try write(2_000_000, "Stop")
        try write(1_000_000, "UserPromptSubmit")
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("3000000-1.hook.json"))
        try Data("{}".utf8).write(to: dir.appendingPathComponent(".tmp.123"))

        let events = reader.drain()
        #expect(events.map(\.hookName) == ["UserPromptSubmit", "Stop"])
        // Processed and malformed files are removed; in-flight temp files are left alone.
        #expect(try fm.contentsOfDirectory(atPath: dir.path) == [".tmp.123"])
    }

    @Test func gitInfoReadsBranchAndWorktrees() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cc-pulse-git-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let repo = root.appendingPathComponent("repo")
        try fm.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: repo.appendingPathComponent("sub/dir"), withIntermediateDirectories: true)
        try "ref: refs/heads/feat/eks-1.31\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)

        let info = try #require(GitInfo.repo(containing: repo.appendingPathComponent("sub/dir").path))
        #expect(URL(fileURLWithPath: info.root).lastPathComponent == "repo")
        #expect(info.branch == "feat/eks-1.31")

        // Worktree: .git is a file pointing elsewhere.
        let wtGit = root.appendingPathComponent("wt-gitdir")
        try fm.createDirectory(at: wtGit, withIntermediateDirectories: true)
        try "a1b2c3d4e5f6\n".write(to: wtGit.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let wt = root.appendingPathComponent("wt")
        try fm.createDirectory(at: wt, withIntermediateDirectories: true)
        try "gitdir: \(wtGit.path)\n".write(to: wt.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        #expect(GitInfo.repo(containing: wt.path)?.branch == "a1b2c3d")
    }
}
