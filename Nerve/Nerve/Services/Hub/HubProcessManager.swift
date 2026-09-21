import Foundation
import Observation

/// Makes sure a `nerve-hub` is up, without ever owning the one that is.
///
/// "Installed the app" has to mean "the hub is there": the binary ships inside
/// `Nerve.app/Contents/MacOS/`, this manager finds it, asks `/v1/health` whether
/// anything already owns the fixed loopback port, and spawns only when nothing
/// answers. A hub is shared infrastructure — a tmux surface, a `cargo install`
/// copy, or a hand-started `nerve-hub serve` may already hold the port and will
/// outlive this app — so there is deliberately no code here that stops one: no
/// stored `Process` handle, no `terminate()`, no `terminationHandler`. The hub
/// releases itself on its own SSE refcount + grace once the last surface goes.
///
/// Recovery is pull-based, not push-based: nothing here watches a child. When
/// ``HubClient`` loses its stream the surface calls ``ensureRunning()`` again,
/// which re-probes and, at most once per ``spawnThrottle`` window, re-spawns.
///
/// Shape follows `MachineTunnelManager` — arg-array `Process`, never a shell
/// string; observable state; `nonisolated` statics for the pure parts — without
/// sharing code with it: ssh tunnels and a local daemon have no common kernel
/// worth a base class. Knows an endpoint and a filesystem. It does not know
/// `JobStore`, and it never reads a frame.
@MainActor
@Observable
final class HubProcessManager {
    /// The binary looked for in every directory of the discovery sequence.
    private static let binaryName = "nerve-hub"
    /// Loopback has no latency to forgive: a hub that has not answered within a
    /// second is not there.
    private static let healthTimeout: TimeInterval = 1
    /// How long a freshly spawned hub gets to bind and answer before this call
    /// gives up on it. It may still come up later — the next probe will see it.
    private static let startupTimeout: TimeInterval = 3
    /// Gap between health polls while waiting on a spawn.
    private static let pollInterval: Duration = .milliseconds(120)
    /// At most one spawn per window. A hub that dies on every start would
    /// otherwise turn each reconnect attempt into another process.
    private static let spawnThrottle: TimeInterval = 10

    /// What the last ``ensureRunning()`` concluded. Recorded so a later Settings
    /// row can explain a blank ribbon; nothing paints it yet.
    enum LaunchState: Equatable {
        /// Never probed.
        case idle
        /// `/v1/health` answered. Whose hub it is makes no difference.
        case running
        /// The discovery sequence came up empty — no `nerve-hub` on this Mac.
        case notInstalled
        /// A binary exists but no hub answers; the text says why.
        case unreachable(String)
    }

    private(set) var state: LaunchState = .idle

    private let session: URLSession
    /// Overlapping calls collapse into one: a dropped stream and a fresh launch
    /// can both ask at the same moment, and only the first should probe.
    private var ensuring = false
    /// When `try process.run()` last succeeded, for the throttle window.
    private var lastSpawnAt: Date?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = HubProcessManager.healthTimeout
        configuration.timeoutIntervalForResource = HubProcessManager.healthTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Ensure

    /// Probe first, spawn only if nothing answers.
    ///
    /// Never throws and never fails loudly: a surface that cannot start a hub
    /// still runs (fail-open, repo invariant 2) — it just paints nothing until
    /// a hub appears. Safe to call on every reconnect; the health probe is what
    /// keeps a second hub from ever being spawned.
    func ensureRunning() async {
        guard !ensuring else { return }
        ensuring = true
        defer { ensuring = false }

        if await hubAnswers() {
            state = .running
            return
        }

        guard let binary = Self.locateBinary() else {
            state = .notInstalled
            NerveLog.hub.error("no \(Self.binaryName, privacy: .public) binary found — start one by hand or reinstall Nerve")
            return
        }

        // The one clock read of this call: swapping it for an injected `now` is
        // the whole seam a throttle test would need.
        let now = Date()
        if let last = lastSpawnAt, now.timeIntervalSince(last) < Self.spawnThrottle {
            // Reaching here means the probe above already failed, so the state
            // must say so — leaving the previous `.running` would have the UI
            // claim a hub that is demonstrably not answering.
            state = .unreachable("hub is not answering; waiting out the restart window")
            NerveLog.hub.info("hub spawn throttled (one per \(Self.spawnThrottle, privacy: .public)s)")
            return
        }
        lastSpawnAt = now

        do {
            try Self.spawn(binary)
        } catch {
            state = .unreachable(error.localizedDescription)
            NerveLog.hub.error("could not spawn \(binary.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        NerveLog.hub.info("spawned hub: \(binary.path, privacy: .public) serve")

        if await waitForHub() {
            state = .running
        } else {
            state = .unreachable("hub did not answer within \(Int(Self.startupTimeout))s of starting")
            NerveLog.hub.error("hub silent \(Self.startupTimeout, privacy: .public)s after spawn")
        }
    }

    // MARK: - Discovery

    /// The first `nerve-hub` that exists and is executable, in descending order
    /// of how sure we are it is the right one.
    ///
    /// Bundle first, because the copy shipped next to this app is the one built
    /// against this surface. Then the two Homebrew prefixes (Apple silicon,
    /// Intel), then `cargo install`'s bin. `PATH` comes last on purpose: an app
    /// launched from Finder inherits `launchd`'s bare `PATH`, so it is a
    /// dev-shell courtesy, not a real channel.
    static func locateBinary() -> URL? {
        let fileManager = FileManager.default
        for directory in searchDirectories() {
            let candidate = directory.appending(path: binaryName)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func searchDirectories() -> [URL] {
        var directories: [URL] = []

        // `Contents/MacOS` — where `scripts/run.sh` embeds it.
        if let executables = Bundle.main.executableURL?.deletingLastPathComponent() {
            directories.append(executables)
        }
        // `Contents/Resources` — a packaging path that treats the hub as a
        // resource rather than an auxiliary executable still works.
        if let resources = Bundle.main.resourceURL {
            directories.append(resources)
        }

        directories.append(URL(fileURLWithPath: "/opt/homebrew/bin"))
        directories.append(URL(fileURLWithPath: "/usr/local/bin"))
        directories.append(
            FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cargo/bin")
        )

        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for segment in path.split(separator: ":") where !segment.isEmpty {
            directories.append(URL(fileURLWithPath: String(segment)))
        }

        return directories
    }

    // MARK: - Spawn

    /// `nerve-hub serve`, started and forgotten.
    ///
    /// The `Process` is deliberately not stored. Keeping a handle is what
    /// eventually invites a `terminate()` in some quit path, and this app does
    /// not get to end a hub other surfaces may be reading. Nothing is lost by
    /// dropping it: a hub that exits — bind conflict, or its own grace timer —
    /// is announced by the stream dying, which is already the retry trigger.
    private static func spawn(_ binary: URL) throws {
        let process = Process()
        process.executableURL = binary
        // Arg array, never a shell string: nothing to quote, nothing to escape.
        process.arguments = ["serve"]
        // Minimal environment. The hub reads no `NERVE_*` and binds a fixed
        // loopback address (repo invariant 2), so it wants a home directory and
        // a sane `PATH` and none of whatever this app happens to be carrying.
        process.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        // A detached daemon has no console: discard all three streams rather
        // than inherit descriptors that die with this app.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    // MARK: - Health

    /// One `GET /v1/health`. Any 2xx means a hub owns the port.
    private func hubAnswers() async -> Bool {
        var request = URLRequest(url: NerveEndpoint.health)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.healthTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    /// Poll until the hub just spawned binds, or the startup budget runs out.
    private func waitForHub() async -> Bool {
        let deadline = Date().addingTimeInterval(Self.startupTimeout)
        while Date() < deadline {
            try? await Task.sleep(for: Self.pollInterval)
            if await hubAnswers() { return true }
        }
        return false
    }
}
