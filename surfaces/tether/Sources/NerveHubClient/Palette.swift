import Foundation

/// The seven display statuses every surface paints, in priority order.
///
/// Mirrors `Nerve/Nerve/Models/CoreTypes.swift` `Status` and
/// `crates/nerve-surface-core/src/status.rs` `StatusClass` so words and hues
/// cannot drift from the macOS menu-bar app.
public enum NerveStatus: String, Sendable, Hashable, CaseIterable, Comparable {
  /// Red — failed or cannot continue.
  case problem
  /// Orange — needs human input, approval, or review.
  case attention
  /// Gray — automatic wait on the system; no human action needed.
  case waiting
  /// Blue — actively executing (main thread, or a background shell/subagent).
  case running
  /// Purple — watching a background stream; phase done, not executing.
  case monitor
  /// Green — completed turn or ended success.
  case success
  /// Gray — ready (no turn yet), paused, or unknown. Not "dead".
  case inactive

  private var order: Int {
    switch self {
    case .problem: return 0
    case .attention: return 1
    case .waiting: return 2
    case .running: return 3
    case .monitor: return 4
    case .success: return 5
    case .inactive: return 6
    }
  }

  public static func < (lhs: NerveStatus, rhs: NerveStatus) -> Bool {
    lhs.order < rhs.order
  }

  /// Visible words alongside colour. Same ladder as `Status.title` on macOS.
  public var title: String {
    switch self {
    case .running: return "Running"
    case .waiting: return "Waiting"
    case .attention: return "Needs you"
    case .problem: return "Problem"
    case .monitor: return "Monitor"
    case .success: return "Completed"
    case .inactive: return "Ready / idle"
    }
  }

  /// Automatic waits (not human Asks) — see `Subject.waitReasons` on macOS.
  static let waitReasons: Set<String> = [
    "resource", "dependency", "queue", "system", "lock", "throttle", "rate", "capacity", "failure",
  ]

  /// Reasons that mean the human, not the system.
  static let askReasons: Set<String> = [
    "input", "approval", "auth", "permission", "decision", "elicitation", "review",
  ]
}

/// Canonical status hexes, transcribed once from
/// `crates/nerve-surface-core/src/palette.rs:48-59`.
///
/// Kept as raw `UInt32` so `NerveHubClientTests` can pin them without pulling
/// SwiftUI into the decode layer. Not a cross-language token package — the
/// macOS app and the Rust surfaces each hold their own copy of the same six.
public enum NervePalette: Sendable {
  public static let problem: UInt32 = 0xFF3B30
  public static let attention: UInt32 = 0xFF9F0A
  public static let running: UInt32 = 0x0A84FF
  public static let monitor: UInt32 = 0xBF5AF2
  public static let success: UInt32 = 0x30D158
  public static let inactive: UInt32 = 0x8E8E93
  /// Waiting shares the chrome gray with Inactive (`palette.rs:66-67`).
  public static let waiting: UInt32 = inactive

  /// The colour a status paints.
  public static func hex(for status: NerveStatus) -> UInt32 {
    switch status {
    case .problem: return problem
    case .attention: return attention
    case .waiting: return waiting
    case .running: return running
    case .monitor: return monitor
    case .success: return success
    case .inactive: return inactive
    }
  }
}
