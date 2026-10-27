import XCTest
@testable import PulseCore

final class ParsingTests: XCTestCase {
    func testDecodesEnvelopeWrittenByHookScript() throws {
        let json = #"{"_pulse":{"v":1,"ts":1793106794106795,"pid":4242,"kind":"status","term":"ghostty"},"payload":{"session_id":"abc","hook_event_name":"Stop"}}"#
        let e = try XCTUnwrap(SpoolEvent.decode(Data(json.utf8)))
        XCTAssertEqual(e.kind, .status)
        XCTAssertEqual(e.pid, 4242)
        XCTAssertEqual(e.terminal, "ghostty")
        XCTAssertEqual(e.sessionID, "abc")
        XCTAssertEqual(e.time.timeIntervalSince1970, 1_793_106_794.106795, accuracy: 0.000_01)
    }

    func testRejectsMalformedAndNullPayloads() {
        XCTAssertNil(SpoolEvent.decode(Data("not json".utf8)))
        XCTAssertNil(SpoolEvent.decode(Data(#"{"_pulse":{"ts":1},"payload":null}"#.utf8)))
    }

    func testActivityDescriptions() {
        func d(_ tool: String, _ input: [String: Any]) -> String {
            ActivityDescriber.describe(tool: tool, input: JSONObject(input))
        }
        XCTAssertEqual(d("Bash", ["command": "npm test\necho done"]), "Running npm test")
        XCTAssertEqual(d("Read", ["file_path": "/a/b/main.tf"]), "Reading main.tf")
        XCTAssertEqual(d("WebFetch", ["url": "https://code.claude.com/docs"]), "Fetching code.claude.com")
        XCTAssertEqual(d("mcp__linear__list_issues", [:]), "Using linear · list_issues")
        XCTAssertEqual(d("SomethingNew", [:]), "Using SomethingNew")
    }

    func testFormatting() {
        XCTAssertEqual(Format.duration(42), "42s")
        XCTAssertEqual(Format.duration(372), "6m 12s")
        XCTAssertEqual(Format.duration(8040), "2h 14m")
        XCTAssertEqual(Format.shortDuration(372), "6m")
        XCTAssertEqual(Format.tokens(124_312), "124k")
        XCTAssertEqual(Format.tokens(1_000_000), "1M")
        XCTAssertEqual(Format.tokens(950), "950")
    }

    func testSpoolReaderDrainsInTimestampOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cc-pulse-test-\(UUID().uuidString)")
        let reader = SpoolReader(directory: dir)
        reader.ensureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        func write(_ ts: Int64, _ name: String) throws {
            let json = #"{"_pulse":{"v":1,"ts":\#(ts),"pid":1,"kind":"hook","term":""},"payload":{"session_id":"s","hook_event_name":"\#(name)"}}"#
            try Data(json.utf8).write(to: dir.appendingPathComponent("\(ts)-1.hook.json"))
        }
        try write(2_000_000, "Stop")
        try write(1_000_000, "UserPromptSubmit")
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("3000000-1.hook.json"))
        try Data("{}".utf8).write(to: dir.appendingPathComponent(".tmp.123"))

        let events = reader.drain()
        XCTAssertEqual(events.map(\.hookName), ["UserPromptSubmit", "Stop"])
        // Processed and malformed files are removed; in-flight temp files are left alone.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [".tmp.123"])
    }

    func testGitInfoReadsBranchAndWorktrees() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cc-pulse-git-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let repo = root.appendingPathComponent("repo")
        try fm.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: repo.appendingPathComponent("sub/dir"), withIntermediateDirectories: true)
        try "ref: refs/heads/feat/eks-1.31\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)

        let info = try XCTUnwrap(GitInfo.repo(containing: repo.appendingPathComponent("sub/dir").path))
        XCTAssertEqual(URL(fileURLWithPath: info.root).lastPathComponent, "repo")
        XCTAssertEqual(info.branch, "feat/eks-1.31")

        // Worktree: .git is a file pointing elsewhere.
        let wtGit = root.appendingPathComponent("wt-gitdir")
        try fm.createDirectory(at: wtGit, withIntermediateDirectories: true)
        try "a1b2c3d4e5f6\n".write(to: wtGit.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let wt = root.appendingPathComponent("wt")
        try fm.createDirectory(at: wt, withIntermediateDirectories: true)
        try "gitdir: \(wtGit.path)\n".write(to: wt.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        XCTAssertEqual(GitInfo.repo(containing: wt.path)?.branch, "a1b2c3d")
    }
}
