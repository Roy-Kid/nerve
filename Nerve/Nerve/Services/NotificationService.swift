import Foundation
import UserNotifications
import AppKit

/// macOS notifications for high-signal job changes. Deduped; never spams heartbeats.
///
/// Ask channel: `reason ∈ Ask` and `level ≥ suggested` on upgrade/first sight.
/// Wait / informational chatter paints Attention but does not interrupt.
/// Fires on structured facet transitions only — never free-text.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let settings: SettingsStore
    private let center = UNUserNotificationCenter.current()

    private var lastFire: [String: Date] = [:]
    private let dedupeInterval: TimeInterval = 120

    /// Select + Open the job (AppModel wires focusAndOpenJob).
    var onOpenJob: ((String) -> Void)?
    /// Best-effort show the status panel after a banner click.
    var onRevealPanel: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { [weak self] settings in
            let authorizationStatus = settings.authorizationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch authorizationStatus {
                case .notDetermined:
                    do {
                        let granted = try await self.center.requestAuthorization(options: [.alert, .sound, .badge])
                        if !granted {
                            NerveLog.notify.error("notification auth: user denied")
                        }
                    } catch {
                        NerveLog.notify.error("notification auth: \(String(describing: error), privacy: .public)")
                    }
                case .denied:
                    NerveLog.notify.error("notifications denied — enable in System Settings → Notifications → Nerve")
                default:
                    break
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

        // Ask channel — input / review / decision / approval. Soft by default.
        if Job.shouldNotifyAsk(previous: previous, next: next) {
            let level = next.attention.level
            switch level {
            case .urgent:
                if settings.notifyUrgent {
                    let copy = next.askNotificationCopy(forceUrgentTone: true)
                    notify(
                        subject: next,
                        kind: "attention.urgent",
                        title: copy.title,
                        body: copy.body,
                        playSound: settings.notificationSoundEnabled
                    )
                }
            case .required:
                if settings.notifyRequired {
                    let copy = next.askNotificationCopy()
                    notify(
                        subject: next,
                        kind: "attention.required",
                        title: copy.title,
                        body: copy.body,
                        playSound: settings.notificationSoundEnabled
                    )
                }
            case .suggested:
                // Settings “Your turn” covers Ask at suggested+.
                // Suggested stays silent even when Play sounds is on.
                if settings.notifyRequired {
                    let copy = next.askNotificationCopy()
                    notify(
                        subject: next,
                        kind: "attention.suggested",
                        title: copy.title,
                        body: copy.body,
                        playSound: false
                    )
                }
            case .informational, .none:
                break
            }
        }

        // Outcome failure (session/job ended badly).
        if settings.notifyFailure,
           next.outcome == .failure,
           previous?.outcome != .failure {
            notify(
                subject: next,
                kind: "outcome.failure",
                title: "Failed: \(next.name)",
                body: next.current?.summary ?? next.outcome?.rawValue ?? "",
                playSound: settings.notificationSoundEnabled
            )
        }

        // Active-session tool / turn failure (hook sets attention.reason=failure, not outcome).
        if settings.notifyFailure,
           next.attention.reason?.lowercased() == "failure",
           previous?.attention.reason?.lowercased() != "failure" {
            notify(
                subject: next,
                kind: "attention.failure",
                title: next.attention.title ?? "Failed: \(next.name)",
                body: next.attention.summary ?? next.current?.summary ?? "",
                playSound: settings.notificationSoundEnabled
            )
        }

        if settings.notifyUnresponsive,
           next.health == .unresponsive,
           previous?.health != .unresponsive {
            notify(
                subject: next,
                kind: "health.unresponsive",
                title: "Unresponsive: \(next.name)",
                body: next.current?.summary ?? "No recent updates",
                playSound: settings.notificationSoundEnabled
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
                    body: next.current?.summary ?? "",
                    playSound: settings.notificationSoundEnabled
                )
            }
        }

        // Clear sticky attention banners once the job no longer needs the user.
        if let previous,
           previous.isAskElevated,
           !next.isAskElevated {
            removeDelivered(
                subjectId: next.id,
                kinds: ["attention.urgent", "attention.required", "attention.suggested"]
            )
        }
    }

    private func notify(
        subject: Job,
        kind: String,
        title: String,
        body: String,
        playSound: Bool
    ) {
        let key = "\(subject.id)|\(kind)"
        let now = Date()
        if let last = lastFire[key], now.timeIntervalSince(last) < dedupeInterval {
            return
        }
        lastFire[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        // Empty body is legal but some macOS versions hide the banner without it.
        content.body = body.isEmpty ? title : body
        content.sound = playSound ? .default : nil
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
                NerveLog.notify.error("notify failed: \(String(describing: error), privacy: .public)")
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
            Task { @MainActor in
                self.center.removeDeliveredNotifications(withIdentifiers: ids)
            }
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
            } else {
                self.onRevealPanel?()
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Menu-bar apps stay "foreground"; still show banners.
        completionHandler([.banner, .sound, .list])
    }
}
