import Foundation

/// User-requested Action awaiting the owning producer (or completed locally).
struct PendingActionRequest: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var jobId: String
    var producerId: String
    var actionId: String
    var actionKind: String
    var title: String
    var requestedAt: Date
    var state: ActionState
    var resultMessage: String?
    var expiresAt: Date?

    var isOpen: Bool {
        state == .pending || state == .available
    }
}

struct ActionResultBody: Codable, Sendable {
    var id: String
    var state: ActionState
    var message: String?
}
