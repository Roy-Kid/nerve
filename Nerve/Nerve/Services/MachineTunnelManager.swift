import Foundation
import Observation

/// SSH reverse tunnels for remotes listed from `~/.ssh/config`.
///
/// Prefer ControlMaster when a master is already up (OTP/captcha clusters):
/// `ssh -O forward` attaches the reverse tunnel without a long-lived slave.
/// Otherwise fall back to `ssh -n -N`.
@MainActor
@Observable
final class MachineTunnelManager {
    private(set) var linkState: [UUID: MachineLinkState] = [:]
    private(set) var lastError: [UUID: String] = [:]

    private var processes: [UUID: Process] = [:]
    /// Forward held by ControlMaster (`ssh -O forward`), not a Process.
    private var muxHeld: Set<UUID> = []
    private var restartWork: [UUID: DispatchWorkItem] = [:]
    private var connectGeneration: [UUID: UInt64] = [:]

    private weak var settings: SettingsStore?

    func attach(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard let settings else { return }
        settings.refreshMachinesFromLocalSSH()
        syncConfig()
        for m in settings.machines where m.enabled && m.autoConnect {
            connect(id: m.id)
        }
    }

    func stopAll() {
        let ids = Set(processes.keys).union(muxHeld).union(connectGeneration.keys)
        for id in ids {
            disconnect(id: id, clearError: true)
        }
        restartWork.values.forEach { $0.cancel() }
        restartWork.removeAll()
    }

    /// Re-read `~/.ssh/config` and rewrite the managed RemoteForward block.
    func refreshFromLocalSSH() {
        guard let settings else { return }
        let previous = Set(settings.machines.map(\.id))
        settings.refreshMachinesFromLocalSSH()
        let next = Set(settings.machines.map(\.id))
        for gone in previous.subtracting(next) {
            disconnect(id: gone, clearError: true)
        }
        syncConfig()
    }

    func syncConfig() {
        guard let settings else { return }
        let machines = settings.machines
        let port = NerveEndpoint.port
        Task.detached(priority: .userInitiated) {
            do {
                try SSHConfigWriter.sync(machines: machines, localIngestPort: port)
            } catch {
                NerveLog.tunnel.error("SSH config sync failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func connect(id: UUID) {
        guard let settings, let machine = settings.machines.first(where: { $0.id == id }) else { return }
        guard machine.enabled else { return }
        guard !machine.alias.isEmpty else {
            setError(id: id, "Alias is required")
            return
        }

        disconnect(id: id, clearError: true)
        let generation = bumpGeneration(id)
        linkState[id] = .connecting
        lastError[id] = nil

        let machines = settings.machines
        let localPort = NerveEndpoint.port
        let alias = machine.alias
        let remotePort = machine.remoteIngestPort
        let probeHost = machine.hostName.isEmpty ? machine.alias : machine.hostName
        let probePort = machine.sshPort

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try SSHConfigWriter.sync(machines: machines, localIngestPort: localPort)
            } catch {
                NerveLog.tunnel.error("SSH config sync failed: \(String(describing: error), privacy: .public)")
            }

            let known = Self.hostKeyKnown(host: probeHost, alias: alias, port: probePort)

            if SSHCLI.controlMasterRunning(alias: alias) {
                let result = SSHCLI.muxForward(alias: alias, remotePort: remotePort, localPort: localPort)
                await MainActor.run { [weak self] in
                    self?.finishMuxAttempt(
                        id: id,
                        alias: alias,
                        generation: generation,
                        hostKeyKnown: known,
                        result: result
                    )
                }
                return
            }

            await MainActor.run { [weak self] in
                self?.startSSHProcess(
                    id: id,
                    alias: alias,
                    remotePort: remotePort,
                    localPort: localPort,
                    generation: generation,
                    hostKeyKnown: known
                )
            }
        }
    }

    func disconnect(id: UUID, clearError: Bool = false) {
        restartWork[id]?.cancel()
        restartWork[id] = nil
        _ = bumpGeneration(id)

        if let p = processes[id] {
            p.terminationHandler = nil
            if p.isRunning { p.terminate() }
        }
        processes[id] = nil

        if muxHeld.remove(id) != nil,
           let settings,
           let machine = settings.machines.first(where: { $0.id == id }) {
            let alias = machine.alias
            let remotePort = machine.remoteIngestPort
            let localPort = NerveEndpoint.port
            Task.detached(priority: .utility) {
                _ = SSHCLI.muxCancel(alias: alias, remotePort: remotePort, localPort: localPort)
            }
        }

        linkState[id] = .idle
        if clearError { lastError[id] = nil }
    }

    func reconnectAllEnabled() {
        guard let settings else { return }
        syncConfig()
        for m in settings.machines where m.enabled {
            connect(id: m.id)
        }
    }

    func state(for id: UUID) -> MachineLinkState { linkState[id] ?? .idle }
    func error(for id: UUID) -> String? { lastError[id] }

    // MARK: - Private

    private func bumpGeneration(_ id: UUID) -> UInt64 {
        let next = (connectGeneration[id] ?? 0) + 1
        connectGeneration[id] = next
        return next
    }

    private func setError(id: UUID, _ message: String) {
        linkState[id] = .error
        lastError[id] = message
    }

    private func finishMuxAttempt(
        id: UUID,
        alias: String,
        generation: UInt64,
        hostKeyKnown: Bool,
        result: SSHCLI.Result
    ) {
        guard connectGeneration[id] == generation, linkState[id] == .connecting else { return }
        if result.ok {
            muxHeld.insert(id)
            linkState[id] = .connected
            lastError[id] = nil
            return
        }
        setError(
            id: id,
            Self.friendlyError(
                stderr: result.stderr,
                status: result.status,
                hostKeyKnown: hostKeyKnown,
                alias: alias,
                mux: true
            )
        )
    }

    private func startSSHProcess(
        id: UUID,
        alias: String,
        remotePort: UInt16,
        localPort: UInt16,
        generation: UInt64,
        hostKeyKnown: Bool
    ) {
        guard connectGeneration[id] == generation, linkState[id] == .connecting else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-n", "-N",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=12",
            "-o", "ExitOnForwardFailure=yes",
            "-R", "\(remotePort):127.0.0.1:\(localPort)",
            alias,
        ]
        let errPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        process.terminationHandler = { [weak self] proc in
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let status = proc.terminationStatus
            Task { @MainActor in
                self?.handleProcessExit(
                    id: id,
                    status: status,
                    stderr: errText,
                    generation: generation,
                    hostKeyKnown: hostKeyKnown,
                    alias: alias
                )
            }
        }

        do {
            try process.run()
            processes[id] = process
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                guard self.connectGeneration[id] == generation else { return }
                if self.processes[id]?.isRunning == true {
                    self.linkState[id] = .connected
                    self.lastError[id] = nil
                }
            }
        } catch {
            setError(id: id, error.localizedDescription)
            processes[id] = nil
        }
    }

    private func handleProcessExit(
        id: UUID,
        status: Int32,
        stderr: String,
        generation: UInt64,
        hostKeyKnown: Bool,
        alias: String
    ) {
        guard connectGeneration[id] == generation else { return }
        processes[id] = nil

        let remotePort = settings?.machines.first(where: { $0.id == id })?.remoteIngestPort ?? 17890
        let localPort = NerveEndpoint.port
        let autoRetry = settings?.machines.first(where: { $0.id == id }).map { $0.enabled && $0.autoConnect } ?? false

        Task.detached(priority: .userInitiated) { [weak self] in
            // Slave often exits under ControlMaster — hand off to mux forward if master is up.
            if SSHCLI.controlMasterRunning(alias: alias) {
                let result = SSHCLI.muxForward(alias: alias, remotePort: remotePort, localPort: localPort)
                let errText = result.stderr.isEmpty ? stderr : result.stderr
                await MainActor.run { [weak self] in
                    self?.finishMuxAttempt(
                        id: id,
                        alias: alias,
                        generation: generation,
                        hostKeyKnown: hostKeyKnown,
                        result: result.ok
                            ? result
                            : SSHCLI.Result(status: result.status, stderr: errText)
                    )
                }
                return
            }

            let message = Self.friendlyError(
                stderr: stderr,
                status: status,
                hostKeyKnown: hostKeyKnown,
                alias: alias,
                mux: false
            )
            let hard = Self.isHardFailure(stderr: stderr, hostKeyKnown: hostKeyKnown)
            await MainActor.run { [weak self] in
                guard let self, self.connectGeneration[id] == generation else { return }
                self.setError(id: id, message)
                guard !hard, autoRetry else { return }
                let work = DispatchWorkItem { [weak self] in
                    self?.connect(id: id)
                }
                self.restartWork[id]?.cancel()
                self.restartWork[id] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
            }
        }
    }

    nonisolated private static func hostKeyKnown(host: String, alias: String, port: UInt16) -> Bool {
        if SSHConfigWriter.isKnownHost(host) { return true }
        if SSHConfigWriter.isKnownHost(alias) { return true }
        if port != 22, SSHConfigWriter.isKnownHost("[\(host)]:\(port)") { return true }
        return false
    }

    nonisolated private static func isHardFailure(stderr: String, hostKeyKnown: Bool) -> Bool {
        let s = stderr.lowercased()
        if !hostKeyKnown { return true }
        return s.contains("host key verification failed")
            || s.contains("permission denied")
            || s.contains("authentication failed")
            || s.contains("too many authentication")
            || s.contains("could not resolve hostname")
            || s.contains("administratively prohibited")
            || s.contains("cannot listen to port")
    }

    nonisolated private static func friendlyError(
        stderr: String,
        status: Int32,
        hostKeyKnown: Bool,
        alias: String,
        mux: Bool
    ) -> String {
        let s = stderr.lowercased()
        if !hostKeyKnown || s.contains("host key verification failed") {
            return "Host key not in known_hosts. Run `ssh \(alias)` once in Terminal, then Connect."
        }
        if s.contains("permission denied") || s.contains("authentication failed") {
            return "SSH auth failed. For OTP/captcha, run `ssh \(alias)` in Terminal first (ControlMaster), then Connect."
        }
        if s.contains("cannot listen") || s.contains("port forwarding failed") || s.contains("administratively prohibited") {
            return "Remote port busy or forwarding denied. Free the remote port or change the tunnel port, then retry."
        }
        if mux && (s.contains("no such") || s.contains("master") || s.contains("control")) {
            return "No live SSH master. Run `ssh \(alias)` in Terminal, leave ControlMaster up, then Connect."
        }
        if !stderr.isEmpty { return stderr }
        if status == 0 {
            return "SSH session ended. If this host uses ControlMaster, run `ssh \(alias)` in Terminal then Connect."
        }
        return "ssh exited (\(status))"
    }
}

// MARK: - SSH CLI (off main actor)

enum SSHCLI {
    struct Result: Sendable {
        var status: Int32
        var stderr: String
        var ok: Bool { status == 0 }
    }

    static func controlMasterRunning(alias: String) -> Bool {
        run(arguments: ["-O", "check", alias]).ok
    }

    static func muxForward(alias: String, remotePort: UInt16, localPort: UInt16) -> Result {
        run(arguments: ["-O", "forward", "-R", "\(remotePort):127.0.0.1:\(localPort)", alias])
    }

    static func muxCancel(alias: String, remotePort: UInt16, localPort: UInt16) -> Result {
        run(arguments: ["-O", "cancel", "-R", "\(remotePort):127.0.0.1:\(localPort)", alias])
    }

    private static func run(arguments: [String]) -> Result {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        task.arguments = arguments
        let err = Pipe()
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = err
        do {
            try task.run()
            task.waitUntilExit()
            let data = err.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Result(status: task.terminationStatus, stderr: text)
        } catch {
            return Result(status: -1, stderr: error.localizedDescription)
        }
    }
}
