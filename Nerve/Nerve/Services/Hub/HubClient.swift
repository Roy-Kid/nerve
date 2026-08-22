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
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Called on the main actor each time an attach attempt ends and before the
    /// backoff sleep — a losing connection is the only crash signal this app
    /// gets. Never called after ``disconnect()``: a quitting app must not be the
    /// reason a hub comes back.
    var onStreamEnded: (() -> Void)?

    private var differ = FrameDiffer()
    private var stream: Task<Void, Never>?
    private var retryDelay: TimeInterval = HubClient.minRetryDelay

    init(store: JobStore) {
        self.store = store

        let configuration = URLSessionConfiguration.ephemeral
        // A live stream is idle between frames; only a dead socket should time
        // out, and the hub's keep-alive comments hold the timer off.
        configuration.timeoutIntervalForRequest = 3600
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)

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
    }

    /// Stop reading frames. The hub keeps running — other surfaces and the
    /// producers that push into it are none of this app's business.
    func disconnect() {
        stream?.cancel()
        stream = nil
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
            do {
                try await readOneConnection()
                NSLog("[Nerve] hub closed the stream")
            } catch {
                NSLog("[Nerve] hub stream ended: %@", "\(error)")
            }
            guard !Task.isCancelled else { return }
            // After the cancellation guard, so `disconnect()` never fires it.
            onStreamEnded?()

            let delay = retryDelay
            retryDelay = min(Self.maxRetryDelay, retryDelay * 2)
            NSLog("[Nerve] reconnecting to hub in %.0fs", delay)
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
        NSLog("[Nerve] attached to hub at %@", Self.streamURL.absoluteString)

        // SSE framing: `data:` lines accumulate until a blank line ends the
        // event, and a line opening with `:` is the keep-alive comment.
        var payload: [String] = []
        for try await line in bytes.lines {
            if line.isEmpty {
                if !payload.isEmpty {
                    apply(payload.joined(separator: "\n"))
                    payload.removeAll(keepingCapacity: true)
                }
                continue
            }
            if line.hasPrefix(":") { continue }
            if let value = Self.value(ofField: "data", in: line) {
                payload.append(value)
            }
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
            NSLog("[Nerve] hub frame ignored (decode failed): %@", "\(error)")
            return
        }

        let pairs = differ.pairs(for: frame)
        store.applyFrame(jobs: frame.jobs, timelines: frame.timelines)
        for pair in pairs {
            store.notificationSink?(pair.previous, pair.next)
        }
    }

    /// The value of one SSE field line, or nil when the line names another field.
    private static func value(ofField field: String, in line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        guard String(line[line.startIndex..<colon]) == field else { return nil }
        var value = line[line.index(after: colon)...]
        // A single leading space after the colon is framing, not content.
        if value.hasPrefix(" ") { value = value.dropFirst() }
        return String(value)
    }

    // MARK: - Writes

    private func post(to url: URL, body: Data?, what: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        Task { [session] in
            do {
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    NSLog("[Nerve] hub refused %@ (HTTP %d)", what, http.statusCode)
                }
            } catch {
                NSLog("[Nerve] hub %@ failed: %@", what, "\(error)")
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
