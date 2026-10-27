import XCTest
@testable import PulseCore

final class SessionStoreTests: XCTestCase {
    private var store: SessionStore!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        store = SessionStore()
        store.repoLookup = { cwd in
            cwd.hasPrefix("/code/argocd-apps") ? GitInfo.Repo(root: "/code/argocd-apps", branch: "main") : nil
        }
    }

    private func hook(_ name: String, at offset: TimeInterval = 0, session: String = "s1",
                      cwd: String = "/code/argocd-apps/apps", extra: [String: Any] = [:]) -> SpoolEvent {
        var payload: [String: Any] = ["session_id": session, "hook_event_name": name, "cwd": cwd]
        payload.merge(extra) { _, new in new }
        return SpoolEvent(time: t0.addingTimeInterval(offset), pid: 4242, kind: .hook, terminal: "iTerm.app", payload: JSONObject(payload))
    }

    private func status(_ payload: [String: Any], at offset: TimeInterval = 0, session: String = "s1") -> SpoolEvent {
        var p = payload
        p["session_id"] = session
        return SpoolEvent(time: t0.addingTimeInterval(offset), kind: .status, payload: JSONObject(p))
    }

    func testPromptMakesSessionWorkingWithRepoInfo() {
        store.apply(hook("SessionStart"))
        store.apply(hook("UserPromptSubmit", at: 1))

        let s = store.sessions["s1"]!
        XCTAssertEqual(s.phase, .working)
        XCTAssertEqual(s.projectName, "argocd-apps")
        XCTAssertEqual(s.branch, "main")
        XCTAssertEqual(s.activity, "Thinking…")
        XCTAssertEqual(s.terminal, "iTerm.app")
        XCTAssertEqual(store.summary, PulseSummary(working: 1))
    }

    func testToolUseDescribesActivity() {
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("PreToolUse", at: 2, extra: ["tool_name": "Edit", "tool_input": ["file_path": "/code/argocd-apps/apps/values.yaml"]]))
        XCTAssertEqual(store.sessions["s1"]?.activity, "Editing values.yaml")
    }

    func testPermissionRequestNeedsInputAndEmitsOnce() {
        store.apply(hook("UserPromptSubmit"))
        let first = store.apply(hook("PermissionRequest", at: 5, extra: [
            "tool_name": "Bash", "tool_input": ["command": "terraform apply -target=module.eks"],
        ]))
        // The Notification hook for the same prompt must not notify twice.
        let second = store.apply(hook("Notification", at: 6, extra: ["notification_type": "permission_prompt", "message": "Claude needs your permission"]))

        let s = store.sessions["s1"]!
        XCTAssertEqual(s.phase, .needsInput)
        XCTAssertEqual(s.attention, "Allow Bash")
        XCTAssertEqual(s.attentionDetail, "terraform apply -target=module.eks")
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second, [])
        XCTAssertEqual(store.summary.dominantPhase, .needsInput)
    }

    func testApprovedToolReturnsToWorking() {
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("PermissionRequest", at: 5, extra: ["tool_name": "Bash"]))
        store.apply(hook("PostToolUse", at: 20, extra: ["tool_name": "Bash"]))

        let s = store.sessions["s1"]!
        XCTAssertEqual(s.phase, .working)
        XCTAssertNil(s.attention)
    }

    func testStopNotifiesOnlyForLongTurns() {
        store.apply(hook("UserPromptSubmit"))
        XCTAssertEqual(store.apply(hook("Stop", at: 10)), [])

        store.apply(hook("UserPromptSubmit", at: 100))
        let effects = store.apply(hook("Stop", at: 100 + 511))
        XCTAssertEqual(effects, [.finished(sessionID: "s1", project: "argocd-apps", duration: 511, tasks: nil)])
        XCTAssertEqual(store.sessions["s1"]?.phase, .idle)
        XCTAssertEqual(store.sessions["s1"]?.lastTurnDuration, 511)
    }

    func testTodoWriteDrivesProgress() {
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("PreToolUse", at: 1, extra: ["tool_name": "TodoWrite", "tool_input": ["todos": [
            ["content": "a", "status": "completed"],
            ["content": "b", "status": "in_progress"],
            ["content": "c", "status": "pending"],
        ]]]))
        XCTAssertEqual(store.sessions["s1"]?.tasks, TaskProgress(done: 1, total: 3))
    }

    func testTaskEventsDriveProgress() {
        store.apply(hook("TaskCreated"))
        store.apply(hook("TaskCreated", at: 1))
        store.apply(hook("TaskCompleted", at: 2))
        XCTAssertEqual(store.sessions["s1"]?.tasks, TaskProgress(done: 1, total: 2))
    }

    func testSubagentsCountAndResetOnStop() {
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("SubagentStart", at: 1))
        store.apply(hook("SubagentStart", at: 2))
        store.apply(hook("SubagentStop", at: 3))
        XCTAssertEqual(store.sessions["s1"]?.activeSubagents, 1)
        store.apply(hook("Stop", at: 4))
        XCTAssertEqual(store.sessions["s1"]?.activeSubagents, 0)
    }

    func testStatusLineFeedsContextAndUsage() {
        store.apply(hook("SessionStart"))
        store.apply(status([
            "model": ["display_name": "Opus 5"],
            "context_window": ["used_percentage": 62, "total_input_tokens": 124_000, "context_window_size": 200_000],
            "rate_limits": [
                "five_hour": ["used_percentage": 38.5, "resets_at": 1_800_008_000],
                "seven_day": ["used_percentage": 71],
            ],
        ], at: 1))

        let s = store.sessions["s1"]!
        XCTAssertEqual(s.model, "Opus 5")
        XCTAssertEqual(s.context, ContextUsage(usedPercentage: 62, usedTokens: 124_000, windowSize: 200_000))
        XCTAssertEqual(store.usage?.fiveHour?.usedPercentage, 38.5)
        XCTAssertEqual(store.usage?.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_800_008_000))
        XCTAssertEqual(store.usage?.sevenDay?.usedPercentage, 71)
    }

    func testOlderUsageSnapshotDoesNotOverwriteNewer() {
        store.apply(status(["rate_limits": ["five_hour": ["used_percentage": 50]]], at: 10, session: "a"))
        store.apply(status(["rate_limits": ["five_hour": ["used_percentage": 40]]], at: 5, session: "b"))
        XCTAssertEqual(store.usage?.fiveHour?.usedPercentage, 50)
    }

    func testSessionEndRemoves() {
        store.apply(hook("SessionStart"))
        store.apply(hook("SessionEnd", at: 1))
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testPruneDropsDeadProcessesAfterGrace() {
        store.apply(hook("SessionStart"))
        XCTAssertFalse(store.prune(now: t0.addingTimeInterval(60), isAlive: { _ in false }))
        XCTAssertTrue(store.prune(now: t0.addingTimeInterval(300), isAlive: { _ in false }))
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testOrderingPutsNeedsInputFirst() {
        store.apply(hook("UserPromptSubmit", session: "working"))
        store.apply(hook("SessionStart", at: 1, session: "idle"))
        store.apply(hook("PermissionRequest", at: 0.5, session: "blocked", extra: ["tool_name": "Bash"]))
        XCTAssertEqual(store.orderedSessions.map(\.id), ["blocked", "working", "idle"])
    }

    func testEventsWithoutSessionIDAreIgnored() {
        let e = SpoolEvent(time: t0, kind: .hook, payload: JSONObject(["hook_event_name": "Stop"]))
        XCTAssertEqual(store.apply(e), [])
        XCTAssertTrue(store.sessions.isEmpty)
    }
}
