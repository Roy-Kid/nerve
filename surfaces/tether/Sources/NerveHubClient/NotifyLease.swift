import Foundation

/// Who may raise an OS banner, as the hub published it.
public struct NotifyLease: Decodable, Sendable, Equatable {
  public enum Policy: String, Decodable, Sendable, Equatable {
    case all
    case single
  }

  public var policy: Policy
  public var owner: String?
  public var surfaces: [String]
  public var watchers: Int

  /// An older hub omitted the key. Everyone may fire.
  public static let legacy = NotifyLease(policy: .all, owner: nil, surfaces: [], watchers: 0)

  public init(policy: Policy, owner: String?, surfaces: [String], watchers: Int) {
    self.policy = policy
    self.owner = owner
    self.surfaces = surfaces
    self.watchers = watchers
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let raw = try c.decodeIfPresent(String.self, forKey: .policy)?.lowercased()
    policy = raw.flatMap(Policy.init(rawValue:)) ?? .single
    owner = try c.decodeIfPresent(String.self, forKey: .owner)
    surfaces = try c.decodeIfPresent([String].self, forKey: .surfaces) ?? []
    watchers = try c.decodeIfPresent(Int.self, forKey: .watchers) ?? 0
  }

  public func mayInterrupt(surface: String) -> Bool {
    switch policy {
    case .all: return true
    case .single: return owner == surface
    }
  }

  private enum CodingKeys: String, CodingKey {
    case policy, owner, surfaces, watchers
  }
}
