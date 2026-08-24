import Foundation

/// The one place the `nerve-hub` address lives.
///
/// The hub always listens on fixed loopback `127.0.0.1:17890` — the fixed port
/// *is* the single-instance lock, so there is nothing to configure and no
/// `NERVE_*` env to read (repo invariant 2). Producers POST snapshots there and
/// surfaces read frames from there.
enum NerveEndpoint {
    static let host = "127.0.0.1"
    /// `UInt16` to match the SSH tunnel and machine-config port fields.
    static let port: UInt16 = 17890

    /// `http://127.0.0.1:17890` — assembled from ``host`` / ``port`` so the two
    /// can never drift out of sync with a hand-written literal.
    static let baseURL: URL = {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        guard let url = components.url else {
            // Unreachable for constant loopback components: a failure here is a
            // build-time typo above, not a runtime condition.
            preconditionFailure("NerveEndpoint: \(host):\(port) is not a valid URL")
        }
        return url
    }()

    // MARK: Routes

    /// Liveness probe.
    static let health = baseURL.appending(path: "/v1/health")
    /// Current jobs in hub memory, each with its timeline.
    static let jobs = baseURL.appending(path: "/v1/jobs")
    /// Server-Sent Events — full ``HubFrame`` per event, never a delta.
    /// Callers add their own `surface` query item.
    static let stream = baseURL.appending(path: "/v1/stream")
    /// Drop every job the hub holds.
    static let clear = baseURL.appending(path: "/v1/clear")
    /// Load the built-in demo jobs.
    static let demo = baseURL.appending(path: "/v1/demo")
    /// Poll a producer's action queue (`producerId` query item added by caller).
    static let actionsPending = baseURL.appending(path: "/v1/actions/pending")
    /// Report action completion (`producerId` query item added by caller).
    static let actionsResult = baseURL.appending(path: "/v1/actions/result")
}
