import SwiftUI
import PatterCore

/// The dropdown under the menu bar icon.
struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings

    private var needsYou: [Session] { model.sessions.filter { $0.phase == .needsInput } }
    private var working: [Session] { model.sessions.filter { $0.phase == .working } }
    private var idle: [Session] { model.sessions.filter { $0.phase == .idle } }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header

            UsageView(usage: model.usage)
                .padding(.horizontal, 6)
                .padding(.bottom, 4)

            if model.sessions.isEmpty {
                emptyState
            } else {
                section("Needs you", needsYou)
                section("Working", working)
                section("Recent", idle)
            }

            Divider().overlay(Theme.palette.separator).padding(.vertical, 6).padding(.horizontal, 8)

            Toggle("Floating HUD", isOn: $model.showHUD).toggleStyle(MenuToggleStyle())
            if NotchController.hasNotch {
                Toggle("Show in notch", isOn: $model.showNotch).toggleStyle(MenuToggleStyle())
            }
            Button {
                // Patter is a menu-bar-only app that's never active on its own,
                // so the Settings window would open but stay hidden. Activate first.
                NSApp.activate()
                openSettings()
            } label: {
                MenuItemLabel(title: "Settings…", shortcut: "⌘,")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            Button { NSApp.terminate(nil) } label: {
                MenuItemLabel(title: "Quit Patter", shortcut: "⌘Q")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(6)
        .frame(width: 392)
        .background { menuBackground }
        .foregroundStyle(Theme.text)
        .themeColorScheme()
        // Theme is a static the views below don't observe: rebuild on change.
        .id(model.theme)
    }

    /// Solid themes paint over the window's own material. Glass leaves it
    /// alone: on macOS 26 the system already puts the menu on glass, and a
    /// second pane of glass (or a fill) on top would just look frosted.
    @ViewBuilder
    private var menuBackground: some View {
        if !Theme.isGlass { Theme.panel }
    }

    private var header: some View {
        HStack {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Patter").font(.system(size: 13, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button {
                model.notificationsMuted.toggle()
            } label: {
                Image(systemName: model.notificationsMuted ? "bell.slash" : "bell")
                    .frame(width: 32, height: 32)
                    .chipSurface(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .help(model.notificationsMuted ? "Unmute notifications" : "Mute notifications")
            .accessibilityLabel(model.notificationsMuted ? "Unmute notifications" : "Mute notifications")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        let s = model.summary
        if s.active == 0 { return "No sessions" }
        var parts = ["\(s.active) active"]
        if s.needsInput > 0 { parts.append("\(s.needsInput) need\(s.needsInput == 1 ? "s" : "") you") }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No Claude Code sessions yet").font(.system(size: 12, weight: .semibold))
            Text("Start `claude` in a terminal. If nothing shows up, run scripts/install.sh and restart the session.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Session]) -> some View {
        if !items.isEmpty {
            SectionLabel(text: title)
            ForEach(items) { session in
                SessionRow(session: session, style: .full) { model.open($0) }
            }
        }
    }
}

private struct MenuItemLabel: View {
    let title: String
    var shortcut: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let shortcut { Text(shortcut).foregroundStyle(Theme.textTertiary) }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .modifier(MenuItemHighlight())
    }
}

/// The hover highlight on a menu item.
private struct MenuItemHighlight: ViewModifier {
    @State private var hovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .background(hovering ? Theme.card : .clear, in: shape)
            .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct MenuToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer()
                if configuration.isOn {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accentText)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .modifier(MenuItemHighlight())
        }
        .buttonStyle(.plain)
    }
}
