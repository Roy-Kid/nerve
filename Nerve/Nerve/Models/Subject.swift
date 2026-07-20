import Foundation

/// A unit of work on a machine (session, build, test, deploy, …).
/// Not an "agent" — producer is who reported it; `alias` is which machine.
struct Job: Identifiable, Codable, Sendable, Hashable {
    var id: String
    /// Job shape: `session`, `build`, `test`, `deploy`, `custom.*`, …
    var kind: String
    var name: String
    /// Machine alias (SSH Host / Settings alias). Routing key.
    var alias: String

    var lifecycle: Lifecycle
    var current: Current?
    var attention: Attention
    var health: Health
    var outcome: Outcome?
    var progress: Progress
    /// Who produced this job (claude-code, codex, xcode, …) — not a machine.
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

    /// Unknown extension fields retained for forward compatibility.
    var extensions: [String: JSONValue]

    var isActive: Bool {
        lifecycle != .ended
    }

    var isEnded: Bool {
        lifecycle == .ended
    }

    var displaySummary: String {
        if let title = attention.title, attention.level >= .suggested {
            return title
        }
        if let s = current?.summary, !s.isEmpty { return s }
        if let n = current?.name, !n.isEmpty { return n }
        if let o = outcome { return o.rawValue.capitalized }
        return lifecycle.rawValue.capitalized
    }

    /// Maps **structured** facets → ribbon color.
    /// Never inspects free-text summaries — only lifecycle / health / outcome /
    /// attention.level / attention.reason codes / current.type vocabulary from hooks.
    var ribbonStatus: RibbonStatus {
        if outcome == .failure { return .problem }
        if health == .unresponsive { return .problem }

        // Controlled attention.reason codes (exact), written by the hook.
        if attention.level >= .informational, let reason = attention.reason?.lowercased() {
            switch reason {
            case "input", "approval", "auth", "permission", "decision", "elicitation":
                return .attention
            case "resource", "dependency", "queue", "system", "lock", "throttle", "rate", "capacity":
                return .waiting
            case "failure":
                return .waiting
            default:
                break
            }
        }
        if attention.level >= .required { return .attention }

        if lifecycle == .ended {
            if outcome == .success || outcome == .partial { return .success }
            return .inactive
        }
        if lifecycle == .suspended || lifecycle == .unknown { return .inactive }
        if lifecycle == .pending || lifecycle == .created { return .waiting }
        if health == .degraded { return .waiting }

        // Controlled current.type vocabulary from hooks.
        switch current?.type.lowercased() {
        case "subagent", "tool", "thinking", "starting", "info":
            if lifecycle == .active { return .running }
        case "waiting":
            return attention.level >= .informational ? .attention : .waiting
        case "idle":
            // Stop / idle_prompt set idle + reason=input (already handled). Bare idle → inactive.
            return .inactive
        default:
            break
        }

        if lifecycle == .active { return .running }
        return .inactive
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
