import Foundation

/// Make sure a `nerve-hub` is up, without ever owning the one that is.
///
/// Probe `/v1/health` first. Spawn only when nothing answers. A second
/// `nerve-hub serve` that loses the bind on 17890 exits as "already running",
/// so Tether and Nerve.app cannot keep two hubs even if they race.
///
/// Nerve.app does not have to be running. This plugin finds a hub binary
/// (installed app, this checkout's `target/`, cargo, Homebrew, login PATH)
/// and starts it when the plugin activates or launches.
public enum HubProcess: Sendable {
  public enum Launch: Equatable, Sendable {
    case alreadyServing
    case spawned
    case missing
    case failed(String)
  }

  private static let binaryName = "nerve-hub"
  private static let healthTimeout: TimeInterval = 1
  private static let spawnThrottle: TimeInterval = 10
  @MainActor private static var lastSpawnAt: Date?
  /// Retained so Foundation does not tear the child down while Tether is up.
  @MainActor private static var child: Process?

  /// Probe, then spawn at most once per throttle window.
  @MainActor
  public static func ensureRunning() async -> Launch {
    if await hubAnswers() {
      NerveLog.hub.info("hub already serving")
      return .alreadyServing
    }
    guard let binary = locateBinary() else {
      NerveLog.hub.error("nerve-hub binary not found")
      return .missing
    }
    let now = Date()
    if let last = lastSpawnAt, now.timeIntervalSince(last) < spawnThrottle {
      return await hubAnswers() ? .alreadyServing : .failed("hub is not answering; waiting out the restart window")
    }
    lastSpawnAt = now
    do {
      try spawn(binary)
      NerveLog.hub.info("spawned \(binary.path, privacy: .public)")
    } catch {
      NerveLog.hub.error("spawn failed: \(error.localizedDescription, privacy: .public)")
      return .failed(error.localizedDescription)
    }
    for _ in 0..<25 {
      try? await Task.sleep(for: .milliseconds(120))
      if await hubAnswers() { return .spawned }
    }
    return .failed("hub did not answer within 3s of starting")
  }

  /// The first executable `nerve-hub`. Installed Nerve.app wins when present
  /// so Tether reuses that copy; otherwise this checkout, cargo, or PATH.
  public static func locateBinary() -> URL? {
    let fileManager = FileManager.default
    for directory in searchDirectories() {
      let candidate = directory.appending(path: binaryName)
      if fileManager.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }
    return whichFromLoginShell()
  }

  public static func searchDirectories() -> [URL] {
    var directories: [URL] = []
    let home = FileManager.default.homeDirectoryForCurrentUser
    directories.append(URL(fileURLWithPath: "/Applications/Nerve.app/Contents/MacOS"))
    directories.append(home.appending(path: "Applications/Nerve.app/Contents/MacOS"))
    directories.append(contentsOf: compileTimeCheckoutDirectories())
    if let exe = Bundle.main.executableURL {
      directories.append(contentsOf: walkUpDirectories(from: exe.deletingLastPathComponent()))
    }
    directories.append(URL(fileURLWithPath: "/opt/homebrew/bin"))
    directories.append(URL(fileURLWithPath: "/usr/local/bin"))
    directories.append(home.appending(path: ".cargo/bin"))
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for segment in path.split(separator: ":") where !segment.isEmpty {
      directories.append(URL(fileURLWithPath: String(segment)))
    }
    return directories
  }

  /// This file is compiled from `nerve/surfaces/tether/…`, so a local
  /// `cargo build -p nerve-hub` is findable even when Nerve.app is not
  /// installed and Tether was launched from Finder with a bare PATH.
  public static func compileTimeCheckoutDirectories() -> [URL] {
    let file = URL(fileURLWithPath: #filePath)
    let repo = file
      .deletingLastPathComponent()  // NerveHubClient
      .deletingLastPathComponent()  // Sources
      .deletingLastPathComponent()  // tether
      .deletingLastPathComponent()  // surfaces
      .deletingLastPathComponent()  // nerve
    return [
      repo.appending(path: "target/release"),
      repo.appending(path: "target/debug"),
    ]
  }

  private static func walkUpDirectories(from start: URL) -> [URL] {
    var directories: [URL] = []
    var dir = start
    for _ in 0..<14 {
      directories.append(dir)
      directories.append(dir.appending(path: "target/release"))
      directories.append(dir.appending(path: "target/debug"))
      directories.append(dir.appending(path: "nerve/target/release"))
      directories.append(dir.appending(path: "nerve/target/debug"))
      directories.append(dir.appending(path: "Nerve.app/Contents/MacOS"))
      let parent = dir.deletingLastPathComponent()
      if parent.path == dir.path { break }
      dir = parent
    }
    return directories
  }

  /// GUI apps inherit launchd's PATH. A login zsh still knows cargo/Homebrew.
  /// Sync on purpose: `waitUntilExit` is not legal inside an async function.
  nonisolated private static func whichFromLoginShell() -> URL? {
    #if os(macOS)
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/bin/zsh")
      task.arguments = ["-lic", "command -v nerve-hub"]
      let out = Pipe()
      task.standardInput = FileHandle.nullDevice
      task.standardOutput = out
      task.standardError = FileHandle.nullDevice
      do {
        try task.run()
        task.waitUntilExit()
      } catch {
        return nil
      }
      guard task.terminationStatus == 0 else { return nil }
      let data = out.fileHandleForReading.readDataToEndOfFile()
      let text = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !text.isEmpty else { return nil }
      let url = URL(fileURLWithPath: text)
      guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
      return url
    #else
      return nil
    #endif
  }

  @MainActor
  private static func spawn(_ binary: URL) throws {
    #if os(macOS)
      let process = Process()
      process.executableURL = binary
      process.arguments = ["serve"]
      process.environment = [
        "HOME": NSHomeDirectory(),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
      ]
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      child = process
    #else
      throw CocoaError(.fileNoSuchFile)
    #endif
  }

  private static func hubAnswers() async -> Bool {
    var request = URLRequest(url: NerveEndpoint.health)
    request.httpMethod = "GET"
    request.timeoutInterval = healthTimeout
    request.cachePolicy = .reloadIgnoringLocalCacheData
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else { return false }
      return (200..<300).contains(http.statusCode)
    } catch {
      return false
    }
  }
}
