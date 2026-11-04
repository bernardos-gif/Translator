import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare binary (`swift run`) instead of a .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct VPNApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = VPNModel.shared

    var body: some Scene {
        WindowGroup("VPN") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 600)
                .tint(Theme.teal)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Device…") { model.showAddDevice = true }
                    .keyboardShortcut("n")
                    .disabled(model.phase != .ready)
                Button("Refresh") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(model.phase != .ready)
            }
        }
    }
}
