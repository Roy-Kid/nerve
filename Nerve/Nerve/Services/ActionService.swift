import Foundation
import AppKit

enum ActionResult: Sendable {
    case succeeded(String)
    case failed(String)
    case pending(String)   // queued for owning producer
    case unsupported
    case denied(String)
}

/// Executes only declared Actions. Never controls another source's Job.
enum ActionService {
    /// Kinds Nerve can fulfill locally without the source process.
    static let localKinds: Set<String> = [
        "open", "focus", "open_url", "openurl",
        "copy", "copy_summary", "copysummary",
        "open_logs", "openlogs", "hide", "mute",
        "dismiss", "dismiss_job", "dismissjob",
    ]

    /// Kinds that must be delivered to the owning producer.
    static let remoteKinds: Set<String> = [
        "approve", "reject", "cancel", "pause", "resume", "retry", "submit",
        "submit_input", "submitinput",
    ]

    @MainActor
    static func classify(action: JobAction) -> KindClass {
        let k = action.kind.lowercased()
        if localKinds.contains(k) { return .local }
        if remoteKinds.contains(k) { return .remote }
        if action.kind.hasPrefix("custom.") { return .remote }
        return .localIfOpenURLElseRemote
    }

    enum KindClass {
        case local
        case remote
        case localIfOpenURLElseRemote
    }

    @MainActor
    static func performLocal(action: JobAction, on subject: Job) -> ActionResult {
        guard action.state == .available || action.state == .pending else {
            return .denied("Action is \(action.state.rawValue)")
        }

        switch action.kind.lowercased() {
        case "open", "focus", "open_url", "openurl":
            return openLocation(subject)

        case "copy", "copy_summary", "copysummary":
            let detail = subject.current?.summary ?? subject.current?.name ?? subject.attention.title
            let text = detail.map { "\(subject.name) — \($0)" } ?? subject.name
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return .succeeded("Copied summary")

        case "open_logs", "openlogs":
            if let path = subject.location?.logPath {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    return .succeeded("Revealed logs")
                }
                return .failed("Log path not found")
            }
            return .failed("No log path")

        case "hide", "mute":
            return .succeeded("Acknowledged (\(action.kind))")

        case "dismiss", "dismiss_job", "dismissjob":
            // Handled in JobStore.performAction (evicts the row). Not reached for store path.
            return .succeeded("Dismissed")

        default:
            if subject.location?.openURL != nil {
                return openLocation(subject)
            }
            return .unsupported
        }
    }

    @MainActor
    private static func openLocation(_ subject: Job) -> ActionResult {
        if let raw = subject.location?.openURL, let url = URL(string: raw) {
            let ok = NSWorkspace.shared.open(url)
            return ok ? .succeeded("Opened") : .failed("Could not open URL")
        }
        if let hint = subject.location?.focusHint, !hint.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hint, forType: .string)
            return .succeeded("Copied focus hint")
        }
        return .failed("No open target")
    }

    /// Destructive kinds require explicit confirmation in UI.
    static func isDestructive(_ action: JobAction) -> Bool {
        if action.destructive { return true }
        switch action.kind.lowercased() {
        case "cancel", "reject":
            return true
        default:
            return action.confirmationRequired
        }
    }
}
