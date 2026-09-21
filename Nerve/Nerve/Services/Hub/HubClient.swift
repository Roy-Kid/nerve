import Foundation

/// The macOS surface's link to `nerve-hub`.
///
/// Consumes the SSE frame stream, recovers `(previous, next)` job pairs with
/// ``FrameDiffer``, writes the frame into ``JobStore`` and only then hands each
/// pair to the store's `notificationSink` — write first, notify after, the same
/// order the in-process store used when it owned state.
///
/// Knows a store and an endpoint and nothing else: no view, no settings, no
/// process management. When the stream drops it reports that through
/// ``onStreamEnded`` and keeps retrying; whether a hub needs starting again is
/// somebody else's judgement (`HubProcessManager`), not this client's.
@MainActor
final class HubClient {
    /// First reconnect wait, and the floor every successful attach resets to.
    private static let minRetryDelay: TimeInterval = 1
    /// Ceiling for the doubling backoff. Loopback, so it never needs to be shy.
    private static let maxRetryDelay: TimeInterval = 30
    /// One-shot `GET /v1/jobs` — not the long-lived stream timeout.
    private static let jobsFetchTimeout: TimeInterval = 5
    /// While SSE is up, re-pull `/v1/jobs` on this interval. A hung URLSession
    /// stream still looks ESTABLISHED; without this the panel stays empty.
    private static let jobsPollInterval: TimeInterval = 3

    /// `?surface=` is a log tag on the hub side — every surface sees every frame.
    private static let streamURL: URL = {
        guard var components = URLComponents(
            url: NerveEndpoint.stream,
            resolvingAgainstBaseURL: false
        ) else {
            return NerveEndpoint.stream
        }
        components.queryItems = [URLQueryItem(name: "surface", value: "macos")]
        return components.url ?? NerveEndpoint.stream
    }()

    private let store: JobStore
    private let session: URLSession
    /// Short GETs/POSTs. The stream session's 1h request timeout must not
    /// apply to `/v1/jobs`, and a live SSE socket must not occupy the only
    /// connection the refresh pull needs.
    private let shortSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Called on the main actor each time an attach attempt ends and before the
    /// backoff sleep — a losing connection is the only crash signal this app
    /// gets. Never called after ``disconnect()``: a quitting app must not be the
    /// reason a hub comes back.
    var onStreamEnded: (() -> Void)?

    private var differ = FrameDiffer()
    private var stream: Task<Void, Never>?
    /// Independent of the SSE reader so a hung `bytes.lines` cannot freeze Refresh.
    private var poll: Task<Void, Never>?
    private var retryDelay: TimeInterval = HubClient.minRetryDelay

    init(store: JobStore) {
        self.store = store

        let configuration = URLSessionConfiguration.ephemeral
        // Keep-alives land every ~15s. A hung socket that still looks ESTABLISHED
        // must die well before an hour, or the panel stays empty with no retry.
        configuration.timeoutIntervalForRequest = 45
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let streamQueue = OperationQueue()
        streamQueue.name = "app.nerve.Nerve.sse"
        streamQueue.maxConcurrentOperationCount = 1
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: streamQueue)

        let short = URLSessionConfiguration.ephemeral
        short.timeoutIntervalForRequest = Self.jobsFetchTimeout
        short.waitsForConnectivity = false
        short.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.shortSession = URLSession(configuration: short)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    // MARK: - Connection

    /// Attach to the frame stream and keep re-attaching until ``disconnect()``.
    func connect() {
        guard stream == nil else { return }
        stream = Task { [weak self] in
            await self?.readFrames()
        }
        poll = Task { [weak self] in
            await self?.pollJobsUntilCancelled()
        }
    }

    /// Stop reading frames. The hub keeps running — other surfaces and the
    /// producers that push into it are none of this app's business.
    func disconnect() {
        stream?.cancel()
        stream = nil
        poll?.cancel()
        poll = nil
        retryDelay = Self.minRetryDelay
    }

    // MARK: - Commands

    /// Panel Clear: drop every job the hub holds. Clearing the local cache
    /// instead would be undone by the very next frame.
    func clearAll() {
        post(to: NerveEndpoint.clear, body: nil, what: "clear")
    }

    /// First-run coach / Settings demo. The hub owns the demo jobs, so they
    /// arrive the same way real ones do — as a frame.
    func loadDemo() {
        post(to: NerveEndpoint.demo, body: nil, what: "demo")
    }

    /// Panel Refresh: ask the hub to reap dead producers and republish, then
    /// paint the returned job list. Do not tear the SSE stream down.
    func refresh() {
        Task { await driveHubRefresh() }
    }

    /// Report how an action the hub handed to a producer ended.
    ///
    /// The pending queue is dormant on both sides (Nerve is display-only and
    /// never reverse-controls an agent), so no surface path reaches this yet —
    /// it is the write half of `/v1/actions/result` that the hub still answers.
    func postActionResult(_ result: ActionResultBody, producerId: String?) {
        guard var components = URLComponents(
            url: NerveEndpoint.actionsResult,
            resolvingAgainstBaseURL: false
        ) else { return }
        if let producerId, !producerId.isEmpty {
            components.queryItems = [URLQueryItem(name: "producerId", value: producerId)]
        }
        guard let url = components.url else { return }
        guard let body = try? encoder.encode(result) else { return }
        post(to: url, body: body, what: "action result")
    }

    // MARK: - Stream

    /// Read frames forever, backing off 1s → 30s between attempts and resetting
    /// the moment one attaches.
    private func readFrames() async {
        while !Task.isCancelled {
            await syncFromHub()
            do {
                try await readOneConnection()
                NerveLog.hub.info("hub closed the stream")
            } catch {
                NerveLog.hub.error("hub stream ended: \(String(describing: error), privacy: .public)")
            }
            guard !Task.isCancelled else { return }
            // After the cancellation guard, so `disconnect()` never fires it.
            onStreamEnded?()

            let delay = retryDelay
            retryDelay = min(Self.maxRetryDelay, retryDelay * 2)
            NerveLog.hub.info("reconnecting to hub in \(delay, privacy: .public)s")
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// One attach, held until the connection drops.
    private func readOneConnection() async throws {
        var request = URLRequest(url: Self.streamURL)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StreamFailure.notHTTP
        }
        guard http.statusCode == 200 else {
            throw StreamFailure.status(http.statusCode)
        }

        retryDelay = Self.minRetryDelay
        NerveLog.record("attached to hub at \(Self.streamURL.absoluteString)")

        // Read off the main actor. A MainActor `for await bytes.lines` can
        // stall the executor: Refresh, polling and SwiftUI then all freeze
        // while the TCP socket still looks ESTABLISHED.
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
            if let value = value(ofField: "data", in: line) {
                payload.append(value)
            }
        }
    }

    private func pollJobsUntilCancelled() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.jobsPollInterval))
            guard !Task.isCancelled else { return }
            await syncFromHub()
        }
    }

    /// Frame → cache → notifications, in that order.
    private func apply(_ payload: String) {
        let frame: HubFrame
        do {
            frame = try decoder.decode(HubFrame.self, from: Data(payload.utf8))
        } catch {
            // One unreadable frame is not worth dropping the connection over:
            // the next frame is a full snapshot and restores everything.
            NerveLog.record("hub frame ignored (decode failed): \(error)")
            return
        }
        NerveLog.record("frame jobs=\(frame.jobs.count) notify=\(frame.notify.owner ?? "-")")
        applyFrame(frame)
    }

    /// `POST /v1/refresh` — hub runs maintenance and answers the job list.
    /// Falls back to `GET /v1/jobs` on an older hub that does not have the route.
    private func driveHubRefresh() async {
        var request = URLRequest(url: NerveEndpoint.refresh)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Self.jobsFetchTimeout
        do {
            let (data, response) = try await shortSession.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                NerveLog.record("hub refresh HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0); falling back to GET")
                await syncFromHub()
                return
            }
            var frame = try HubFrame(jobsListJSON: data, decoder: decoder)
            frame.notify = store.notify
            NerveLog.record("hub refresh jobs=\(frame.jobs.count)")
            applyFrame(frame)
        } catch {
            NerveLog.record("hub refresh failed: \(error); falling back to GET")
            await syncFromHub()
        }
    }

    /// `GET /v1/jobs` before (re)attaching to SSE — paint immediately, not
    /// after the first stream event.
    private func syncFromHub() async {
        var request = URLRequest(url: NerveEndpoint.jobs)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Self.jobsFetchTimeout
        do {
            let (data, response) = try await shortSession.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return
            }
            var frame = try HubFrame(jobsListJSON: data, decoder: decoder)
            // `/v1/jobs` is a bare array — it has no notify lease. Keep the
            // one the stream already elected, or a refresh would look like an
            // older hub (everyone may banner) until the next SSE frame.
            frame.notify = store.notify
            if frame.jobs.count != store.activeCount {
                NerveLog.record("jobs pull \(frame.jobs.count)")
            }
            applyFrame(frame)
        } catch {
            NerveLog.record("hub jobs fetch failed: \(error)")
        }
    }

    private func applyFrame(_ frame: HubFrame) {
        let pairs = differ.pairs(for: frame)
        store.applyFrame(jobs: frame.jobs, timelines: frame.timelines, notify: frame.notify)
        guard frame.notify.mayInterrupt(surface: "macos") else { return }
        for pair in pairs {
            store.notificationSink?(pair.previous, pair.next)
        }
    }

    /// The value of one SSE field line, or nil when the line names another field.
    private nonisolated static func value(ofField field: String, in line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        guard String(line[line.startIndex..<colon]) == field else { return nil }
        var value = line[line.index(after: colon)...]
        // A single leading space after the colon is framing, not content.
        if value.hasPrefix(" ") { value = value.dropFirst() }
        return String(value)
    }

    // MARK: - Writes

    /// `PUT /v1/notify` — `single` (one owner) or `all` (every surface).
    func setNotifyPolicy(_ policy: String) {
        let body = try? encoder.encode(["policy": policy])
        put(to: NerveEndpoint.notify, body: body, what: "notify")
    }

    private func put(to url: URL, body: Data?, what: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        Task { [shortSession] in
            do {
                let (_, response) = try await shortSession.data(for: request)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    NerveLog.hub.error("hub refused \(what, privacy: .public) (HTTP \(http.statusCode, privacy: .public))")
                }
            } catch {
                NerveLog.hub.error("hub \(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func post(to url: URL, body: Data?, what: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        Task { [shortSession] in
            do {
                let (_, response) = try await shortSession.data(for: request)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    NerveLog.hub.error("hub refused \(what, privacy: .public) (HTTP \(http.statusCode, privacy: .public))")
                }
            } catch {
                NerveLog.hub.error("hub \(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private enum StreamFailure: Error, CustomStringConvertible {
        case notHTTP
        case status(Int)

        var description: String {
            switch self {
            case .notHTTP:
                return "hub answered with a non-HTTP response"
            case .status(let code):
                return "hub answered HTTP \(code) — is `nerve-hub serve` running?"
            }
        }
    }
}
