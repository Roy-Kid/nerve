import Foundation

/// Observation of a Job state change, or a full snapshot correction.
enum EventKind: String, Codable, Sendable, Hashable {
    case jobCreated = "job.created"
    case lifecycleChanged = "lifecycle.changed"
    case currentChanged = "current.changed"
    case attentionChanged = "attention.changed"
    case healthChanged = "health.changed"
    case progressUpdated = "progress.updated"
    case outcomeReported = "outcome.reported"
    case heartbeat = "heartbeat"
    case jobEnded = "job.ended"
    case actionCompleted = "action.completed"
    case producerDisconnected = "producer.disconnected"
    case snapshot = "snapshot"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Accept legacy subject.* kind strings from old fixtures during internal tests only.
        switch raw {
        case "subject.created": self = .jobCreated
        case "subject.ended": self = .jobEnded
        case "source.disconnected": self = .producerDisconnected
        default:
            self = EventKind(rawValue: raw) ?? .unknown
        }
    }
}

struct NerveEvent: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var jobId: String
    var kind: EventKind
    var timestamp: Date
    var producerId: String
    var alias: String?
    /// Monotonic version for the job at the producer. Higher wins; equal id is idempotent.
    var version: UInt64?
    var sequence: UInt64?

    var name: String?
    var jobKind: String?
    var lifecycle: Lifecycle?
    var current: Current?
    var attention: Attention?
    var health: Health?
    var outcome: Outcome?
    var progress: Progress?
    var context: ContextInfo?
    var location: LocationInfo?
    var capabilities: [String]?
    var actions: [JobAction]?
    var extensions: [String: JSONValue]?

    /// Full job body for snapshot / create.
    var job: Job?

    enum CodingKeys: String, CodingKey {
        case id, kind, timestamp, version, sequence
        case name, lifecycle, current, attention, health, outcome, progress
        case context, location, capabilities, actions, extensions, alias
        case jobId, producerId, jobKind, job
        // legacy wire names
        case subjectId, sourceId, type, subject
    }

    init(
        id: String,
        jobId: String,
        kind: EventKind,
        timestamp: Date,
        producerId: String,
        alias: String? = nil,
        version: UInt64? = nil,
        sequence: UInt64? = nil,
        name: String? = nil,
        jobKind: String? = nil,
        lifecycle: Lifecycle? = nil,
        current: Current? = nil,
        attention: Attention? = nil,
        health: Health? = nil,
        outcome: Outcome? = nil,
        progress: Progress? = nil,
        context: ContextInfo? = nil,
        location: LocationInfo? = nil,
        capabilities: [String]? = nil,
        actions: [JobAction]? = nil,
        extensions: [String: JSONValue]? = nil,
        job: Job? = nil
    ) {
        self.id = id
        self.jobId = jobId
        self.kind = kind
        self.timestamp = timestamp
        self.producerId = producerId
        self.alias = alias
        self.version = version
        self.sequence = sequence
        self.name = name
        self.jobKind = jobKind
        self.lifecycle = lifecycle
        self.current = current
        self.attention = attention
        self.health = health
        self.outcome = outcome
        self.progress = progress
        self.context = context
        self.location = location
        self.capabilities = capabilities
        self.actions = actions
        self.extensions = extensions
        self.job = job
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        jobId = try c.decodeIfPresent(String.self, forKey: .jobId)
            ?? c.decodeIfPresent(String.self, forKey: .subjectId)
            ?? ""
        kind = try c.decode(EventKind.self, forKey: .kind)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        producerId = try c.decodeIfPresent(String.self, forKey: .producerId)
            ?? c.decodeIfPresent(String.self, forKey: .sourceId)
            ?? ""
        alias = try c.decodeIfPresent(String.self, forKey: .alias)
        version = try c.decodeIfPresent(UInt64.self, forKey: .version)
        sequence = try c.decodeIfPresent(UInt64.self, forKey: .sequence)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        jobKind = try c.decodeIfPresent(String.self, forKey: .jobKind)
            ?? c.decodeIfPresent(String.self, forKey: .type)
        lifecycle = try c.decodeIfPresent(Lifecycle.self, forKey: .lifecycle)
        current = try c.decodeIfPresent(Current.self, forKey: .current)
        attention = try c.decodeIfPresent(Attention.self, forKey: .attention)
        health = try c.decodeIfPresent(Health.self, forKey: .health)
        outcome = try c.decodeIfPresent(Outcome.self, forKey: .outcome)
        progress = try c.decodeIfPresent(Progress.self, forKey: .progress)
        context = try c.decodeIfPresent(ContextInfo.self, forKey: .context)
        location = try c.decodeIfPresent(LocationInfo.self, forKey: .location)
        capabilities = try c.decodeIfPresent([String].self, forKey: .capabilities)
        actions = try c.decodeIfPresent([JobAction].self, forKey: .actions)
        extensions = try c.decodeIfPresent([String: JSONValue].self, forKey: .extensions)
        job = try c.decodeIfPresent(Job.self, forKey: .job)
            ?? c.decodeIfPresent(Job.self, forKey: .subject)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(jobId, forKey: .jobId)
        try c.encode(kind, forKey: .kind)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(producerId, forKey: .producerId)
        try c.encodeIfPresent(alias, forKey: .alias)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encodeIfPresent(sequence, forKey: .sequence)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(jobKind, forKey: .jobKind)
        try c.encodeIfPresent(lifecycle, forKey: .lifecycle)
        try c.encodeIfPresent(current, forKey: .current)
        try c.encodeIfPresent(attention, forKey: .attention)
        try c.encodeIfPresent(health, forKey: .health)
        try c.encodeIfPresent(outcome, forKey: .outcome)
        try c.encodeIfPresent(progress, forKey: .progress)
        try c.encodeIfPresent(context, forKey: .context)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(capabilities, forKey: .capabilities)
        try c.encodeIfPresent(actions, forKey: .actions)
        try c.encodeIfPresent(extensions, forKey: .extensions)
        try c.encodeIfPresent(job, forKey: .job)
    }
}

/// Wire envelope for HTTP ingest. Jobs only; machine identity is `alias`.
struct IngestEnvelope: Codable, Sendable {
    /// Machine alias (required for snapshot/events that create or update jobs).
    var alias: String?
    /// Optional platform kind reported by the client (`darwin`, `linux`, …).
    var machineKind: String?
    var jobs: [Job]?
    var events: [NerveEvent]?
}
