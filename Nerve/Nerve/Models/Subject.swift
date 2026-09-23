import Foundation

/// A unit of work on a machine (session, build, test, deploy, …).
/// Producer is who reported it; `alias` is which machine.
struct Job: Identifiable, Codable, Sendable, Hashable {
    var id: String
    /// `session`, `build`, `test`, `deploy`, `custom.*`, …
    var kind: String
    var name: String
    /// Machine alias (SSH Host / Settings alias).
    var alias: String

    var lifecycle: Lifecycle
    var current: Current?
    var attention: Attention
    var health: Health
    var outcome: Outcome?
    var progress: Progress
    var producer: ProducerInfo
    var context: ContextInfo?
    var location: LocationInfo?
    var capabilities: [String]
    var actions: [JobAction]

    var createdAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var updatedAt: Date
    var version: UInt64

    /// Forward-compatible open fields from producers.
    var extensions: [String: JSONValue]

    // MARK: Derived (not stored / not ingested)

    /// Single display status for every view (ribbon, panel, header counts).
    /// Derived only from structured facets — never free-text.
    var status: Status {
        if outcome == .failure { return .problem }
        if health == .unresponsive { return .problem }

        if lifecycle == .ended {
            return outcome == .success || outcome == .partial ? .success : .inactive
        }
        let kind = current?.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let reason = attention.reason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let busy = lifecycle == .active && ["subagent", "tool", "thinking", "info"].contains(kind ?? "")
        if !busy, attention.level >= .informational {
            if Self.waitReasons.contains(reason ?? "") { return .waiting }
            if isAskReason || attention.level >= .suggested { return .attention }
        }

        if lifecycle == .suspended || lifecycle == .unknown { return .inactive }
        if lifecycle == .pending || lifecycle == .created { return .waiting }
        if health == .degraded { return .problem }

        // Open session, partial outcome: a monitor holding the stream.
        if lifecycle == .active, outcome == .partial {
            return .monitor
        }

        switch current?.type.lowercased() {
        case "subagent", "tool", "thinking", "info":
            // Shell / subagent still running → Running (never Monitor).
            if lifecycle == .active { return .running }
        case "monitor":
            // Watching a background stream — not executing, not done.
            return .monitor
        case "completed":
            return .success
        case "waiting":
            return .waiting
        // starting = Ready (session open, no turn yet). idle = your_turn facet
        // without elevated attention (rare). Never paint Running for these.
        case "idle", "starting", "booting":
            return .inactive
        default:
            break
        }

        if lifecycle == .active { return .running }
        return .inactive
    }

    static let waitReasons: Set<String> = ["resource", "dependency", "queue", "system", "lock", "throttle", "rate", "capacity", "failure"]

    /// Visible words alongside color; never infer a status from the summary.
    var statusLabel: String {
        if status == .attention {
            switch attention.reason?.lowercased() {
            case "approval", "permission", "auth": return "Approval needed"
            case "input", "elicitation": return "Input needed"
            case "review": return "Review needed"
            case "decision": return "Decision needed"
            default: return "Needs attention"
            }
        }
        if status == .success, lifecycle == .active { return "Turn complete" }
        return status.title
    }

    // MARK: Role / visibility (panel / ribbon)

    /// Explicit producer role from `extensions.role` (group | member | job | subagent | …).
    var extensionRole: String? {
        if case .string(let role) = extensions["role"] {
            let s = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return s.isEmpty ? nil : s
        }
        return nil
    }

    /// What the human last asked this agent (`extensions.lastPrompt`).
    ///
    /// Reported once, by the producer's `UserPromptSubmit` hook run, and kept
    /// by the hub across the snapshots that follow (`STICKY_EXTENSIONS` in
    /// `crates/nerve-hub/src/state/store.rs`). It is the one thing a status row
    /// cannot say: `current` is what the agent is doing *now*.
    var lastPrompt: String? {
        guard case .string(let prompt) = extensions["lastPrompt"] else { return nil }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isGroupJob: Bool { extensionRole == "group" }
    var isMemberJob: Bool { extensionRole == "member" }

    /// Group id for member rows (`extensions.groupId` or legacy `parentJobId`).
    var groupId: String? {
        if case .string(let g) = extensions["groupId"], !g.isEmpty { return g }
        if case .string(let g) = extensions["parentJobId"], !g.isEmpty { return g }
        return nil
    }

    /// Legacy agent subagent / noise rows that must not accumulate in the store.
    ///
    /// Explicit ``role=group|member|job`` (e.g. molq rollup) is never treated as noise,
    /// even when the id has multiple ``:`` segments or ``paintRibbon=false``.
    var isLegacyChildNoise: Bool {
        if let role = extensionRole {
            if role == "subagent" { return true }
            if role == "group" || role == "member" || role == "job" { return false }
        }
        // Untyped legacy agent children
        if extensions["parentJobId"] != nil { return true }
        if case .bool(false) = extensions["paintRibbon"] { return true }
        // `{producer}:{session}` has one `:`; legacy child ids have two+.
        if id.filter({ $0 == ":" }).count >= 2 { return true }
        return false
    }

    /// Whether this row should be kept in the in-memory job map.
    var isConversationJob: Bool { !isLegacyChildNoise }

    /// Whether this job paints a menu-bar ribbon segment.
    ///
    /// Members and rows with ``paintRibbon=false`` stay off the ribbon;
    /// Settings may further restrict roots.
    var paintsRibbon: Bool {
        if isLegacyChildNoise { return false }
        if isMemberJob { return false }
        if case .bool(false) = extensions["paintRibbon"] { return false }
        return true
    }

    /// Ask reasons — human should return to the agent UI (interruptible channel).
    static let askReasons: Set<String> = [
        "input", "approval", "auth", "permission", "decision", "elicitation", "review",
    ]

    /// True when `attention.reason` is an Ask reason (case-insensitive).
    var isAskReason: Bool {
        guard let reason = attention.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else { return false }
        return Self.askReasons.contains(reason.lowercased())
    }

    /// Ask + elevated enough to interrupt (`level ≥ suggested`).
    var isAskElevated: Bool {
        isAskReason && attention.level >= .suggested
    }

    /// Whether an Ask interrupt should fire for this transition (upgrade or first sight).
    static func shouldNotifyAsk(previous: Job?, next: Job) -> Bool {
        guard next.isAskElevated else { return false }
        guard let previous else { return true }
        if !previous.isAskElevated { return true }
        return next.attention.level > previous.attention.level
    }

    /// Gentle banner copy. Prefers producer title/summary; never panics.
    func askNotificationCopy(forceUrgentTone: Bool = false) -> (title: String, body: String) {
        let reason = attention.reason?.lowercased() ?? "input"
        let fallbackTitle: String = {
            switch reason {
            case "approval", "permission", "auth":
                return "Approval needed: \(name)"
            case "review":
                return "A review is waiting: \(name)"
            default:
                return "Your turn: \(name)"
            }
        }()
        let fallbackBody: String = {
            if forceUrgentTone || attention.level == .urgent {
                return "Please return when you can — continue in the agent"
            }
            switch reason {
            case "approval", "permission", "auth":
                return "Return to the agent to approve"
            case "review":
                return "Return to the agent when you are ready"
            default:
                return "Ready when you are — return to the agent to continue"
            }
        }()
        let title = attention.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = attention.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = self.current?.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            title: (title?.isEmpty == false) ? title! : fallbackTitle,
            body: (summary?.isEmpty == false)
                ? summary!
                : ((activity?.isEmpty == false) ? activity! : fallbackBody)
        )
    }

    static func make(
        id: String,
        kind: String = "session",
        name: String,
        alias: String,
        producer: ProducerInfo,
        lifecycle: Lifecycle = .active,
        now: Date = .now
    ) -> Job {
        Job(
            id: id,
            kind: kind,
            name: name,
            alias: alias,
            lifecycle: lifecycle,
            current: nil,
            attention: .none,
            health: .ok,
            outcome: nil,
            progress: .none,
            producer: producer,
            context: nil,
            location: nil,
            capabilities: [],
            actions: [],
            createdAt: now,
            startedAt: now,
            endedAt: nil,
            updatedAt: now,
            version: 1,
            extensions: [:]
        )
    }
}

// MARK: - JSONValue (open extensions)

enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
