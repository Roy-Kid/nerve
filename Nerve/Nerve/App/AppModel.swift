import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    let store: SubjectStore
    let settings: SettingsStore
    private var menuBar: MenuBarRibbonController?
    private var ingest: IngestServer?
    private var notifications: NotificationService?
    private var coach: FirstRunCoachController?
    private var expireTimer: Timer?

    init() {
        let settings = SettingsStore()
        let store = SubjectStore()
        self.settings = settings
        self.store = store
        store.settingsProvider = { [weak self] in
            self?.settings ?? SettingsStore()
        }
    }

    func start() {
        let notifications = NotificationService(settings: settings)
        self.notifications = notifications
        notifications.requestAuthorizationIfNeeded()
        notifications.onOpenSubject = { [weak self] subjectId in
            self?.openSubjectFromNotification(subjectId)
        }

        store.notificationSink = { [weak self] before, next in
            self?.notifications?.evaluate(previous: before, next: next)
        }

        let menuBar = MenuBarRibbonController(store: store, settings: settings)
        self.menuBar = menuBar
        // Immediate ribbon redraw when subjects change (not only the 0.5s timer)
        store.ribbonInvalidationSink = { [weak menuBar] in
            menuBar?.refresh(force: true)
        }
        // Group mode / ribbon size / colors — independent of whether the panel is open
        settings.ribbonAppearanceSink = { [weak menuBar] in
            menuBar?.refresh(force: true)
        }
        menuBar.start()

        let server = IngestServer(port: settings.ingestPort, store: store)
        self.ingest = server
        server.start()

        expireTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.expireStalePendingActions()
            }
        }

        // First-run coach (skippable). Demo only if user chooses or legacy empty first launch.
        if !settings.hasSeenCoachMarks {
            let coach = FirstRunCoachController()
            self.coach = coach
            coach.show { [weak self] loadDemo in
                guard let self else { return }
                self.settings.hasSeenCoachMarks = true
                self.settings.hasCompletedFirstRun = true
                if loadDemo {
                    self.store.loadDemo()
                    self.menuBar?.refresh()
                }
            }
        } else if !settings.hasCompletedFirstRun {
            settings.hasCompletedFirstRun = true
        }
    }

    func openSubjectFromNotification(_ subjectId: String) {
        store.focusSubject(id: subjectId)
        menuBar?.showStatusPopover()
        menuBar?.refresh()
    }

    func togglePanel() {
        menuBar?.toggleStatusPopover()
    }

    func refreshRibbon() {
        menuBar?.refresh(force: true)
    }

    func quit() {
        expireTimer?.invalidate()
        expireTimer = nil
        ingest?.stop()
        menuBar?.stop()
    }
}
