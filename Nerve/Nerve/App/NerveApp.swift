import SwiftUI
import AppKit

@main
struct NerveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No floating windows / MenuBarExtra.
        // Ribbon + left-click status + right-click → Preferences window are AppKit status item.
        Settings {
            // Secondary path (e.g. system Settings). Primary UI is PreferencesWindowController.
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.quit() // stop ingest + remove status item only
    }
}
