import SwiftUI
import AppKit

@main
struct NerveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var menuBarItemEnabled = true

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInsertion) {
            StatusPanelRoot(
                store: appDelegate.model.store,
                settings: appDelegate.model.settings
            )
        } label: {
            MenuBarRibbonLabel(
                store: appDelegate.model.store,
                settings: appDelegate.model.settings
            )
            // Right-click menu is installed via AppKit
            // (`MenuBarExtraContextMenuBridge`) — SwiftUI `.contextMenu` on the
            // label is unreliable with `.menuBarExtraStyle(.window)`.
            .help("Nerve — click for status, right-click for Settings")
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(
                store: appDelegate.model.store,
                settings: appDelegate.model.settings,
                tunnels: appDelegate.model.tunnels
            )
        }
    }

    private var menuBarInsertion: Binding<Bool> {
        Binding(
            get: {
                menuBarItemEnabled
                    && (!appDelegate.model.settings.hideWhenIdle
                        || appDelegate.model.store.activeCount > 0)
            },
            set: { menuBarItemEnabled = $0 }
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var ribbonContextMenu: MenuBarExtraContextMenuBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `nil` is the AppKit contract for inheriting the current macOS appearance.
        // Keep this app system-driven; individual windows and popovers inherit it.
        NSApp.appearance = nil
        NSApp.setActivationPolicy(.accessory)
        model.start()

        // MenuBarExtra(.window) does not honor label context menus — install AppKit bridge.
        let bridge = MenuBarExtraContextMenuBridge { [weak self] in
            guard let self else { return }
            PreferencesWindowController.show(
                store: self.model.store,
                settings: self.model.settings,
                tunnels: self.model.tunnels
            )
        }
        bridge.start()
        ribbonContextMenu = bridge
    }

    func applicationWillTerminate(_ notification: Notification) {
        ribbonContextMenu?.stop()
        ribbonContextMenu = nil
        model.quit()
    }
}
