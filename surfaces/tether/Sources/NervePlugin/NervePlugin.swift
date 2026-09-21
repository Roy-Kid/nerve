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
    summary: "Jobs from the local hub."
  )

  let session = HubSession()
  private let banners = AskBanners()

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
    // Toolbar click is "start the plugin". Hub comes up here even when
    // Nerve.app is not running; activate() already tried at Tether launch.
    session.start()
    context.openWorkspace(NerveWorkspace(session: session, hostLabel: context.hostLabel))
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
