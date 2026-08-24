import Foundation
import UserNotifications
import AppKit

/// macOS notifications for high-signal job changes. Deduped; never spams heartbeats.
///
/// Fires on structured facet transitions only (attention / outcome / health) — never free-text.
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
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        NSLog("[Nerve] notification auth: %@", "\(error)")
                    } else if !granted {
                        NSLog("[Nerve] notification auth: user denied")
                    }
                }
            case .denied:
                NSLog("[Nerve] notifications denied — enable in System Settings → Notifications → Nerve")
            default:
                break
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

        let prevLevel = previous?.attention.level ?? .none
        let nextLevel = next.attention.level

        // Attention escalations.
        // Hooks use `suggested` for Stop / idle_prompt (your turn) and `required`
        // for permission prompts. Both paint Status.attention — both should notify.
        if nextLevel > prevLevel || (previous == nil && nextLevel >= .suggested) {
            switch nextLevel {
            case .urgent:
                if settings.notifyUrgent {
                    notify(
                        subject: next,
                        kind: "attention.urgent",
                        title: next.attention.title ?? "Urgent: \(next.name)",
                        body: next.attention.summary ?? next.current?.summary ?? ""
                    )
                }
            case .required, .suggested:
                // Settings “Needs attention” covers suggested + required.
                if settings.notifyRequired {
                    let kind = nextLevel == .required ? "attention.required" : "attention.suggested"
                    // Honest: user acts in the agent UI — Nerve only points them there.
                    let fallbackTitle: String = {
                        if next.attention.reason?.lowercased() == "approval" {
                            return "Approval needed: \(next.name)"
                        }
                        return "Your turn: \(next.name)"
                    }()
                    let fallbackBody: String = {
                        if next.attention.reason?.lowercased() == "approval" {
                            return "Return to the agent to approve"
                        }
                        return "Return to the agent to continue"
                    }()
                    notify(
                        subject: next,
                        kind: kind,
                        title: next.attention.title ?? fallbackTitle,
                        body: next.attention.summary ?? next.current?.summary ?? fallbackBody
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
                body: next.current?.summary ?? next.outcome?.rawValue ?? ""
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
                body: next.attention.summary ?? next.current?.summary ?? ""
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
                    body: next.current?.summary ?? ""
                )
            }
        }

        // Clear sticky attention banners once the job no longer needs the user.
        if let previous,
           previous.attention.level >= .suggested,
           next.attention.level < .suggested {
            removeDelivered(
                subjectId: next.id,
                kinds: ["attention.urgent", "attention.required", "attention.suggested"]
            )
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
        // Empty body is legal but some macOS versions hide the banner without it.
        content.body = body.isEmpty ? title : body
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
            } else {
                self.onRevealPanel?()
            }
            completionHandler()
        }
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
