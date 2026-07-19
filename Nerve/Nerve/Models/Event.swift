import Foundation

/// Observation of a Subject state change, or a full snapshot correction.
enum EventKind: String, Codable, Sendable, Hashable {
    case subjectCreated = "subject.created"
    case lifecycleChanged = "lifecycle.changed"
    case currentChanged = "current.changed"
    case attentionChanged = "attention.changed"
    case healthChanged = "health.changed"
    case progressUpdated = "progress.updated"
    case outcomeReported = "outcome.reported"
    case heartbeat = "heartbeat"
    case subjectEnded = "subject.ended"
    case actionCompleted = "action.completed"
    case sourceDisconnected = "source.disconnected"
    case snapshot = "snapshot"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EventKind(rawValue: raw) ?? .unknown
    }
}

struct NerveEvent: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var subjectId: String
    var kind: EventKind
    var timestamp: Date
    var sourceId: String
    /// Monotonic version for the subject at the source. Higher wins; equal id is idempotent.
    var version: UInt64?
    var sequence: UInt64?

    // Partial patch fields (optional depending on kind)
    var name: String?
    var type: String?
    var parentId: String?
    var lifecycle: Lifecycle?
    var current: Current?
    var attention: Attention?
    var health: Health?
    var outcome: Outcome?
    var progress: Progress?
    var context: ContextInfo?
    var location: LocationInfo?
    var capabilities: [String]?
    var actions: [SubjectAction]?
    var extensions: [String: JSONValue]?

    /// Full subject body for snapshot / create.
    var subject: Subject?
}

/// Wire envelope for HTTP ingest.
struct IngestEnvelope: Codable, Sendable {
    var events: [NerveEvent]?
    var subjects: [Subject]?
    var source: SourceInfo?
}
