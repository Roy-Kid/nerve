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

        // Elevated attention → attention or waiting, never running.
        if attention.level >= .suggested {
            if let reason = attention.reason?.lowercased() {
                switch reason {
                case "resource", "dependency", "queue", "system", "lock",
                     "throttle", "rate", "capacity", "failure":
                    return .waiting
                default:
                    return .attention
                }
            }
            return .attention
        }

        if attention.level >= .informational, let reason = attention.reason?.lowercased() {
            switch reason {
            case "input", "approval", "auth", "permission", "decision", "elicitation":
                return .attention
            case "resource", "dependency", "queue", "system", "lock",
                 "throttle", "rate", "capacity", "failure":
                return .waiting
            default:
                break
            }
        }

        if lifecycle == .ended {
            if outcome == .success || outcome == .partial { return .success }
            return .inactive
        }
        if lifecycle == .suspended || lifecycle == .unknown { return .inactive }
        if lifecycle == .pending || lifecycle == .created { return .waiting }
        if health == .degraded { return .waiting }

        switch current?.type.lowercased() {
        case "subagent", "tool", "thinking", "starting", "info":
            if lifecycle == .active { return .running }
        case "waiting":
            return .waiting
        case "idle":
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
