import Foundation

/// The subset of a hub job this surface paints. Only `id` is required.
public struct NerveJob: Decodable, Identifiable, Sendable, Equatable {
  public var id: String
  public var name: String
  public var alias: String
  public var lifecycle: String
  public var attentionLevel: String
  public var attentionReason: String?
  public var attentionTitle: String?
  public var currentType: String
  public var currentName: String?
  public var summary: String?
  public var openURL: String?
  public var focusHint: String?
  public var health: String?
  public var outcome: String?
  public var lastPrompt: String?
  public var model: String?
  public var agentType: String?

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    alias = try c.decodeIfPresent(String.self, forKey: .alias) ?? ""
    lifecycle = try c.decodeIfPresent(String.self, forKey: .lifecycle) ?? "active"
    health = try c.decodeIfPresent(String.self, forKey: .health)
    outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
    if let attention = try? c.nestedContainer(keyedBy: AttentionKeys.self, forKey: .attention) {
      attentionLevel = (try? attention.decode(String.self, forKey: .level)) ?? "none"
      attentionReason = try? attention.decode(String.self, forKey: .reason)
      attentionTitle = try? attention.decode(String.self, forKey: .title)
    } else {
      attentionLevel = "none"
      attentionReason = nil
      attentionTitle = nil
    }
    if let current = try? c.nestedContainer(keyedBy: CurrentKeys.self, forKey: .current) {
      currentType = (try? current.decode(String.self, forKey: .type)) ?? ""
      currentName = try? current.decode(String.self, forKey: .name)
      summary = try? current.decode(String.self, forKey: .summary)
    } else {
      currentType = ""
      currentName = nil
      summary = nil
    }
    if let location = try? c.nestedContainer(keyedBy: LocationKeys.self, forKey: .location) {
      openURL = try? location.decode(String.self, forKey: .openURL)
      focusHint = try? location.decode(String.self, forKey: .focusHint)
    } else {
      openURL = nil
      focusHint = nil
    }
    if let ext = try? c.nestedContainer(keyedBy: ExtensionKeys.self, forKey: .extensions) {
      lastPrompt = try? ext.decode(String.self, forKey: .lastPrompt)
      model = try? ext.decode(String.self, forKey: .model)
      agentType = try? ext.decode(String.self, forKey: .agentType)
    } else {
      lastPrompt = nil
      model = nil
      agentType = nil
    }
  }

  /// One line for the row: Ask copy, else what the agent is doing now.
  public var progress: String {
    if isAsk {
      let title = (attentionTitle ?? "").trimmingCharacters(in: .whitespaces)
      if !title.isEmpty { return title }
      return "Needs you"
    }
    let summary = (summary ?? "").trimmingCharacters(in: .whitespaces)
    if !summary.isEmpty { return summary }
    let name = (currentName ?? "").trimmingCharacters(in: .whitespaces)
    if !name.isEmpty { return name }
    return currentType
  }

  /// `none` < `informational` < `suggested` < `required` < `urgent`.
  private var attentionRank: Int {
    switch attentionLevel.lowercased() {
    case "informational": return 1
    case "suggested": return 2
    case "required": return 3
    case "urgent": return 4
    default: return 0
    }
  }

  private var isBusy: Bool {
    lifecycle == "active"
      && ["subagent", "tool", "thinking", "info"]
        .contains(currentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }

  /// Human Ask tally (not the broader Attention paint). Same rule as
  /// `Subject.isAskReason` + `>= suggested`, with the busy-kind skip.
  public var isAsk: Bool {
    if isBusy { return false }
    let reason = (attentionReason ?? "").lowercased()
    return NerveStatus.askReasons.contains(reason) && attentionRank >= 2
  }

  /// Single display status, derived only from structured facets — never
  /// free-text. Mirrors `Subject.status` on macOS and `StatusClass::of` in
  /// `crates/nerve-surface-core/src/status.rs`.
  public var status: NerveStatus {
    if outcome == "failure" { return .problem }
    if health == "unresponsive" { return .problem }
    if lifecycle == "ended" {
      return (outcome == "success" || outcome == "partial") ? .success : .inactive
    }
    let reason = (attentionReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !isBusy && attentionRank >= 1 {
      if NerveStatus.waitReasons.contains(reason) { return .waiting }
      if NerveStatus.askReasons.contains(reason) || attentionRank >= 2 { return .attention }
    }
    if lifecycle == "suspended" || lifecycle == "unknown" { return .inactive }
    if lifecycle == "pending" || lifecycle == "created" { return .waiting }
    if health == "degraded" { return .problem }
    // Open session, partial outcome: a monitor holding the stream.
    if lifecycle == "active" && outcome == "partial" { return .monitor }

    let kind = currentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch kind {
    case "subagent", "tool", "thinking", "info":
      if lifecycle == "active" { return .running }
    case "monitor":
      return .monitor
    case "completed":
      return .success
    case "waiting":
      return .waiting
    case "idle", "starting", "booting":
      return .inactive
    default:
      break
    }
    return lifecycle == "active" ? .running : .inactive
  }

  /// Visible words alongside colour. Same ladder as `Subject.statusLabel`.
  public var statusLabel: String {
    if status == .attention {
      switch (attentionReason ?? "").lowercased() {
      case "approval", "permission", "auth": return "Approval needed"
      case "input", "elicitation": return "Input needed"
      case "review": return "Review needed"
      case "decision": return "Decision needed"
      default: return "Needs attention"
      }
    }
    if status == .success && lifecycle == "active" { return "Turn complete" }
    return status.title
  }

  /// `alias · model` (or `alias · agentType`) for the row's trailing caption.
  public var metadataCaption: String? {
    let parts = [alias, model ?? agentType].filter { !($0 ?? "").isEmpty }
    let joined = parts.compactMap { $0 }.joined(separator: " · ")
    return joined.isEmpty ? nil : joined
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, alias, lifecycle, attention, current, location, extensions
    case health, outcome
  }
  private enum AttentionKeys: String, CodingKey { case level, reason, title }
  private enum CurrentKeys: String, CodingKey { case type, name, summary }
  private enum LocationKeys: String, CodingKey { case openURL, focusHint }
  private enum ExtensionKeys: String, CodingKey { case lastPrompt, model, agentType }
}

public struct NerveFrame: Decodable, Sendable {
  public var jobs: [NerveJob]
  public var notify: NotifyLease

  public init(jobs: [NerveJob] = [], notify: NotifyLease = .legacy) {
    self.jobs = jobs
    self.notify = notify
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    jobs = (try c.decodeIfPresent([NerveJob].self, forKey: .jobs) ?? []).filter { !$0.id.isEmpty }
    notify = try c.decodeIfPresent(NotifyLease.self, forKey: .notify) ?? .legacy
  }

  private enum CodingKeys: String, CodingKey { case jobs, notify }
}
