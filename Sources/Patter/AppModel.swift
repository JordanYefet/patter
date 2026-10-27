import AppKit
import Combine
import PatterCore

/// Owns the store, watches the spool directory and publishes state to the UI.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var usage: UsageLimits?
    @Published private(set) var summary = PatterSummary()

    // Preferences (persisted in UserDefaults).
    @Published var showHUD: Bool { didSet { defaults.set(showHUD, forKey: Keys.showHUD); hud.setVisible(showHUD) } }
    @Published var showNotch: Bool { didSet { defaults.set(showNotch, forKey: Keys.showNotch); notch.setVisible(showNotch) } }
    @Published var notifyNeedsInput: Bool { didSet { defaults.set(notifyNeedsInput, forKey: Keys.notifyNeedsInput) } }
    @Published var notifyFinished: Bool { didSet { defaults.set(notifyFinished, forKey: Keys.notifyFinished) } }
    @Published var notificationsMuted = false
    @Published var notifyAfterSeconds: Double {
        didSet {
            defaults.set(notifyAfterSeconds, forKey: Keys.notifyAfter)
            store.notifyFinishedAfter = notifyAfterSeconds
        }
    }

    let notifier = Notifier()
    private(set) lazy var hud = HUDController(model: self)
    private(set) lazy var notch = NotchController(model: self)

    private let store = SessionStore()
    private let reader = SpoolReader(directory: SpoolReader.defaultDirectory)
    private let defaults = UserDefaults.standard
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var pendingRefresh = false
    private let launchedAt = Date()

    private enum Keys {
        static let showHUD = "showHUD"
        static let showNotch = "showNotch"
        static let notifyNeedsInput = "notifyNeedsInput"
        static let notifyFinished = "notifyFinished"
        static let notifyAfter = "notifyAfterSeconds"
        static let migratedFromCCPulse = "migratedFromCCPulse"
    }

    /// One-time migration from the CC Pulse name; remove after a while.
    /// Copies the user's toggles from the old defaults domain. Window frames
    /// are left behind on purpose (the HUD position resets).
    private static func migrateFromCCPulse(into d: UserDefaults) {
        guard !d.bool(forKey: Keys.migratedFromCCPulse) else { return }
        d.set(true, forKey: Keys.migratedFromCCPulse)
        guard let old = UserDefaults(suiteName: "io.github.cc-pulse") else { return }
        let keys = [Keys.showHUD, Keys.showNotch, Keys.notifyNeedsInput, Keys.notifyFinished, Keys.notifyAfter, "hudCollapsed"]
        for key in keys where d.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { d.set(value, forKey: key) }
        }
    }

    private init() {
        // A local: `self.defaults` can't be read until every stored property is set.
        let d = UserDefaults.standard
        Self.migrateFromCCPulse(into: d)
        d.register(defaults: [
            Keys.showHUD: false,
            // On by default; NotchController only shows it while a notched screen exists.
            Keys.showNotch: true,
            Keys.notifyNeedsInput: true,
            Keys.notifyFinished: true,
            Keys.notifyAfter: 30.0,
        ])
        showHUD = d.bool(forKey: Keys.showHUD)
        showNotch = d.bool(forKey: Keys.showNotch)
        notifyNeedsInput = d.bool(forKey: Keys.notifyNeedsInput)
        notifyFinished = d.bool(forKey: Keys.notifyFinished)
        notifyAfterSeconds = d.double(forKey: Keys.notifyAfter)
        store.notifyFinishedAfter = notifyAfterSeconds
    }

    func start() {
        reader.ensureDirectory()
        notifier.requestAuthorization()
        refresh()
        watchSpool()
        // Fallback tick: catches anything the watcher missed and prunes dead sessions.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        hud.setVisible(showHUD)
        notch.setVisible(showNotch)
    }

    /// Drain the spool, apply events, publish.
    func refresh() {
        pendingRefresh = false
        let events = reader.drain()
        for event in events {
            let effects = store.apply(event)
            // Don't replay notifications for events that piled up while the app was closed.
            guard event.time > launchedAt.addingTimeInterval(-10) else { continue }
            deliver(effects)
        }
        store.prune(now: Date(), isAlive: ProcessProbe.isAlive)
        publish()
    }

    func open(_ session: Session) {
        TerminalActivator.activate(terminal: session.terminal)
    }

    private func deliver(_ effects: [PatterEffect]) {
        guard !notificationsMuted else { return }
        for effect in effects {
            switch effect {
            case .needsInput where notifyNeedsInput, .finished where notifyFinished:
                notifier.post(effect)
            default:
                break
            }
        }
    }

    private func publish() {
        let ordered = store.orderedSessions
        if ordered != sessions { sessions = ordered }
        if store.usage != usage { usage = store.usage }
        let newSummary = store.summary
        if newSummary != summary { summary = newSummary }
    }

    private func watchSpool() {
        let fd = Darwin.open(reader.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            // Coalesce bursts (a tool call produces Pre + Post + status within ms).
            MainActor.assumeIsolated {
                guard let self, !self.pendingRefresh else { return }
                self.pendingRefresh = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}

enum ProcessProbe {
    /// True if the process exists (EPERM still means it exists).
    static func isAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
