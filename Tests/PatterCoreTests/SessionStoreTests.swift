import Foundation
import Testing
@testable import PatterCore

@Suite("SessionStore")
struct SessionStoreTests {
    let store = SessionStore()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
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

    @Test func promptMakesSessionWorkingWithRepoInfo() throws {
        store.apply(hook("SessionStart"))
        store.apply(hook("UserPromptSubmit", at: 1))

        let s = try #require(store.sessions["s1"])
        #expect(s.phase == .working)
        #expect(s.projectName == "argocd-apps")
        #expect(s.branch == "main")
        #expect(WorkingVerb.all.map { "\($0)…" }.contains(s.activity ?? ""))
        #expect(s.terminal == "iTerm.app")
        #expect(store.summary == PatterSummary(working: 1))
    }

    @Test func toolUseKeepsTheTurnsVerb() throws {
        store.apply(hook("UserPromptSubmit"))
        let verb = try #require(store.sessions["s1"]?.activity)
        store.apply(hook("PreToolUse", at: 2, extra: ["tool_name": "Edit", "tool_input": ["file_path": "/code/argocd-apps/apps/values.yaml"]]))
        #expect(store.sessions["s1"]?.activity == verb)
    }

    @Test func toolUseMidTurnStillGetsAVerb() {
        // e.g. the app started while a turn was already running
        store.apply(hook("PreToolUse", at: 2, extra: ["tool_name": "Bash", "tool_input": ["command": "ls"]]))
        #expect(WorkingVerb.all.map { "\($0)…" }.contains(store.sessions["s1"]?.activity ?? ""))
    }

    @Test func workingVerbIsStablePerSeedAndVaries() {
        #expect(WorkingVerb.pick(seed: "s1|1000") == WorkingVerb.pick(seed: "s1|1000"))
        let picks = Set((0..<30).map { WorkingVerb.pick(seed: "s1|\($0)") })
        #expect(picks.count >= 5)
    }

    @Test func permissionRequestNeedsInputAndEmitsOnce() throws {
        store.apply(hook("UserPromptSubmit"))
        let first = store.apply(hook("PermissionRequest", at: 5, extra: [
            "tool_name": "Bash", "tool_input": ["command": "terraform apply -target=module.eks"],
        ]))
        // The Notification hook for the same prompt must not notify twice.
        let second = store.apply(hook("Notification", at: 6, extra: ["notification_type": "permission_prompt", "message": "Claude needs your permission"]))

        let s = try #require(store.sessions["s1"])
        #expect(s.phase == .needsInput)
        #expect(s.attention == "Allow Bash")
        #expect(s.attentionDetail == "terraform apply -target=module.eks")
        #expect(first.count == 1)
        #expect(second.isEmpty)
        #expect(store.summary.dominantPhase == .needsInput)
    }

    @Test func approvedToolReturnsToWorking() throws {
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("PermissionRequest", at: 5, extra: ["tool_name": "Bash"]))
        store.apply(hook("PostToolUse", at: 20, extra: ["tool_name": "Bash"]))

        let s = try #require(store.sessions["s1"])
        #expect(s.phase == .working)
        #expect(s.attention == nil)
    }

    @Test func stopNotifiesOnlyForLongTurns() {
        store.apply(hook("UserPromptSubmit"))
        #expect(store.apply(hook("Stop", at: 10)).isEmpty)

        store.apply(hook("UserPromptSubmit", at: 100))
        let effects = store.apply(hook("Stop", at: 100 + 511))
        #expect(effects == [.finished(sessionID: "s1", project: "argocd-apps", duration: 511, tasks: nil)])
        #expect(store.sessions["s1"]?.phase == .idle)
        #expect(store.sessions["s1"]?.lastTurnDuration == 511)
    }

    @Test func todoWriteDrivesProgress() {
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("PreToolUse", at: 1, extra: ["tool_name": "TodoWrite", "tool_input": ["todos": [
            ["content": "a", "status": "completed"],
            ["content": "b", "status": "in_progress"],
            ["content": "c", "status": "pending"],
        ]]]))
        #expect(store.sessions["s1"]?.tasks == TaskProgress(done: 1, total: 3))
    }

    @Test func taskEventsDriveProgress() {
        store.apply(hook("TaskCreated"))
        store.apply(hook("TaskCreated", at: 1))
        store.apply(hook("TaskCompleted", at: 2))
        #expect(store.sessions["s1"]?.tasks == TaskProgress(done: 1, total: 2))
    }

    @Test func subagentsCountAndResetOnStop() {
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("SubagentStart", at: 1))
        store.apply(hook("SubagentStart", at: 2))
        store.apply(hook("SubagentStop", at: 3))
        #expect(store.sessions["s1"]?.activeSubagents == 1)
        store.apply(hook("Stop", at: 4))
        #expect(store.sessions["s1"]?.activeSubagents == 0)
    }

    @Test func statusLineFeedsContextAndUsage() throws {
        store.apply(hook("SessionStart"))
        store.apply(status([
            "model": ["display_name": "Opus 5"],
            "context_window": ["used_percentage": 62, "total_input_tokens": 124_000, "context_window_size": 200_000],
            "rate_limits": [
                "five_hour": ["used_percentage": 38.5, "resets_at": 1_800_008_000],
                "seven_day": ["used_percentage": 71],
            ],
        ], at: 1))

        let s = try #require(store.sessions["s1"])
        #expect(s.model == "Opus 5")
        #expect(s.context == ContextUsage(usedPercentage: 62, usedTokens: 124_000, windowSize: 200_000))
        #expect(store.usage?.fiveHour?.usedPercentage == 38.5)
        #expect(store.usage?.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_800_008_000))
        #expect(store.usage?.sevenDay?.usedPercentage == 71)
    }

    @Test func olderUsageSnapshotDoesNotOverwriteNewer() {
        store.apply(status(["rate_limits": ["five_hour": ["used_percentage": 50]]], at: 10, session: "a"))
        store.apply(status(["rate_limits": ["five_hour": ["used_percentage": 40]]], at: 5, session: "b"))
        #expect(store.usage?.fiveHour?.usedPercentage == 50)
    }

    @Test func sessionEndRemoves() {
        store.apply(hook("SessionStart"))
        store.apply(hook("SessionEnd", at: 1))
        #expect(store.sessions.isEmpty)
    }

    @Test func pruneDropsDeadProcessesAfterGrace() {
        store.apply(hook("SessionStart"))
        #expect(!store.prune(now: t0.addingTimeInterval(60), isAlive: { _ in false }))
        #expect(store.prune(now: t0.addingTimeInterval(300), isAlive: { _ in false }))
        #expect(store.sessions.isEmpty)
    }

    @Test func orderingPutsNeedsInputFirst() {
        store.apply(hook("UserPromptSubmit", session: "working"))
        store.apply(hook("SessionStart", at: 1, session: "idle"))
        store.apply(hook("PermissionRequest", at: 0.5, session: "blocked", extra: ["tool_name": "Bash"]))
        #expect(store.orderedSessions.map(\.id) == ["blocked", "working", "idle"])
    }

    @Test func orderingWithinAStateStaysPutAsSessionsWork() {
        store.apply(hook("UserPromptSubmit", session: "first"))
        store.apply(hook("UserPromptSubmit", at: 1, session: "second"))
        store.apply(hook("PreToolUse", at: 2, session: "second", extra: ["tool_name": "Read"]))
        store.apply(hook("PreToolUse", at: 3, session: "first", extra: ["tool_name": "Read"]))
        #expect(store.orderedSessions.map(\.id) == ["first", "second"])
        store.apply(hook("PreToolUse", at: 4, session: "second", extra: ["tool_name": "Edit"]))
        #expect(store.orderedSessions.map(\.id) == ["first", "second"])
    }

    @Test func eventsWithoutSessionIDAreIgnored() {
        let e = SpoolEvent(time: t0, kind: .hook, payload: JSONObject(["hook_event_name": "Stop"]))
        #expect(store.apply(e).isEmpty)
        #expect(store.sessions.isEmpty)
    }
}
