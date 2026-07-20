import Foundation

// MARK: - Lifecycle

/// Lifecycle stage only. Activity, attention, failure, etc. live in other facets.
enum Lifecycle: String, Codable, Sendable, Hashable, CaseIterable {
    case created = "created"
    case pending = "pending"
    case active = "active"
    case suspended = "suspended"
    case ended = "ended"
    case unknown = "unknown"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Lifecycle(rawValue: raw.lowercased()) ?? .unknown
    }
}

// MARK: - Attention

enum AttentionLevel: String, Codable, Sendable, Hashable, CaseIterable, Comparable {
    case none = "none"
    case informational = "informational"
    case suggested = "suggested"
    case required = "required"
    case urgent = "urgent"

    private var rank: Int {
        switch self {
        case .none: return 0
        case .informational: return 1
        case .suggested: return 2
        case .required: return 3
        case .urgent: return 4
        }
    }

    static func < (lhs: AttentionLevel, rhs: AttentionLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AttentionLevel(rawValue: raw.lowercased()) ?? .none
    }
}

struct Attention: Codable, Sendable, Hashable {
    var level: AttentionLevel
    var reason: String?
    var title: String?
    var summary: String?
    var deferrable: Bool?
    var deadline: Date?

    static let none = Attention(level: .none)

    init(
        level: AttentionLevel = .none,
        reason: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        deferrable: Bool? = nil,
        deadline: Date? = nil
    ) {
        self.level = level
        self.reason = reason
        self.title = title
        self.summary = summary
        self.deferrable = deferrable
        self.deadline = deadline
    }
}

// MARK: - Health / Outcome

enum Health: String, Codable, Sendable, Hashable, CaseIterable {
    case ok = "ok"
    case degraded = "degraded"
    case unresponsive = "unresponsive"
    case unknown = "unknown"

    var severity: Int {
        switch self {
        case .ok: return 0
        case .unknown: return 1
        case .degraded: return 2
        case .unresponsive: return 3
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Health(rawValue: raw.lowercased()) ?? .unknown
    }
}

enum Outcome: String, Codable, Sendable, Hashable, CaseIterable {
    case success = "success"
    case failure = "failure"
    case cancelled = "cancelled"
    case partial = "partial"
    case unknown = "unknown"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Outcome(rawValue: raw.lowercased()) ?? .unknown
    }
}

// MARK: - Current

/// What the Subject is doing now. Not an independent run object.
struct Current: Codable, Sendable, Hashable {
    /// Open type string, e.g. planning, testing, custom.foo
    var type: String
    var name: String?
    var summary: String?
    var detail: String?
    var startedAt: Date?

    init(
        type: String,
        name: String? = nil,
        summary: String? = nil,
        detail: String? = nil,
        startedAt: Date? = nil
    ) {
        self.type = type
        self.name = name
        self.summary = summary
        self.detail = detail
        self.startedAt = startedAt
    }
}

// MARK: - Progress

enum ProgressKind: String, Codable, Sendable, Hashable {
    case none
    case indeterminate
    case determinate
    case metrics
}

struct ProgressMetric: Codable, Sendable, Hashable {
    var label: String
    var current: Double?
    var total: Double?
    var unit: String?
}

struct Progress: Codable, Sendable, Hashable {
    var kind: ProgressKind
    /// Only when source provides a trustworthy ratio in 0...1. Never invent.
    var ratio: Double?
    var label: String?
    var metrics: [ProgressMetric]?

    static let none = Progress(kind: .none)

    init(
        kind: ProgressKind = .none,
        ratio: Double? = nil,
        label: String? = nil,
        metrics: [ProgressMetric]? = nil
    ) {
        self.kind = kind
        self.ratio = ratio
        self.label = label
        self.metrics = metrics
    }
}

// MARK: - Producer / Context / Location

/// Who reported the job (claude-code, codex, xcode, …). Not a machine.
struct ProducerInfo: Codable, Sendable, Hashable {
    var id: String
    var name: String?
    var kind: String?

    init(id: String, name: String? = nil, kind: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

struct ContextInfo: Codable, Sendable, Hashable {
    var project: String?
    var workspace: String?
    var labels: [String]?
}

struct LocationInfo: Codable, Sendable, Hashable {
    var openURL: String?
    var focusHint: String?
    var logPath: String?
}

// MARK: - Action

enum ActionState: String, Codable, Sendable, Hashable {
    case available
    case pending
    case succeeded
    case failed
    case expired
    case unsupported
}

struct JobAction: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var kind: String
    var state: ActionState
    var destructive: Bool
    var confirmationRequired: Bool

    init(
        id: String,
        title: String,
        kind: String,
        state: ActionState = .available,
        destructive: Bool = false,
        confirmationRequired: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.state = state
        self.destructive = destructive
        self.confirmationRequired = confirmationRequired
    }
}

// MARK: - Visual status bucket for ribbon / panel

/// Six display statuses for the continuous ribbon and status-grouped list.
/// Not a product facet — derived from attention / health / outcome / lifecycle.
/// `allCases` order = ribbon / panel-by-status section order (priority first).
enum RibbonStatus: String, Sendable, Hashable, CaseIterable, Comparable {
    /// Red — failed or cannot continue.
    case problem
    /// Orange — needs user input, authorization, or decision.
    case attention
    /// Purple — waiting on system, resources, or dependencies.
    case waiting
    /// Blue — actively executing.
    case running
    /// Green — recently completed successfully.
    case success
    /// Gray — paused, idle, or unknown.
    case inactive

    private var order: Int {
        switch self {
        case .problem: return 0
        case .attention: return 1
        case .waiting: return 2
        case .running: return 3
        case .success: return 4
        case .inactive: return 5
        }
    }

    static func < (lhs: RibbonStatus, rhs: RibbonStatus) -> Bool {
        lhs.order < rhs.order
    }

    /// High-priority statuses get a guaranteed minimum ribbon width.
    var isHighPriority: Bool {
        switch self {
        case .problem, .attention:
            return true
        default:
            return false
        }
    }

    /// Section title when the status panel is grouped by ribbon status.
    var panelTitle: String {
        switch self {
        case .running: return "Running"
        case .waiting: return "Waiting"
        case .attention: return "Attention"
        case .problem: return "Problem"
        case .success: return "Success"
        case .inactive: return "Inactive"
        }
    }
}

// MARK: - Status panel grouping

/// How the status panel buckets jobs into sections.
/// This is **grouping** (section headers), not sort order — within a section
/// jobs still follow the default priority sort (attention → health → …).
enum PanelGroupMode: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    /// Bucket by reported machine alias (default).
    case machine
    /// Attention / Active / Recent.
    case priority
    /// Bucket by ribbon status.
    case status

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "source": self = .machine
        default: self = PanelGroupMode(rawValue: raw) ?? .machine
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .machine: return "Machine"
        case .priority: return "Priority"
        case .status: return "Status"
        }
    }

    var shortTitle: String {
        switch self {
        case .machine: return "Machine"
        case .priority: return "Prio"
        case .status: return "Status"
        }
    }
}

/// One collapsible section in the status panel list.
struct StatusSection: Identifiable, Hashable {
    var id: String
    var title: String
    var jobs: [Job]

    /// Compatibility for call sites still using `.subjects`.
    var subjects: [Job] {
        get { jobs }
        set { jobs = newValue }
    }

    init(id: String, title: String, jobs: [Job]) {
        self.id = id
        self.title = title
        self.jobs = jobs
    }

    init(id: String, title: String, subjects: [Job]) {
        self.id = id
        self.title = title
        self.jobs = subjects
    }
}

// failure = clear red; success = clear green (distinct from urgent coral / active cyan)
