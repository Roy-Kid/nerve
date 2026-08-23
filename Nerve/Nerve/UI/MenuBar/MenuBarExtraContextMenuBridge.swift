import AppKit
import SwiftUI

// MARK: - MenuBarExtra right-click (Settings / Quit)

/// SwiftUI `MenuBarExtra` + `.window` style does **not** reliably deliver
/// `.contextMenu` on the label. Secondary-click is intercepted here with AppKit
/// so the ribbon still offers Settings… and Quit.
@MainActor
final class MenuBarExtraContextMenuBridge: NSObject {
    private let openSettings: () -> Void
    private var monitor: Any?
    private var menu: NSMenu?

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()
        rebuildMenu()
    }

    func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .leftMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.isMenuBarItemEvent(event) else { return event }

            let secondary =
                event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard secondary else { return event }

            self.popupMenu()
            // Swallow so MenuBarExtra does not open/toggle the status panel.
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsAction(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Nerve",
            action: #selector(quitAction(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
    }

    private func popupMenu() {
        guard let menu else { return }
        // Screen coordinates when `in:` is nil — sits under the cursor on the ribbon.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// MenuBarExtra’s status item lives in a private status-bar window owned by this process.
    private func isMenuBarItemEvent(_ event: NSEvent) -> Bool {
        if let window = event.window {
            let name = NSStringFromClass(type(of: window))
            if name.contains("StatusBar") || name.contains("StatusItem") {
                return true
            }
        }

        // Fallback: hit-test any of our short, menu-bar-level windows (the ribbon).
        let point = NSEvent.mouseLocation
        for window in NSApp.windows {
            let name = NSStringFromClass(type(of: window))
            let isStatusChrome =
                name.contains("StatusBar")
                || name.contains("StatusItem")
                || (window.level.rawValue >= NSWindow.Level.statusBar.rawValue
                    && window.frame.height <= 32
                    && window.frame.width <= 320
                    && window.isVisible)
            guard isStatusChrome, window.frame.contains(point) else { continue }
            return true
        }
        return false
    }

    @objc private func openSettingsAction(_ sender: Any?) {
        openSettings()
    }

    @objc private func quitAction(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
