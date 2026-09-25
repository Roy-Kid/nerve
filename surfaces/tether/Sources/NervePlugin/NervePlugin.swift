import Foundation
import NerveHubClient
import SwiftUI
import TetherPluginKit
#if os(macOS)
  import UserNotifications
#endif

/// Nerve jobs inside Tether. One SSE against the shared `nerve-hub`; never a
/// second hub if Nerve.app is already serving 17890.
@MainActor
public final class NervePlugin: TetherPlugin {
  public let metadata = PluginMetadata(
    id: "app.nerve.tether",
    name: "Nerve",
    symbol: "waveform.path.ecg",
    summary: "Live job status from the local hub."
  )

  let session = HubSession()
  private let banners = AskBanners()

  public var isStatusBarOnly: Bool { true }

  /// Tether renders this compact lamp beside its host selector. Read the
  /// observed session directly so job updates repaint the status bar.
  public var statusBarItem: PluginStatusBarItem? {
    let jobs = session.jobs.filter { $0.lifecycle != "ended" }
    var runs: [(status: NerveStatus, count: Int)] = []
    for job in jobs {
      if let last = runs.last, last.status == job.status {
        runs[runs.count - 1].count += 1
      } else {
        runs.append((job.status, 1))
      }
    }
    let total = max(1, jobs.count)
    let segments = runs.isEmpty
      ? [PluginStatusSegment(id: "inactive", color: NervePalette.inactive, weight: 1)]
      : runs.enumerated().map { index, run in
        PluginStatusSegment(
          id: "\(index)-\(run.status.rawValue)",
          color: NervePalette.hex(for: run.status),
          weight: Double(run.count) / Double(total))
      }
    return PluginStatusBarItem(
      id: metadata.id,
      label: "Nerve status · click to view jobs",
      segments: segments)
  }

  public func statusBarWorkspace() -> (any PluginWorkspace)? {
    NerveWorkspace(session: session, hostLabel: "Local")
  }

  public init() {}

  public func activate() {
    session.onAsk = { [weak self] job in
      self?.banners.deliver(job)
    }
    banners.requestAuthorization()
    session.start()
  }

  public func deactivate() {
    session.onAsk = nil
    session.stop()
  }

  /// Jobs live on the local hub. A localhost tab has no SSH session.
  public var needsRemoteConnection: Bool { false }

  public func launch(in context: PluginContext) {
    // Nerve is represented by the live status lamp, not a separate workspace.
    session.start()
  }

  public func settings() -> AnyView {
    AnyView(NerveSettings(session: session))
  }
}

@MainActor
private final class AskBanners {
  #if os(macOS)
    private let center = UNUserNotificationCenter.current()
  #endif
  private var lastFire: [String: Date] = [:]
  private let window: TimeInterval = 120

  func requestAuthorization() {
    #if os(macOS)
      center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    #endif
  }

  func deliver(_ job: NerveJob) {
    let now = Date()
    let key = "\(job.id)|\(job.attentionLevel)"
    if let last = lastFire[key], now.timeIntervalSince(last) < window { return }
    lastFire[key] = now
    let copy = AskCopy.of(job)
    #if os(macOS)
      let content = UNMutableNotificationContent()
      content.title = copy.title
      content.body = copy.body
      content.sound = job.attentionLevel == "urgent" ? .default : nil
      let request = UNNotificationRequest(
        identifier: "\(key)|\(Int(now.timeIntervalSince1970))",
        content: content,
        trigger: nil
      )
      center.add(request)
    #endif
  }
}
