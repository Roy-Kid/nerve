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

        tunnels.start()

        expireTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.expireStalePendingActions()
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

    func openJobFromNotification(_ jobId: String) {
        store.focusJob(id: jobId)
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
