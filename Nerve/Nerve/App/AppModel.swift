import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    let store: JobStore
    let settings: SettingsStore
    let tunnels: MachineTunnelManager
    private var ingest: IngestServer?
    private var notifications: NotificationService?
    private var coach: FirstRunCoachController?
    private var expireTimer: Timer?
    private var started = false

    init() {
        let settings = SettingsStore()
        let store = JobStore()
        let tunnels = MachineTunnelManager()
        self.settings = settings
        self.store = store
        self.tunnels = tunnels
        store.settingsProvider = { [weak self] in
            self?.settings ?? SettingsStore()
        }
        tunnels.attach(settings: settings)
    }

    func start() {
        guard !started else { return }
        started = true

        let notifications = NotificationService(settings: settings)
        self.notifications = notifications
        notifications.requestAuthorizationIfNeeded()
        notifications.onOpenJob = { [weak self] jobId in
            self?.openJobFromNotification(jobId)
        }
        // Panel deep-link helper used when a banner is clicked.
        notifications.onRevealPanel = { [weak self] in
            self?.revealStatusPanelBestEffort()
        }

        store.notificationSink = { [weak self] before, next in
            self?.notifications?.evaluate(previous: before, next: next)
        }

        // SwiftUI observes the store and settings directly for MenuBarExtra updates.
        store.ribbonInvalidationSink = nil
        settings.ribbonAppearanceSink = nil

        let server = IngestServer(
            port: settings.ingestPort,
            store: store,
            settingsProvider: { [weak self] in self?.settings }
        )
        self.ingest = server
        server.start()

        // Drop any leftover per-subagent rows from older hooks still in memory.
        store.purgeAllLegacyChildJobs()

        tunnels.start()

        // 5s: pending-action expiry + local PID reaping (closed terminal / kill).
        expireTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.runMaintenanceTick()
            }
        }

        if !settings.hasSeenCoachMarks {
            let coach = FirstRunCoachController()
            self.coach = coach
            coach.show { [weak self] loadDemo in
                guard let self else { return }
                self.settings.hasSeenCoachMarks = true
                self.settings.hasCompletedFirstRun = true
                if loadDemo {
                    self.store.loadDemo()
                }
            }
        } else if !settings.hasCompletedFirstRun {
            settings.hasCompletedFirstRun = true
        }
    }

    /// Banner click: select + expand the job, Open/Focus the agent workspace, try to show panel.
    func openJobFromNotification(_ jobId: String) {
        _ = store.focusAndOpenJob(id: jobId)
        revealStatusPanelBestEffort()
    }

    /// Best-effort: click the MenuBarExtra status item so the panel appears with the job expanded.
    /// MenuBarExtra has no public open API — we locate our status-bar chrome and performClick.
    private func revealStatusPanelBestEffort() {
        NSApp.activate(ignoringOtherApps: true)
        // If the panel is already up, selectedJobId + onChange expands the row.
        if store.panelOpen { return }

        // Prefer a visible status-item button owned by this process.
        for window in NSApp.windows {
            let name = NSStringFromClass(type(of: window))
            guard name.contains("StatusBar") || name.contains("StatusItem") else { continue }
            if let button = window.contentView?.subviews.compactMap({ $0 as? NSStatusBarButton }).first
                ?? window.contentView as? NSStatusBarButton {
                button.performClick(nil)
                return
            }
            // Fallback: synthesize a click at the window center (status item).
            let frame = window.frame
            let point = NSPoint(x: frame.midX, y: frame.midY)
            if let event = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: window.convertPoint(fromScreen: point),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ) {
                window.sendEvent(event)
            }
            if let up = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: window.convertPoint(fromScreen: point),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ) {
                window.sendEvent(up)
            }
            return
        }
    }

    /// Call after Settings mutates the machine list.
    func machinesDidChange() {
        tunnels.syncConfig()
        tunnels.reconnectAllEnabled()
    }

    func quit() {
        guard started else { return }
        started = false
        expireTimer?.invalidate()
        expireTimer = nil
        tunnels.stopAll()
        ingest?.stop()
    }
}
