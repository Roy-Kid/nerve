import Foundation
import Network

/// Loopback HTTP JSON ingest for jobs.
/// POST /v1/snapshot  { "alias", "machineKind"?, "jobs": [ ... ] }
/// POST /v1/events    { "alias"?, "events": [ ... ] }
/// GET  /v1/health
/// GET  /v1/jobs
final class IngestServer: @unchecked Sendable {
    private let port: NWEndpoint.Port
    private let store: JobStore
    private let settingsProvider: () -> SettingsStore?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.nerve.ingest", qos: .userInitiated)
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private(set) var isRunning = false
    private(set) var boundPort: UInt16 = 0

    init(port: UInt16, store: JobStore, settingsProvider: @escaping () -> SettingsStore? = { nil }) {
        self.port = NWEndpoint.Port(rawValue: port) ?? 17890
        self.store = store
        self.settingsProvider = settingsProvider
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: port)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                    if let p = listener.port?.rawValue {
                        self?.boundPort = p
                        NSLog("[Nerve] Ingest listening on 127.0.0.1:%u", p)
                    }
                case .failed(let error):
                    NSLog("[Nerve] Ingest failed: %@", "\(error)")
                    self?.isRunning = false
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(connection: conn)
            }
            listener.start(queue: queue)
        } catch {
            NSLog("[Nerve] Ingest could not start: %@", "\(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveHeader(connection: connection, buffer: Data())
    }

    private func receiveHeader(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                NSLog("[Nerve] receive error: %@", "\(error)")
                connection.cancel()
                return
            }
            var buf = buffer
            if let data { buf.append(data) }

            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buf.subdata(in: buf.startIndex..<range.lowerBound)
                let header = String(data: headerData, encoding: .utf8) ?? ""
                let rest = buf.subdata(in: range.upperBound..<buf.endIndex)
                let contentLength = Self.parseContentLength(header) ?? 0
                if rest.count >= contentLength {
                    let body = rest.prefix(contentLength)
                    self.respond(connection: connection, header: header, body: Data(body))
                } else {
                    self.receiveBody(connection: connection, header: header, body: rest, remaining: contentLength - rest.count)
                }
            } else if isComplete {
                connection.cancel()
            } else if buf.count > 1024 * 1024 {
                self.send(connection: connection, status: 413, body: #"{"error":"too large"}"#)
            } else {
                self.receiveHeader(connection: connection, buffer: buf)
            }
        }
    }

    private func receiveBody(connection: NWConnection, header: String, body: Data, remaining: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: max(remaining, 1)) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            var buf = body
            if let data { buf.append(data) }
            let need = Self.parseContentLength(header) ?? 0
            if buf.count >= need {
                self.respond(connection: connection, header: header, body: Data(buf.prefix(need)))
            } else if isComplete {
                self.respond(connection: connection, header: header, body: buf)
            } else {
                self.receiveBody(connection: connection, header: header, body: buf, remaining: need - buf.count)
            }
        }
    }

    private func respond(connection: NWConnection, header: String, body: Data) {
        if let ep = connection.currentPath?.remoteEndpoint, case .hostPort(let host, _) = ep {
            switch host {
            case .ipv4(let addr):
                let s = "\(addr)"
                if s != "127.0.0.1" && !s.hasPrefix("127.") {
                    send(connection: connection, status: 403, body: #"{"error":"loopback only"}"#)
                    return
                }
            case .ipv6(let addr):
                let s = "\(addr)"
                if s != "::1" && s != "0:0:0:0:0:0:0:1" {
                    send(connection: connection, status: 403, body: #"{"error":"loopback only"}"#)
                    return
                }
            default:
                break
            }
        }

        let lines = header.split(separator: "\r\n", omittingEmptySubsequences: false)
        let requestLine = lines.first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        do {
            let (status, payload) = try route(method: method, path: path, body: body)
            send(connection: connection, status: status, body: payload)
        } catch {
            send(connection: connection, status: 400, body: "{\"error\":\(Self.jsonString("\(error)"))}")
        }
    }

    private func route(method: String, path: String, body: Data) throws -> (Int, String) {
        let pathOnly = path.split(separator: "?").first.map(String.init) ?? path
        let query = Self.parseQuery(path)

        switch (method, pathOnly) {
        case ("GET", "/v1/health"), ("GET", "/health"):
            return (200, #"{"ok":true,"service":"nerve","version":"0.1.0"}"#)

        case ("GET", "/v1/jobs"), ("GET", "/v1/subjects"):
            let list = store.allJobs
            let data = try encoder.encode(list)
            return (200, String(data: data, encoding: .utf8) ?? "[]")

        case ("GET", "/v1/actions/pending"):
            let producerId = query["producerId"] ?? query["sourceId"]
            let list = DispatchQueue.main.sync {
                store.expireStalePendingActions()
                return store.openPendingActions(forProducer: producerId)
            }
            let data = try encoder.encode(list)
            return (200, String(data: data, encoding: .utf8) ?? "[]")

        case ("POST", "/v1/actions/result"):
            let result = try decoder.decode(ActionResultBody.self, from: body)
            let producerId = query["producerId"] ?? query["sourceId"]
            let ok = DispatchQueue.main.sync {
                store.completePendingAction(
                    id: result.id,
                    state: result.state,
                    message: result.message,
                    producerId: producerId
                )
            }
            if ok {
                return (200, #"{"ok":true}"#)
            }
            return (404, #"{"error":"pending action not found or producer mismatch"}"#)

        case ("POST", "/v1/events"):
            var envelope = try decodeEnvelope(body)
            if let err = validateAndNormalize(&envelope) {
                return err
            }
            let n = DispatchQueue.main.sync {
                store.apply(envelope: envelope)
            }
            return (200, "{\"applied\":\(n)}")

        case ("POST", "/v1/snapshot"):
            var envelope = try decodeSnapshot(body)
            if let err = validateAndNormalize(&envelope) {
                return err
            }
            let n = DispatchQueue.main.sync {
                store.apply(envelope: envelope)
            }
            return (200, "{\"applied\":\(n)}")

        case ("POST", "/v1/demo"):
            DispatchQueue.main.sync {
                store.loadDemo()
            }
            return (200, #"{"ok":true,"demo":true}"#)

        case ("POST", "/v1/clear"):
            DispatchQueue.main.sync {
                store.clearAll()
            }
            return (200, #"{"ok":true}"#)

        case ("POST", "/v1/actions/invoke"):
            struct InvokeBody: Codable {
                var jobId: String?
                var subjectId: String?
                var actionId: String
                var confirmed: Bool?
            }
            let inv = try decoder.decode(InvokeBody.self, from: body)
            let jobId = inv.jobId ?? inv.subjectId ?? ""
            let msg = DispatchQueue.main.sync { () -> String in
                let result = store.performAction(
                    actionId: inv.actionId,
                    jobId: jobId,
                    confirmed: inv.confirmed ?? true
                )
                switch result {
                case .succeeded(let m): return "succeeded:\(m)"
                case .failed(let m): return "failed:\(m)"
                case .pending(let m): return "pending:\(m)"
                case .unsupported: return "unsupported"
                case .denied(let m): return "denied:\(m)"
                }
            }
            return (200, "{\"result\":\(Self.jsonString(msg))}")

        default:
            return (404, #"{"error":"not found"}"#)
        }
    }

    /// Require a non-empty alias; keep the reported string as-is (no allow-list, no rename).
    private func validateAndNormalize(_ envelope: inout IngestEnvelope) -> (Int, String)? {
        let rawAlias = envelope.alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fromJobs = envelope.jobs?.first(where: { !$0.alias.isEmpty })?.alias
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reported = rawAlias.isEmpty ? fromJobs : rawAlias
        if reported.isEmpty {
            return (400, #"{"error":"alias required"}"#)
        }
        envelope.alias = reported
        if var jobs = envelope.jobs {
            for i in jobs.indices {
                let jobAlias = jobs[i].alias.trimmingCharacters(in: .whitespacesAndNewlines)
                jobs[i].alias = jobAlias.isEmpty ? reported : jobAlias
            }
            envelope.jobs = jobs
        }
        return nil
    }

    private static func parseQuery(_ path: String) -> [String: String] {
        guard let qIndex = path.firstIndex(of: "?") else { return [:] }
        let q = path[path.index(after: qIndex)...]
        var out: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                out[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
            }
        }
        return out
    }

    private func decodeEnvelope(_ body: Data) throws -> IngestEnvelope {
        if body.isEmpty { return IngestEnvelope() }
        if let env = try? decoder.decode(IngestEnvelope.self, from: body) {
            return env
        }
        if let events = try? decoder.decode([NerveEvent].self, from: body) {
            return IngestEnvelope(events: events)
        }
        if let event = try? decoder.decode(NerveEvent.self, from: body) {
            return IngestEnvelope(events: [event])
        }
        throw IngestError.invalidJSON
    }

    private func decodeSnapshot(_ body: Data) throws -> IngestEnvelope {
        if body.isEmpty { return IngestEnvelope() }
        if let env = try? decoder.decode(IngestEnvelope.self, from: body) {
            return env
        }
        throw IngestError.invalidJSON
    }

    private func send(connection: NWConnection, status: Int, body: String) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        default: reason = "Error"
        }
        let data = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(data.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r

        """
        var message = Data(header.utf8)
        message.append(data)
        connection.send(content: message, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func parseContentLength(_ header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                return Int(parts[1])
            }
        }
        return 0
    }

    private static func jsonString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

enum IngestError: Error {
    case invalidJSON
}
