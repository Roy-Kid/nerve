import Foundation
import Observation

/// Opens SSH reverse-forward sessions for configured remotes (`ssh -N <alias>`).
/// Status is in-memory only; machine definitions live in Settings (+ managed ssh config).
@MainActor
@Observable
final class MachineTunnelManager {
    private(set) var linkState: [UUID: MachineLinkState] = [:]
    private(set) var lastError: [UUID: String] = [:]
    private var processes: [UUID: Process] = [:]
    private var restartWork: [UUID: DispatchWorkItem] = [:]

    private weak var settings: SettingsStore?
    private var ingestPort: UInt16 = 17890

    func attach(settings: SettingsStore) {
        self.settings = settings
        self.ingestPort = settings.ingestPort
    }

    func start() {
        guard let settings else { return }
        syncConfig()
        for m in settings.machines where m.enabled && m.autoConnect {
            connect(id: m.id)
        }
    }

    func stopAll() {
        for id in processes.keys {
            disconnect(id: id, clearError: true)
        }
        restartWork.values.forEach { $0.cancel() }
        restartWork.removeAll()
    }

    func syncConfig() {
        guard let settings else { return }
        ingestPort = settings.ingestPort
        do {
            try SSHConfigWriter.sync(machines: settings.machines, localIngestPort: ingestPort)
        } catch {
            NSLog("[Nerve] SSH config sync failed: %@", "\(error)")
        }
    }

    func connect(id: UUID) {
        guard let settings, let machine = settings.machines.first(where: { $0.id == id }) else { return }
        guard machine.enabled else { return }
        disconnect(id: id, clearError: true)
        syncConfig()

        linkState[id] = .connecting
        lastError[id] = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-N",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=12",
            "-o", "ExitOnForwardFailure=yes",
            machine.alias,
        ]
        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        process.terminationHandler = { [weak self] proc in
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                self?.handleExit(id: id, status: proc.terminationStatus, stderr: errText)
            }
        }

        do {
            try process.run()
            processes[id] = process
            // RemoteForward is ready once ssh stays up past the connect window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                if self.processes[id]?.isRunning == true {
                    self.linkState[id] = .connected
                    self.lastError[id] = nil
                }
            }
        } catch {
            linkState[id] = .error
            lastError[id] = error.localizedDescription
            processes[id] = nil
        }
    }

    func disconnect(id: UUID, clearError: Bool = false) {
        restartWork[id]?.cancel()
        restartWork[id] = nil
        if let p = processes[id] {
            p.terminationHandler = nil
            if p.isRunning { p.terminate() }
        }
        processes[id] = nil
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

    func state(for id: UUID) -> MachineLinkState {
        linkState[id] ?? .idle
    }

    func error(for id: UUID) -> String? {
        lastError[id]
    }

    func isKnown(_ machine: MachineConfig) -> Bool {
        SSHConfigWriter.isKnownHost(machine.hostName) || SSHConfigWriter.isKnownHost(machine.alias)
    }

    private func handleExit(id: UUID, status: Int32, stderr: String) {
        processes[id] = nil
        let message: String
        if !stderr.isEmpty {
            message = stderr
        } else if status == 0 {
            message = "Disconnected"
        } else {
            message = "ssh exited (\(status))"
        }
        lastError[id] = message
        linkState[id] = .error

        guard let settings,
              let machine = settings.machines.first(where: { $0.id == id }),
              machine.enabled,
              machine.autoConnect
        else { return }

        let work = DispatchWorkItem { [weak self] in
            self?.connect(id: id)
        }
        restartWork[id]?.cancel()
        restartWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }
}
