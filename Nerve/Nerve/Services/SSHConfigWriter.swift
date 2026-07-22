import Foundation

/// A concrete Host entry from the user's `~/.ssh/config` (excluding the Nerve-managed block).
struct LocalSSHHost: Identifiable, Hashable, Sendable {
    var id: String { alias }
    /// SSH `Host` token (`ssh Arrhenius`).
    var alias: String
    /// `HostName` when set; otherwise the alias.
    var hostName: String
    var user: String
    var port: UInt16
    var identityFile: String?

    func asMachineConfig(
        remoteIngestPort: UInt16 = 17890,
        enabled: Bool = false,
        autoConnect: Bool = false
    ) -> MachineConfig {
        MachineConfig(
            alias: alias,
            hostName: hostName,
            user: user.isEmpty ? NSUserName() : user,
            sshPort: port,
            identityFile: identityFile,
            enabled: enabled,
            autoConnect: autoConnect,
            remoteIngestPort: remoteIngestPort
        )
    }
}

/// Reads the user's SSH Hosts / known_hosts and writes a managed RemoteForward-only block.
///
/// Connection details (HostName, keys, ProxyJump, ControlMaster) stay in the user's config.
/// Nerve only injects reverse-forward lines for enabled tunnels.
enum SSHConfigWriter {
    static let beginMarker = "# BEGIN NERVE MANAGED"
    static let endMarker = "# END NERVE MANAGED"

    private static let ioQueue = DispatchQueue(label: "app.nerve.ssh-config", qos: .userInitiated)

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
            .appendingPathComponent("config", isDirectory: false)
    }

    static var sshDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
    }

    // MARK: - Write managed tunnel block

    static func sync(machines: [MachineConfig], localIngestPort: UInt16) throws {
        try ioQueue.sync {
            try FileManager.default.createDirectory(
                at: sshDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            let block = buildBlock(machines: machines, localIngestPort: localIngestPort)
            let url = configURL
            let existing: String
            if FileManager.default.fileExists(atPath: url.path) {
                existing = try String(contentsOf: url, encoding: .utf8)
            } else {
                existing = ""
            }
            let merged = replaceManagedBlock(in: existing, with: block)
            try merged.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
    }

    /// Managed block is tunnel-only: `RemoteForward` + `ExitOnForwardFailure` per enabled Host.
    static func buildBlock(machines: [MachineConfig], localIngestPort: UInt16) -> String {
        var lines: [String] = [beginMarker, "# Written by Nerve — RemoteForward only; do not edit by hand"]
        let remotes = machines.filter { $0.enabled && !$0.alias.isEmpty }
        if remotes.isEmpty {
            lines.append("# (no enabled tunnels)")
        }
        for m in remotes {
            lines.append("Host \(m.alias)")
            lines.append("  # tunnel only — HostName/keys/ControlMaster come from your config above")
            lines.append("  RemoteForward \(m.remoteIngestPort) 127.0.0.1:\(localIngestPort)")
            lines.append("  ExitOnForwardFailure yes")
            lines.append("")
        }
        lines.append(endMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    static func replaceManagedBlock(in existing: String, with block: String) -> String {
        let trimmedBlock = block.trimmingCharacters(in: .newlines) + "\n"
        guard let beginRange = existing.range(of: beginMarker) else {
            if existing.isEmpty { return trimmedBlock }
            let sep = existing.hasSuffix("\n") ? "\n" : "\n\n"
            return existing + sep + trimmedBlock
        }
        if let endRange = existing.range(of: endMarker), endRange.lowerBound > beginRange.lowerBound {
            let afterEnd = existing[endRange.upperBound...]
            let prefix = existing[..<beginRange.lowerBound]
            var out = String(prefix)
            if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
            out += trimmedBlock
            let rest = afterEnd.drop(while: { $0 == "\n" || $0 == "\r" })
            if !rest.isEmpty {
                out += "\n"
                out += rest
            }
            return out
        }
        let prefix = String(existing[..<beginRange.lowerBound])
        return prefix + (prefix.isEmpty || prefix.hasSuffix("\n") ? "" : "\n") + trimmedBlock
    }

    // MARK: - Read local Host entries

    /// Concrete Host aliases from `~/.ssh/config` (and simple non-glob `Include` files).
    static func loadLocalHosts() -> [LocalSSHHost] {
        ioQueue.sync {
            loadLocalHostsUnlocked(from: configURL, depth: 0)
        }
    }

    private static func loadLocalHostsUnlocked(from url: URL, depth: Int) -> [LocalSSHHost] {
        guard depth < 8 else { return [] }
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }

        let withoutManaged = stripManagedBlock(text)
        var hosts: [LocalSSHHost] = []
        var seenAliases = Set<String>()
        var currentAliases: [String] = []
        var hostName: String?
        var user: String?
        var port: UInt16 = 22
        var identity: String?

        func flush() {
            for alias in currentAliases {
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !seenAliases.contains(trimmed) else { continue }
                if trimmed.contains(where: { $0 == "*" || $0 == "?" }) { continue }
                seenAliases.insert(trimmed)
                let hn = (hostName?.isEmpty == false) ? hostName! : trimmed
                hosts.append(
                    LocalSSHHost(
                        alias: trimmed,
                        hostName: hn,
                        user: user ?? "",
                        port: port,
                        identityFile: identity
                    )
                )
            }
            currentAliases = []
            hostName = nil
            user = nil
            port = 22
            identity = nil
        }

        for rawLine in withoutManaged.components(separatedBy: .newlines) {
            let line = stripSSHComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let head = parts.first.map(String.init) else { continue }
            let keyword = head.lowercased()
            let rest = parts.dropFirst().map(String.init)

            if keyword == "host" {
                flush()
                currentAliases = rest
                continue
            }
            if keyword == "match" {
                flush()
                continue
            }
            if keyword == "include" {
                for pathToken in rest {
                    let expanded = expandSSHPath(pathToken)
                    if expanded.contains("*") || expanded.contains("?") { continue }
                    let nested = loadLocalHostsUnlocked(from: URL(fileURLWithPath: expanded), depth: depth + 1)
                    for h in nested where !seenAliases.contains(h.alias) {
                        seenAliases.insert(h.alias)
                        hosts.append(h)
                    }
                }
                continue
            }

            guard !currentAliases.isEmpty else { continue }
            let value = rest.joined(separator: " ")
            switch keyword {
            case "hostname": hostName = value
            case "user": user = value
            case "port": if let p = UInt16(value) { port = p }
            case "identityfile": if identity == nil { identity = expandSSHPath(value) }
            default: break
            }
        }
        flush()
        return hosts.sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending }
    }

    private static func stripManagedBlock(_ text: String) -> String {
        guard let begin = text.range(of: beginMarker),
              let end = text.range(of: endMarker),
              end.lowerBound > begin.lowerBound
        else { return text }
        var out = String(text[..<begin.lowerBound])
        let after = text[end.upperBound...].drop(while: { $0 == "\n" || $0 == "\r" })
        out += after
        return out
    }

    private static func stripSSHComment(_ line: String) -> String {
        if let idx = line.firstIndex(of: "#") {
            return String(line[..<idx])
        }
        return line
    }

    private static func expandSSHPath(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        if s.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(s.dropFirst(2))).path
        }
        if s == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return s
    }

    // MARK: - known_hosts

    /// `ssh-keygen -F` probe. Avoid the main thread during view updates.
    static func isKnownHost(_ hostName: String) -> Bool {
        guard !hostName.isEmpty else { return false }
        return keygenKnows(hostName)
    }

    static func isKnown(_ machine: MachineConfig) -> Bool {
        if !machine.hostName.isEmpty, isKnownHost(machine.hostName) { return true }
        if !machine.alias.isEmpty, isKnownHost(machine.alias) { return true }
        if machine.sshPort != 22, !machine.hostName.isEmpty {
            return keygenKnows("[\(machine.hostName)]:\(machine.sshPort)")
        }
        return false
    }

    private static func keygenKnows(_ host: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        task.arguments = ["-F", host]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
