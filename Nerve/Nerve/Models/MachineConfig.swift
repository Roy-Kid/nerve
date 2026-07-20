import Foundation

/// A machine the host tracks for **SSH reverse tunnels only**.
/// Job display uses whatever `alias` the producer reports — not this registry.
struct MachineConfig: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// SSH `Host` token (and a convenient label in Settings).
    var alias: String
    /// DNS name or IP (`HostName` in ssh config).
    var hostName: String
    var user: String
    var sshPort: UInt16
    /// Absolute path to identity file; nil uses the ssh agent / default keys.
    var identityFile: String?
    var enabled: Bool
    var autoConnect: Bool
    /// Port forwarded on the remote loopback to this host's Nerve ingest.
    var remoteIngestPort: UInt16

    init(
        id: UUID = UUID(),
        alias: String,
        hostName: String,
        user: String = NSUserName(),
        sshPort: UInt16 = 22,
        identityFile: String? = nil,
        enabled: Bool = true,
        autoConnect: Bool = true,
        remoteIngestPort: UInt16 = 17890
    ) {
        self.id = id
        self.alias = Self.sanitizeAlias(alias)
        self.hostName = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sshPort = sshPort
        self.identityFile = identityFile
        self.enabled = enabled
        self.autoConnect = autoConnect
        self.remoteIngestPort = remoteIngestPort
    }

    /// SSH Host tokens: letters, digits, `.`, `-`, `_`.
    static func sanitizeAlias(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return filtered.isEmpty ? "machine" : filtered
    }
}

/// Runtime connection status for a configured remote machine (not persisted).
enum MachineLinkState: String, Sendable, Hashable {
    case idle
    case connecting
    case connected
    case error
}

/// This Mac — labels for Settings / demo data only. Ingest jobs keep their own alias.
enum LocalMachine {
    /// Stable Bonjour name when available; otherwise process hostname short form.
    static var alias: String {
        if let local = bonjourLocalHostName, !local.isEmpty {
            return MachineConfig.sanitizeAlias(local)
        }
        let host = ProcessInfo.processInfo.hostName
        if let short = host.split(separator: ".").first.map(String.init), !short.isEmpty {
            return MachineConfig.sanitizeAlias(short)
        }
        return "local"
    }

    static var kind: String {
        #if os(macOS)
        return "darwin"
        #else
        return "unknown"
        #endif
    }

    private static var bonjourLocalHostName: String? {
        #if os(macOS)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        task.arguments = ["--get", "LocalHostName"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty == false) ? s : nil
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
