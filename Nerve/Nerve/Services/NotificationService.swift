import Foundation
import UserNotifications
import AppKit

/// macOS notifications for high-signal Subject changes. Deduped; never spams heartbeats.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let settings: SettingsStore
    private let center = UNUserNotificationCenter.current()

    private var lastFire: [String: Date] = [:]
    private let dedupeInterval: TimeInterval = 120

    var onOpenJob: ((String) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
                if let error {
                    NSLog("[Nerve] notification auth: %@", "\(error)")
                }
            }
        }
    }

    func evaluate(previous: Job?, next: Job) {
        guard settings.shouldDeliverNotifications(at: Date()) else { return }
        if settings.mutedSourceIds.contains(next.producer.id) { return }
        if let project = next.context?.project, settings.mutedProjectIds.contains(project) {
            return
        }
        if let workspace = next.context?.workspace, settings.mutedProjectIds.contains(workspace) {
            return
        }

        if next.attention.level >= .required {
            let prevLevel = previous?.attention.level ?? .none
            if next.attention.level > prevLevel || previous == nil {
                if next.attention.level == .urgent, settings.notifyUrgent {
                    notify(
                        subject: next,
                        kind: "attention.urgent",
                        title: next.attention.title ?? "Urgent: \(next.name)",
                        body: next.attention.summary ?? next.displaySummary
                    )
                } else if next.attention.level == .required, settings.notifyRequired {
                    notify(
                        subject: next,
                        kind: "attention.required",
                        title: next.attention.title ?? "Needs you: \(next.name)",
                        body: next.attention.summary ?? next.displaySummary
                    )
                }
            }
        }

        if settings.notifyFailure,
           next.outcome == .failure,
           previous?.outcome != .failure {
            notify(
                subject: next,
                kind: "outcome.failure",
                title: "Failed: \(next.name)",
                body: next.displaySummary
            )
        }

        if settings.notifyUnresponsive,
           next.health == .unresponsive,
           previous?.health != .unresponsive {
            notify(
                subject: next,
                kind: "health.unresponsive",
                title: "Unresponsive: \(next.name)",
                body: next.current?.summary ?? "No recent updates"
            )
        }

        if settings.notifyLongSuccess,
           next.lifecycle == .ended,
           next.outcome == .success,
           previous?.lifecycle != .ended {
            let start = next.startedAt ?? next.createdAt
            let end = next.endedAt ?? Date()
            if end.timeIntervalSince(start) >= settings.longTaskSuccessThresholdSeconds {
                notify(
                    subject: next,
                    kind: "outcome.long_success",
                    title: "Completed: \(next.name)",
                    body: next.displaySummary
                )
            }
        }

        if let previous,
           previous.attention.level >= .required,
           next.attention.level < .required {
            removeDelivered(subjectId: next.id, kinds: ["attention.urgent", "attention.required"])
        }
    }

    private func notify(subject: Job, kind: String, title: String, body: String) {
        let key = "\(subject.id)|\(kind)"
        let now = Date()
        if let last = lastFire[key], now.timeIntervalSince(last) < dedupeInterval {
            return
        }
        lastFire[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = settings.notificationSoundEnabled ? .default : nil
        content.userInfo = [
            "subjectId": subject.id,
            "kind": kind,
        ]
        content.threadIdentifier = subject.id

        let request = UNNotificationRequest(
            identifier: "\(key)|\(Int(now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                NSLog("[Nerve] notify failed: %@", "\(error)")
            }
        }
    }

    private func removeDelivered(subjectId: String, kinds: [String]) {
        center.getDeliveredNotifications { notes in
            let ids = notes.compactMap { note -> String? in
                let info = note.request.content.userInfo
                guard let sid = info["subjectId"] as? String, sid == subjectId else { return nil }
                guard let kind = info["kind"] as? String, kinds.contains(kind) else { return nil }
                return note.request.identifier
            }
            self.center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let subjectId = info["subjectId"] as? String
        Task { @MainActor in
            if let subjectId {
                self.onOpenJob?(subjectId)
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
