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

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Show") {
                Toggle("Floating HUD", isOn: $model.showHUD)
                Toggle("In the notch", isOn: $model.showNotch)
                    .disabled(!NotchController.hasNotch)
                    .help(NotchController.hasNotch ? "" : "This Mac's display has no notch")
            }
            Section("Appearance") {
                Picker("Theme", selection: $model.theme) {
                    ForEach(ThemeChoice.allCases.filter(\.isAvailable)) { Text($0.title).tag($0) }
                }
                Picker("Menu bar icon", selection: $model.menuBarIconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Animate the menu bar icon", isOn: $model.menuBarAnimation)
                    .help("Clawd walks in the menu bar while a session works")
            }
            Section("Notifications") {
                Toggle("When a session needs you", isOn: $model.notifyNeedsInput)
                Toggle("When a session finishes", isOn: $model.notifyFinished)
                Stepper(value: $model.notifyAfterSeconds, in: 0...600, step: 10) {
                    Text("Only for turns longer than \(Int(model.notifyAfterSeconds))s")
                }
                .disabled(!model.notifyFinished)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                    .disabled(Bundle.main.bundleIdentifier == nil)
                LabeledContent("Spool folder", value: SpoolReader.defaultDirectory.path)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, 8)
    }
}
