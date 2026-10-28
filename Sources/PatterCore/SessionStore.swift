import Foundation

/// The state machine: folds spool events into per-session state.
///
/// Pure and synchronous: no timers, no I/O except the injectable git lookup,
/// so every transition is unit-testable. See docs/architecture.md for the
/// event -> state table.
public final class SessionStore {
    public private(set) var sessions: [String: Session] = [:]
    public private(set) var usage: UsageLimits?

    /// Only notify "finished" for turns at least this long (seconds).
    public var notifyFinishedAfter: TimeInterval = 30

    /// Injected so tests don't touch the file system.
    public var repoLookup: (String) -> GitInfo.Repo? = { GitInfo.repo(containing: $0) }

    public init() {}

    // MARK: - Reading

    /// Needs-you first, then working, then idle. Within each, the order they
    /// started in: activity never reshuffles the rows, only a change of state
    /// moves one, and a new session joins at the end of its group.
    public var orderedSessions: [Session] {
        sessions.values.sorted {
            if $0.phase != $1.phase { return $0.phase < $1.phase }
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id < $1.id
        }
    }

    public var summary: PatterSummary {
        var s = PatterSummary()
        for session in sessions.values {
            switch session.phase {
            case .working: s.working += 1
            case .needsInput: s.needsInput += 1
            case .idle: s.idle += 1
            }
        }
        return s
    }

    // MARK: - Applying events

    @discardableResult
    public func apply(_ event: SpoolEvent) -> [PatterEffect] {
        guard let id = event.sessionID, !id.isEmpty else { return [] }

        if event.hookName == "SessionEnd" {
            sessions[id] = nil
            return []
        }

        var session = sessions[id] ?? newSession(id: id, event: event)
        touch(&session, with: event)

        var effects: [PatterEffect] = []
        switch event.kind {
        case .status:
            applyStatus(event, to: &session)
        case .hook:
            effects = applyHook(event, to: &session)
        }

        sessions[id] = session
        return effects
    }

    /// Drops sessions whose Claude Code process is gone, and anything silent
    /// for a very long time. Returns true if anything was removed.
    @discardableResult
    public func prune(now: Date, isAlive: (Int32) -> Bool, deadGrace: TimeInterval = 120, maxSilence: TimeInterval = 12 * 3600) -> Bool {
        let before = sessions.count
        sessions = sessions.filter { _, s in
            let silence = now.timeIntervalSince(s.lastEventAt)
            if silence > maxSilence { return false }
            if s.pid > 1, silence > deadGrace, !isAlive(s.pid) { return false }
            return true
        }
        return sessions.count != before
    }

    // MARK: - Internals

    private func newSession(id: String, event: SpoolEvent) -> Session {
        var s = Session(id: id, cwd: event.cwd ?? "", at: event.time, pid: event.pid, terminal: event.terminal)
        refreshRepo(&s)
        return s
    }

    private func touch(_ s: inout Session, with event: SpoolEvent) {
        if event.time > s.lastEventAt { s.lastEventAt = event.time }
        if event.pid > 1 { s.pid = event.pid }
        if let term = event.terminal { s.terminal = term }
        if let cwd = event.cwd, !cwd.isEmpty, cwd != s.cwd {
            s.cwd = cwd
            refreshRepo(&s)
        }
    }

    private func refreshRepo(_ s: inout Session) {
        guard !s.cwd.isEmpty else { return }
        if let repo = repoLookup(s.cwd) {
            s.projectName = URL(fileURLWithPath: repo.root).lastPathComponent
            s.branch = repo.branch
        } else {
            s.projectName = URL(fileURLWithPath: s.cwd).lastPathComponent
            s.branch = nil
        }
    }

    private func setPhase(_ phase: SessionPhase, _ s: inout Session, at time: Date) {
        guard s.phase != phase else { return }
        s.phase = phase
        s.phaseSince = time
    }

    private func applyStatus(_ event: SpoolEvent, to s: inout Session) {
        let p = event.payload

        if let model = p.object("model")?.string("display_name") ?? p.object("model")?.string("id") {
            s.model = model
        }

        if let ctx = p.object("context_window"), let pct = ctx.double("used_percentage") {
            let used: Int?
            if let input = ctx.int("total_input_tokens") {
                used = input
            } else if let cur = ctx.object("current_usage") {
                used = (cur.int("input_tokens") ?? 0)
                    + (cur.int("cache_creation_input_tokens") ?? 0)
                    + (cur.int("cache_read_input_tokens") ?? 0)
            } else {
                used = nil
            }
            s.context = ContextUsage(usedPercentage: pct, usedTokens: used, windowSize: ctx.int("context_window_size"))
        }

        // Rate limits are account-wide: keep the newest snapshot from any session.
        if let limits = p.object("rate_limits"), usage.map({ event.time >= $0.updatedAt }) ?? true {
            func window(_ key: String) -> LimitWindow? {
                guard let w = limits.object(key), let pct = w.double("used_percentage") else { return nil }
                return LimitWindow(usedPercentage: pct, resetsAt: w.double("resets_at").map { Date(timeIntervalSince1970: $0) })
            }
            let five = window("five_hour"), week = window("seven_day")
            if five != nil || week != nil {
                usage = UsageLimits(fiveHour: five, sevenDay: week, updatedAt: event.time)
            }
        }
    }

    private func applyHook(_ event: SpoolEvent, to s: inout Session) -> [PatterEffect] {
        let p = event.payload
        let t = event.time
        let tool = p.string("tool_name")
        let input = p.object("tool_input")

        switch event.hookName {
        case "SessionStart":
            if let model = p.string("model") { s.model = model }
            if p.string("source") == "clear" {
                s.tasks = nil
                s.context = nil
            }
            if s.phase != .working { s.activity = nil }

        case "UserPromptSubmit":
            setPhase(.working, &s, at: t)
            s.turnStartedAt = t
            s.activity = WorkingVerb.activity(sessionID: s.id, turnStart: t)
            s.attention = nil
            s.attentionDetail = nil
            if s.tasks?.isComplete == true { s.tasks = nil }

        case "PreToolUse":
            // A pending permission is resolved once the tool actually runs (PostToolUse),
            // so don't let PreToolUse of a parallel call hide it.
            if s.phase != .needsInput { setPhase(.working, &s, at: t) }
            if s.turnStartedAt == nil { s.turnStartedAt = t }
            // The turn's verb stays put; the individual tool calls aren't shown.
            if s.activity == nil { s.activity = WorkingVerb.activity(sessionID: s.id, turnStart: s.turnStartedAt ?? t) }
            if tool == "TodoWrite", let todos = input?.array("todos") { s.tasks = progress(todos) }

        case "PostToolUse", "PostToolUseFailure":
            if s.phase == .needsInput {
                s.attention = nil
                s.attentionDetail = nil
            }
            setPhase(.working, &s, at: t)
            if tool == "TodoWrite", let todos = input?.array("todos") { s.tasks = progress(todos) }

        case "PermissionRequest":
            let name = tool ?? "a tool"
            return needsInput(&s, at: t, title: "Allow \(name)", detail: tool.flatMap { ActivityDescriber.permissionDetail(tool: $0, input: input) })

        case "Notification":
            let message = p.string("message")
            switch p.string("notification_type") {
            case "permission_prompt":
                // PermissionRequest usually got here first with better detail.
                if s.phase == .needsInput { return [] }
                return needsInput(&s, at: t, title: message ?? "Permission needed", detail: nil)
            case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                return needsInput(&s, at: t, title: message ?? "Claude has a question", detail: nil)
            default:
                break // idle_prompt and the rest don't change state
            }

        case "Stop":
            let duration = s.turnStartedAt.map { t.timeIntervalSince($0) }
            setPhase(.idle, &s, at: t)
            s.activity = nil
            s.attention = nil
            s.attentionDetail = nil
            s.activeSubagents = 0
            s.turnStartedAt = nil
            if let duration { s.lastTurnDuration = duration }
            refreshRepo(&s) // the branch may have changed during the turn
            if let duration, duration >= notifyFinishedAfter {
                return [.finished(sessionID: s.id, project: s.projectName, duration: duration, tasks: s.tasks)]
            }

        case "StopFailure":
            let reason = p.string("error_type") ?? p.string("error") ?? p.string("reason") ?? "error"
            s.activeSubagents = 0
            s.turnStartedAt = nil
            return needsInput(&s, at: t, title: "Stopped: \(reason.replacingOccurrences(of: "_", with: " "))", detail: nil)

        case "SubagentStart":
            s.activeSubagents += 1

        case "SubagentStop":
            s.activeSubagents = max(0, s.activeSubagents - 1)

        case "TaskCreated":
            let current = s.tasks ?? TaskProgress(done: 0, total: 0)
            s.tasks = TaskProgress(done: current.done, total: current.total + 1)

        case "TaskCompleted":
            if let current = s.tasks {
                s.tasks = TaskProgress(done: min(current.total, current.done + 1), total: current.total)
            }

        case "PreCompact":
            s.activity = "Compacting context…"

        default:
            break
        }
        return []
    }

    private func needsInput(_ s: inout Session, at t: Date, title: String, detail: String?) -> [PatterEffect] {
        let wasWaiting = s.phase == .needsInput
        setPhase(.needsInput, &s, at: t)
        s.attention = title
        s.attentionDetail = detail
        if wasWaiting { return [] }
        let message = detail.map { "\(title): \($0)" } ?? title
        return [.needsInput(sessionID: s.id, project: s.projectName, message: message)]
    }

    private func progress(_ todos: [JSONObject]) -> TaskProgress? {
        guard !todos.isEmpty else { return nil }
        let done = todos.filter { $0.string("status") == "completed" }.count
        return TaskProgress(done: done, total: todos.count)
    }
}
