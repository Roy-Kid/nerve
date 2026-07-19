import SwiftUI
import AppKit

@main
struct NerveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No floating windows / MenuBarExtra.
        // Ribbon + left-click status + right-click → Settings window are AppKit status item.
        Settings {
            // Secondary path (e.g. system Settings). Primary UI is the status-item menu.
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `nil` is the AppKit contract for inheriting the current macOS appearance.
        // Keep this app system-driven; individual windows and popovers inherit it.
        NSApp.appearance = nil
        NSApp.setActivationPolicy(.accessory)
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.quit() // stop ingest + remove status item only
    }
}
