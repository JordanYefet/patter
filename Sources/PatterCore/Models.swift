import Foundation

/// What a session is doing right now, from the user's point of view.
public enum SessionPhase: String, Sendable, Comparable {
    /// Blocked on you: a permission prompt, a question, or a failure.
    case needsInput
    /// Claude is processing a prompt.
    case working
    /// Waiting for your next prompt (or just finished).
    case idle

    /// Sort order: the states that cost you time come first.
    var rank: Int {
        switch self {
        case .needsInput: return 0
        case .working: return 1
        case .idle: return 2
        }
    }

    public static func < (lhs: SessionPhase, rhs: SessionPhase) -> Bool { lhs.rank < rhs.rank }
}

/// Context-window usage, from the status line feed.
public struct ContextUsage: Equatable, Sendable {
    public var usedPercentage: Double
    public var usedTokens: Int?
    public var windowSize: Int?

    public init(usedPercentage: Double, usedTokens: Int? = nil, windowSize: Int? = nil) {
        self.usedPercentage = usedPercentage
        self.usedTokens = usedTokens
        self.windowSize = windowSize
    }

    /// Claude Code auto-compacts near the top of the window; warn before that.
    public var isHigh: Bool { usedPercentage >= 80 }
}

/// One rate-limit window (5-hour or weekly), from the status line feed.
public struct LimitWindow: Equatable, Sendable {
    public var usedPercentage: Double
    public var resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date? = nil) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    public var isHigh: Bool { usedPercentage >= 80 }
}

/// Account-wide usage limits. Only present for Pro/Max subscribers.
public struct UsageLimits: Equatable, Sendable {
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var updatedAt: Date

    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?, updatedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
    }

    /// When you can work again, if a limit is used up right now: the latest
    /// reset among full windows. Nil once that time passes (the snapshot is
    /// stale by then) or when there's no reset time to count down to.
    public func blockedUntil(now: Date) -> Date? {
        [fiveHour, sevenDay]
            .compactMap { $0 }
            .filter { $0.usedPercentage >= 100 }
            .compactMap(\.resetsAt)
            .filter { $0 > now }
            .max()
    }
}

/// Progress through Claude's own todo list for the current piece of work.
public struct TaskProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    public var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    public var isComplete: Bool { total > 0 && done >= total }
}

/// Everything Patter knows about one Claude Code session.
public struct Session: Identifiable, Equatable, Sendable {
    public let id: String
    public var cwd: String
    public var projectName: String
    public var branch: String?

    public var phase: SessionPhase
    public var phaseSince: Date
    public var startedAt: Date
    public var lastEventAt: Date

    /// Plain-language current action, e.g. "Editing values.yaml".
    public var activity: String?
    /// Why the session needs you, e.g. "Allow Bash".
    public var attention: String?
    /// The detail behind `attention`, e.g. the command waiting for approval.
    public var attentionDetail: String?

    public var tasks: TaskProgress?
    public var activeSubagents: Int
    public var context: ContextUsage?
    public var model: String?

    /// Claude Code's process id (0 if unknown). Used to drop crashed sessions.
    public var pid: Int32
    /// $TERM_PROGRAM of the terminal the session runs in.
    public var terminal: String?

    public var turnStartedAt: Date?
    public var lastTurnDuration: TimeInterval?

    public init(id: String, cwd: String, at time: Date, pid: Int32 = 0, terminal: String? = nil) {
        self.id = id
        self.cwd = cwd
        self.projectName = URL(fileURLWithPath: cwd).lastPathComponent
        self.branch = nil
        self.phase = .idle
        self.phaseSince = time
        self.startedAt = time
        self.lastEventAt = time
        self.activity = nil
        self.attention = nil
        self.attentionDetail = nil
        self.tasks = nil
        self.activeSubagents = 0
        self.context = nil
        self.model = nil
        self.pid = pid
        self.terminal = terminal
        self.turnStartedAt = nil
        self.lastTurnDuration = nil
    }
}

/// Counts for the menu bar icon.
public struct PatterSummary: Equatable, Sendable {
    public var working: Int = 0
    public var needsInput: Int = 0
    public var idle: Int = 0

    public init(working: Int = 0, needsInput: Int = 0, idle: Int = 0) {
        self.working = working
        self.needsInput = needsInput
        self.idle = idle
    }

    public var active: Int { working + needsInput + idle }

    /// The single state the icon shows. "Needs you" wins over everything.
    public var dominantPhase: SessionPhase? {
        if needsInput > 0 { return .needsInput }
        if working > 0 { return .working }
        if idle > 0 { return .idle }
        return nil
    }
}

/// Side effects the app should perform after an event (notifications).
public enum PatterEffect: Equatable, Sendable {
    case needsInput(sessionID: String, project: String, message: String)
    case finished(sessionID: String, project: String, duration: TimeInterval, tasks: TaskProgress?)
}
