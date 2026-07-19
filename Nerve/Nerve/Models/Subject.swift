import Foundation

/// Independently tracked run object. Type is open-ended (`agent.session`, `custom.*`, …).
struct Subject: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var type: String
    var name: String
    var parentId: String?

    var lifecycle: Lifecycle
    var current: Current?
    var attention: Attention
    var health: Health
    var outcome: Outcome?
    var progress: Progress
    var source: SourceInfo
    var context: ContextInfo?
    var location: LocationInfo?
    var capabilities: [String]
    var actions: [SubjectAction]

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

    /// Maps facets → one of six display statuses (Running / Waiting / Attention / Problem / Success / Inactive).
    var ribbonStatus: RibbonStatus {
        // Problem — failed or cannot continue
        if outcome == .failure { return .problem }
        if health == .unresponsive { return .problem }

        // Attention — needs the user (input / auth / decision)
        if attention.level >= .required { return .attention }
        if Self.looksLikeUserWait(attention) { return .attention }

        // Ended outcomes
        if lifecycle == .ended {
            if outcome == .success || outcome == .partial { return .success }
            return .inactive
        }

        // Waiting — system, resources, dependencies (not the user)
        if Self.looksLikeSystemWait(attention) { return .waiting }
        if attention.level >= .suggested { return .waiting }
        if health == .degraded { return .waiting }
        if lifecycle == .pending || lifecycle == .created { return .waiting }

        // Inactive — paused / unknown
        if lifecycle == .suspended || lifecycle == .unknown { return .inactive }

        // Running — actively executing
        if lifecycle == .active { return .running }

        return .inactive
    }

    private static func looksLikeUserWait(_ attention: Attention) -> Bool {
        guard attention.level >= .informational else { return false }
        let blob = [attention.reason, attention.title, attention.summary]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let keys = ["input", "approval", "approve", "decision", "auth", "permission", "confirm", "user"]
        return keys.contains { blob.contains($0) }
    }

    private static func looksLikeSystemWait(_ attention: Attention) -> Bool {
        guard attention.level >= .informational else { return false }
        let blob = [attention.reason, attention.title, attention.summary]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let keys = ["resource", "depend", "queue", "system", "lock", "throttle", "rate", "capacity"]
        return keys.contains { blob.contains($0) }
    }

    static func make(
        id: String,
        type: String = "custom.unknown",
        name: String,
        source: SourceInfo,
        lifecycle: Lifecycle = .active,
        now: Date = .now
    ) -> Subject {
        Subject(
            id: id,
            type: type,
            name: name,
            parentId: nil,
            lifecycle: lifecycle,
            current: nil,
            attention: .none,
            health: .ok,
            outcome: nil,
            progress: .none,
            source: source,
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
