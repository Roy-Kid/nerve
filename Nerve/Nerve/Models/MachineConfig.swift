import Foundation

/// A remote tunnel row in Settings — sourced from the user's `~/.ssh/config` Hosts.
/// Job display uses whatever `alias` the producer reports; this list is tunnels only.
struct MachineConfig: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// SSH `Host` token (`ssh <alias>`).
    var alias: String
    /// `HostName` from the user's config (display).
    var hostName: String
    var user: String
    var sshPort: UInt16
    /// Absolute path when set in the user's config (display).
    var identityFile: String?
    var enabled: Bool
    var autoConnect: Bool
    /// Port forwarded on the remote loopback to this Mac's Nerve ingest.
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

    enum CodingKeys: String, CodingKey {
        case id, alias, hostName, user, sshPort, identityFile
        case enabled, autoConnect, remoteIngestPort
        // Legacy key ignored on decode.
        case usesExistingSSHHost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        alias = try c.decode(String.self, forKey: .alias)
        hostName = try c.decode(String.self, forKey: .hostName)
        user = try c.decode(String.self, forKey: .user)
        sshPort = try c.decode(UInt16.self, forKey: .sshPort)
        identityFile = try c.decodeIfPresent(String.self, forKey: .identityFile)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        autoConnect = try c.decode(Bool.self, forKey: .autoConnect)
        remoteIngestPort = try c.decode(UInt16.self, forKey: .remoteIngestPort)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(alias, forKey: .alias)
        try c.encode(hostName, forKey: .hostName)
        try c.encode(user, forKey: .user)
        try c.encode(sshPort, forKey: .sshPort)
        try c.encodeIfPresent(identityFile, forKey: .identityFile)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(autoConnect, forKey: .autoConnect)
        try c.encode(remoteIngestPort, forKey: .remoteIngestPort)
    }

    /// SSH Host tokens: letters, digits, `.`, `-`, `_`. Empty input stays empty.
    static func sanitizeAlias(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return String(trimmed.unicodeScalars.filter { allowed.contains($0) })
    }
}

/// Runtime connection status for a tunnel (not persisted).
enum MachineLinkState: String, Sendable, Hashable {
    case idle
    case connecting
    case connected
    case error
}

/// This Mac — labels for Settings / demo data only. Ingest jobs keep their own alias.
enum LocalMachine {
    /// Stable Bonjour name when available; otherwise process hostname short form.
    /// Cached once: `scutil` is a subprocess and must not run on every SwiftUI body eval.
    static let alias: String = resolveAlias()

    static var kind: String {
        #if os(macOS)
        return "darwin"
        #else
        return "unknown"
        #endif
    }

    private static func resolveAlias() -> String {
        if let local = bonjourLocalHostName(), !local.isEmpty {
            return MachineConfig.sanitizeAlias(local)
        }
        let host = ProcessInfo.processInfo.hostName
        if let short = host.split(separator: ".").first.map(String.init), !short.isEmpty {
            return MachineConfig.sanitizeAlias(short)
        }
        return "local"
    }

    private static func bonjourLocalHostName() -> String? {
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

/// Which machine a job runs on, and how this Mac can reach it.
///
/// Jobs carry whatever `alias` their producer reported, and a producer on
/// another host reaches this hub through its RemoteForward tunnel — so a job in
/// the panel is not necessarily a job on this Mac. Asking that question first is
/// what keeps a remote workspace path from being opened locally; the same guard
/// the tmux surface applies before it matches a pane
/// (`crates/nerve-tmux-surface/src/machine.rs`) and the hub applies before it
/// trusts a pid (`crates/nerve-hub/src/state/reaper.rs`).
enum RemoteMachine {
    /// Alias of the machine a job runs on, when that is not this one.
    ///
    /// `nil` means "treat it as local": the job named no machine, or it named
    /// this one.
    static func foreignAlias(of jobAlias: String, local: String = LocalMachine.alias) -> String? {
        let alias = jobAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        if alias.isEmpty { return nil }
        return sameMachine(alias, local) ? nil : alias
    }

    /// Whether two aliases name the same machine.
    ///
    /// Compared the way they are produced: case-insensitively, over the
    /// characters an alias may contain. The hook posts the raw machine name and
    /// the hub sanitises what it fills in, so one machine can be spelled two
    /// ways on the wire.
    static func sameMachine(_ left: String, _ right: String) -> Bool {
        let l = MachineConfig.sanitizeAlias(left)
        let r = MachineConfig.sanitizeAlias(right)
        return !l.isEmpty && l.compare(r, options: .caseInsensitive) == .orderedSame
    }

    /// The ssh `Host` token that reaches `alias`, or `nil` when the user's
    /// config has no way there.
    ///
    /// The two names come from different places and often disagree in shape: a
    /// producer reports its hostname (`arrhenius1`) while the human's config
    /// spells the Host its own way (`ssh Arrhenius` → `login.hpc.arrhenius…`).
    /// Both the Host token and its `HostName` are scored, best wins, and ties
    /// go to the first entry in the file.
    static func bestHost(
        for alias: String,
        among hosts: [(alias: String, hostName: String)]
    ) -> String? {
        var best: (score: Int, host: String)?
        for host in hosts {
            let candidates = [score(host: host.alias, alias: alias),
                              score(host: host.hostName, alias: alias)]
            guard let score = candidates.compactMap({ $0 }).max() else { continue }
            if best == nil || score > best!.score {
                best = (score, host.alias)
            }
        }
        return best?.host
    }

    /// How well one host name answers to `alias`: exact (3), first label (2),
    /// shared prefix (1), unrelated (`nil`).
    static func score(host: String, alias: String) -> Int? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty || alias.isEmpty { return nil }
        if host.compare(alias, options: .caseInsensitive) == .orderedSame { return 3 }
        let label = String(host.split(separator: ".").first ?? "")
        if label.compare(alias, options: .caseInsensitive) == .orderedSame { return 2 }
        // `Arrhenius` is how a login node called `arrhenius1` is usually spelled.
        return sharesPrefix(label, alias) ? 1 : nil
    }

    /// Shortest name that may be prefix-matched, so `a` cannot stand for a
    /// whole machine.
    private static let minimumPrefix = 3

    private static func sharesPrefix(_ left: String, _ right: String) -> Bool {
        let overlap = min(left.count, right.count)
        guard overlap >= minimumPrefix else { return false }
        return left.prefix(overlap).compare(right.prefix(overlap), options: .caseInsensitive)
            == .orderedSame
    }
}
