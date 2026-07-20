import Foundation

/// Maintains a managed block inside `~/.ssh/config` for Nerve machines.
/// User never edits the file by hand — Settings drives this writer.
enum SSHConfigWriter {
    static let beginMarker = "# BEGIN NERVE MANAGED"
    static let endMarker = "# END NERVE MANAGED"

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
            .appendingPathComponent("config", isDirectory: false)
    }

    static var sshDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
    }

    /// Rewrite the Nerve-managed Host entries from the current machine list.
    static func sync(machines: [MachineConfig], localIngestPort: UInt16) throws {
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

    static func buildBlock(machines: [MachineConfig], localIngestPort: UInt16) -> String {
        var lines: [String] = [beginMarker, "# Written by Nerve Settings — do not edit by hand"]
        let remotes = machines.filter { $0.enabled && !$0.alias.isEmpty && !$0.hostName.isEmpty }
        if remotes.isEmpty {
            lines.append("# (no remote machines)")
        }
        for m in remotes {
            lines.append("Host \(m.alias)")
            lines.append("  HostName \(m.hostName)")
            if !m.user.isEmpty {
                lines.append("  User \(m.user)")
            }
            if m.sshPort != 22 {
                lines.append("  Port \(m.sshPort)")
            }
            if let identity = m.identityFile, !identity.isEmpty {
                lines.append("  IdentityFile \(identity)")
            }
            lines.append("  RemoteForward \(m.remoteIngestPort) 127.0.0.1:\(localIngestPort)")
            lines.append("  ExitOnForwardFailure yes")
            lines.append("  ServerAliveInterval 15")
            lines.append("  ServerAliveCountMax 3")
            // First connect records the host key without requiring a terminal prompt.
            lines.append("  StrictHostKeyChecking accept-new")
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
        // Begin without end — append fresh block after stripping broken tail.
        let prefix = String(existing[..<beginRange.lowerBound])
        return prefix + (prefix.isEmpty || prefix.hasSuffix("\n") ? "" : "\n") + trimmedBlock
    }

    /// Whether `ssh-keygen -F` knows this host (known_hosts).
    static func isKnownHost(_ hostName: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        task.arguments = ["-F", hostName]
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
