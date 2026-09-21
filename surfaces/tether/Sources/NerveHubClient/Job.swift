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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    alias = try c.decodeIfPresent(String.self, forKey: .alias) ?? ""
    lifecycle = try c.decodeIfPresent(String.self, forKey: .lifecycle) ?? "active"
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
    } else {
      openURL = nil
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

  public var isAsk: Bool {
    let reason = (attentionReason ?? "").lowercased()
    let ask = ["input", "approval", "auth", "permission", "decision", "elicitation", "review"]
    let elevated = ["suggested", "required", "urgent"]
    return ask.contains(reason) && elevated.contains(attentionLevel.lowercased())
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, alias, lifecycle, attention, current, location
  }
  private enum AttentionKeys: String, CodingKey { case level, reason, title }
  private enum CurrentKeys: String, CodingKey { case type, name, summary }
  private enum LocationKeys: String, CodingKey { case openURL }
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
