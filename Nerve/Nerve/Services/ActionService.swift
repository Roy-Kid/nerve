import Foundation
import AppKit

enum ActionResult: Sendable {
    case succeeded(String)
    case failed(String)
    case pending(String)   // queued for owning source
    case unsupported
    case denied(String)
}

/// Executes only declared Actions. Never controls another source's Subject.
enum ActionService {
    /// Kinds Nerve can fulfill locally without the source process.
    static let localKinds: Set<String> = [
        "open", "focus", "open_url", "openurl",
        "copy", "copy_summary", "copysummary",
        "open_logs", "openlogs", "hide", "mute",
    ]

    /// Kinds that must be delivered to the owning source.
    static let remoteKinds: Set<String> = [
        "approve", "reject", "cancel", "pause", "resume", "retry", "submit",
        "submit_input", "submitinput",
    ]

    @MainActor
    static func classify(action: SubjectAction) -> KindClass {
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
    static func performLocal(action: SubjectAction, on subject: Subject) -> ActionResult {
        guard action.state == .available || action.state == .pending else {
            return .denied("Action is \(action.state.rawValue)")
        }

        switch action.kind.lowercased() {
        case "open", "focus", "open_url", "openurl":
            return openLocation(subject)

        case "copy", "copy_summary", "copysummary":
            let text = "\(subject.name) — \(subject.displaySummary)"
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

        default:
            if subject.location?.openURL != nil {
                return openLocation(subject)
            }
            return .unsupported
        }
    }

    @MainActor
    private static func openLocation(_ subject: Subject) -> ActionResult {
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
    static func isDestructive(_ action: SubjectAction) -> Bool {
        if action.destructive { return true }
        switch action.kind.lowercased() {
        case "cancel", "reject":
            return true
        default:
            return action.confirmationRequired
        }
    }
}
