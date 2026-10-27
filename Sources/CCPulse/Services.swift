import AppKit
import PulseCore
import UserNotifications

/// macOS notifications. Only works when running from the .app bundle
/// (scripts/bundle.sh): UNUserNotificationCenter needs a bundle identifier,
/// so under `swift run` this quietly does nothing.
final class Notifier {
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ effect: PulseEffect) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        let id: String
        switch effect {
        case let .needsInput(sessionID, project, message):
            content.title = "\(project) needs you"
            content.body = message
            content.sound = .default
            id = "needs-\(sessionID)"
        case let .finished(sessionID, project, duration, tasks):
            content.title = "\(project) is done"
            var body = "Finished in \(Format.duration(duration))"
            if let tasks, tasks.total > 0 { body += " · \(tasks.done)/\(tasks.total) tasks" }
            content.body = body
            id = "done-\(sessionID)"
        }
        // Same identifier per session: a newer notification replaces the older one.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

/// Brings the session's terminal app to the front.
///
/// v1 activates the app, not the exact tab/pane: that needs per-terminal
/// AppleScript (see the roadmap in README.md).
enum TerminalActivator {
    /// $TERM_PROGRAM -> bundle identifier.
    static let bundleIDs: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "vscode": "com.microsoft.VSCode",
        "WezTerm": "com.github.wez.wezterm",
        "kitty": "net.kovidgoyal.kitty",
        "Hyper": "co.zeit.hyper",
        "zed": "dev.zed.Zed",
    ]

    static func activate(terminal: String?) {
        guard let terminal, let bundleID = bundleIDs[terminal] else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        }
    }
}
