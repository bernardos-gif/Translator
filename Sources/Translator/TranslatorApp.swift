import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare binary (`swift run`) instead of a .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Double-clicking an .exe in Finder (or dropping it on the Dock icon) lands here.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            AppModel.shared.openExternally(urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Translator") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 620)
                .tint(Theme.violet)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Bottle…") { model.showNewBottle = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(model.needsSetup)
                Button("Install or Run Windows Program…") { model.chooseAndRun() }
                    .keyboardShortcut("o")
                    .disabled(model.needsSetup)
            }
            CommandGroup(after: .sidebar) {
                Button("Library") { model.sidebar = .library }
                    .keyboardShortcut("1")
                Button(model.showLog ? "Hide Log" : "Show Log") { model.showLog.toggle() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Refresh Library") { model.refreshAllPrograms() }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .tint(Theme.violet)
        }
    }
}
