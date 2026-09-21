import Foundation
import Observation

/// One SSE subscription for the Tether surface. Holding it open is this
/// surface's hub refcount. Fail-open: a missing hub paints an empty list.
@MainActor
@Observable
public final class HubSession {
  public private(set) var jobs: [NerveJob] = []
  public private(set) var notify: NotifyLease = .legacy
  public private(set) var connected = false
  /// Why the hub is not up, when it isn't. Cleared on a live attach.
  public private(set) var hubError: String?
  public var onAsk: ((NerveJob) -> Void)?

  private var stream: Task<Void, Never>?
  private var poll: Task<Void, Never>?
  private var streamSession: URLSession?
  private var previous: [String: NerveJob] = [:]
  private let decoder = JSONDecoder()
  private let shortSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 5
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }()

  public init() {}

  public func start() {
    guard stream == nil else { return }
    NerveLog.hub.info("start")
    stream = Task { [weak self] in
      await self?.run()
    }
    poll = Task { [weak self] in
      await self?.pollJobsUntilCancelled()
    }
  }

  public func stop() {
    NerveLog.hub.info("stop")
    stream?.cancel()
    stream = nil
    poll?.cancel()
    poll = nil
    streamSession?.invalidateAndCancel()
    streamSession = nil
    connected = false
  }

  /// Toolbar Reconnect: ask the hub to reap, drop a hung SSE socket, attach again.
  public func reconnect() {
    NerveLog.hub.info("reconnect")
    Task {
      await self.driveHubRefresh()
      self.stop()
      self.start()
    }
  }

  public func setPolicy(_ policy: String) {
    Task {
      var request = URLRequest(url: NerveEndpoint.notify)
      request.httpMethod = "PUT"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONEncoder().encode(["policy": policy])
      _ = try? await URLSession.shared.data(for: request)
    }
  }

  private func run() async {
    while !Task.isCancelled {
      switch await HubProcess.ensureRunning() {
      case .alreadyServing, .spawned:
        hubError = nil
      case .missing:
        hubError =
          "No nerve-hub binary on this Mac. Build it with `cargo build -p nerve-hub` in the nerve checkout, or install Nerve.app — Tether will start it even if the menu bar is closed."
        NerveLog.hub.error("hub missing")
      case .failed(let message):
        hubError = message
        NerveLog.hub.error("hub launch failed: \(message, privacy: .public)")
      }
      await pullJobs()
      do {
        try await readOneConnection()
        hubError = nil
      } catch {
        connected = false
        NerveLog.hub.error("stream ended: \(String(describing: error), privacy: .public)")
      }
      guard !Task.isCancelled else { return }
      try? await Task.sleep(for: .seconds(1))
    }
  }

  private func readOneConnection() async throws {
    var request = URLRequest(url: NerveEndpoint.streamURL)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    request.timeoutInterval = 45
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 45
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let queue = OperationQueue()
    queue.name = "app.nerve.tether.sse"
    queue.maxConcurrentOperationCount = 1
    let session = URLSession(configuration: configuration, delegate: nil, delegateQueue: queue)
    streamSession = session
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    connected = true
    NerveLog.hub.info("attached")
    try await Self.iterateSSE(bytes) { [weak self] event in
      await self?.apply(event)
    }
  }

  private nonisolated static func iterateSSE(
    _ bytes: URLSession.AsyncBytes,
    onEvent: @escaping @Sendable (String) async -> Void
  ) async throws {
    var payload: [String] = []
    for try await line in bytes.lines {
      if line.isEmpty {
        if !payload.isEmpty {
          let event = payload.joined(separator: "\n")
          payload.removeAll(keepingCapacity: true)
          await onEvent(event)
        }
        continue
      }
      if line.hasPrefix(":") { continue }
      if let value = field("data", in: line) {
        payload.append(value)
      }
    }
  }

  private func pollJobsUntilCancelled() async {
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      await pullJobs()
    }
  }

  private func driveHubRefresh() async {
    var request = URLRequest(url: NerveEndpoint.refresh)
    request.httpMethod = "POST"
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 5
    do {
      let (data, response) = try await shortSession.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        await pullJobs()
        return
      }
      jobs = try decoder.decode([NerveJob].self, from: data).filter { !$0.id.isEmpty }
      NerveLog.hub.info("hub refresh jobs \(self.jobs.count, privacy: .public)")
    } catch {
      NerveLog.hub.error("hub refresh failed: \(String(describing: error), privacy: .public)")
      await pullJobs()
    }
  }

  private func pullJobs() async {
    var request = URLRequest(url: NerveEndpoint.jobs)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 5
    do {
      let (data, response) = try await shortSession.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        return
      }
      jobs = try decoder.decode([NerveJob].self, from: data).filter { !$0.id.isEmpty }
      NerveLog.hub.debug("jobs \(self.jobs.count, privacy: .public)")
    } catch {
      NerveLog.hub.error("jobs fetch failed: \(String(describing: error), privacy: .public)")
    }
  }

  private func apply(_ raw: String) {
    guard let frame = try? decoder.decode(NerveFrame.self, from: Data(raw.utf8)) else {
      NerveLog.hub.error("frame decode failed")
      return
    }
    let next = Dictionary(frame.jobs.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    if frame.notify.mayInterrupt(surface: NerveEndpoint.surfaceName) {
      for job in frame.jobs where job.isAsk {
        let before = previous[job.id]
        if before == nil || !(before?.isAsk ?? false)
          || (before?.attentionLevel != job.attentionLevel)
        {
          onAsk?(job)
        }
      }
    }
    previous = next
    jobs = frame.jobs
    notify = frame.notify
    NerveLog.hub.debug("frame jobs \(frame.jobs.count, privacy: .public)")
  }

  private nonisolated static func field(_ name: String, in line: String) -> String? {
    guard let colon = line.firstIndex(of: ":") else { return nil }
    guard String(line[line.startIndex..<colon]) == name else { return nil }
    var value = line[line.index(after: colon)...]
    if value.hasPrefix(" ") { value = value.dropFirst() }
    return String(value)
  }
}
