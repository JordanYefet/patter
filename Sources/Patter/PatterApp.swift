import AppKit
import ServiceManagement
import SwiftUI
import PatterCore

@main
struct PatterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, even when run via `swift run`.
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated { AppModel.shared.start() }
    }
}

/// Settings, drawn in the current theme. Not a `Form`: on macOS a grouped
/// Form ignores `listRowBackground`, so its rows stay in system colors.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var systemScheme
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    // Everything reads `Theme` here in `body`, which reruns when `model.theme`
    // changes, so there's no `.id(model.theme)`: rebuilding the tree would
    // replace the theme picker while its menu is still closing.
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Show") {
                toggleRow("Floating HUD", $model.showHUD)
                rowDivider
                toggleRow("In the notch", $model.showNotch, enabled: NotchController.hasNotch)
                    .help(NotchController.hasNotch ? "" : "This Mac's display has no notch")
            }
            section("Appearance") {
                row("Theme") {
                    Picker("Theme", selection: $model.theme) {
                        ForEach(ThemeChoice.allCases.filter(\.isAvailable)) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                rowDivider
                row("Menu bar icon") {
                    Picker("Menu bar icon", selection: $model.menuBarIconStyle) {
                        ForEach(MenuBarIconStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                rowDivider
                toggleRow("Animate the menu bar icon", $model.menuBarAnimation)
                    .help("Clawd walks in the menu bar while a session works")
            }
            section("Notifications") {
                toggleRow("When a session needs you", $model.notifyNeedsInput)
                rowDivider
                toggleRow("When a session finishes", $model.notifyFinished)
                rowDivider
                row("Only for turns longer than \(Int(model.notifyAfterSeconds))s", enabled: model.notifyFinished) {
                    Stepper("Seconds", value: $model.notifyAfterSeconds, in: 0...600, step: 10)
                        .labelsHidden()
                }
            }
            section("General") {
                toggleRow("Launch at login", $launchAtLogin, enabled: Bundle.main.bundleIdentifier != nil)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                rowDivider
                row("Spool folder") {
                    Text((SpoolReader.defaultDirectory.path as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            rowDivider.padding(.horizontal, -12)
            about
        }
        .padding(20)
        // Sized to its content, so every section shows without scrolling.
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        // Liquid Glass keeps its controls in the text color rather than the
        // accent, so the window reads as one glass sheet.
        .tint(Theme.isGlass ? Theme.text : Theme.accent)
        // Under the transparent title bar too (the window has a full-size
        // content view), so the whole window is one surface.
        .background { SettingsSurface().ignoresSafeArea() }
        .background(SettingsWindowStyler(theme: model.theme))
        // Same as `.themeColorScheme()`, but without its if/else: switching to
        // or from Liquid Glass would otherwise rebuild the whole tree too.
        .environment(\.colorScheme, Theme.colorScheme ?? systemScheme)
    }

    /// Who made it, at the bottom, out of the way of the settings.
    private var about: some View {
        HStack(spacing: 12) {
            PatterLogo(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Patter").font(.headline)
                    Spacer()
                    if let version {
                        Text("Version: \(version)").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.bottom, 4)
                Text("Created by Jordan Yefet Berman").foregroundStyle(Theme.textSecondary)
                Link("github.com/JordanYefet/patter", destination: URL(string: "https://github.com/JordanYefet/patter")!)
                    .font(.callout)
                    .foregroundStyle(Theme.accentText)
            }
        }
        .padding(.horizontal, 12)
    }

    /// A titled card of rows, like a grouped Form section.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
            VStack(spacing: 0) { content() }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// A label and its control. A disabled row dims its label too, as a Form does.
    private func row<Control: View>(_ title: String, enabled: Bool = true, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(title).opacity(enabled ? 1 : 0.5)
            Spacer(minLength: 0)
            control()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .disabled(!enabled)
    }

    private var rowDivider: some View {
        Rectangle().fill(Theme.palette.separator).frame(height: 1).padding(.horizontal, 12)
    }

    private func toggleRow(_ title: String, _ isOn: Binding<Bool>, enabled: Bool = true) -> some View {
        row(title, enabled: enabled) {
            Toggle(title, isOn: isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
    }
}

/// The whole Settings window's background: the panel color, or one pane of
/// Liquid Glass (the cards on it are flat, never glass inside glass).
private struct SettingsSurface: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        #if compiler(>=6.2)
        if Theme.isGlass, #available(macOS 26, *) {
            let tint = scheme == .dark ? Theme.palette.glassTint.dark : Theme.palette.glassTint.light
            Color.clear.glassEffect(.regular.tint(tint), in: Rectangle())
        } else {
            Theme.panel
        }
        #else
        Theme.panel
        #endif
    }
}

/// Fits the Settings window's chrome to the theme: a transparent title bar
/// over a full-size content view, so SettingsSurface fills the window. Solid
/// themes force their appearance (so popup menus match too); Liquid Glass
/// makes the window itself clear so the glass shows the desktop behind it.
private struct SettingsWindowStyler: NSViewRepresentable {
    let theme: ThemeChoice

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let palette = theme.palette
        // The view isn't in its window yet on the first pass.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.isOpaque = !palette.glass
            window.backgroundColor = palette.glass ? .clear : NSColor(palette.panel)
            window.appearance = switch palette.colorScheme {
            case .dark: NSAppearance(named: .darkAqua)
            case .light: NSAppearance(named: .aqua)
            default: nil
            }
        }
    }
}
