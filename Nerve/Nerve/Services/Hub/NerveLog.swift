import Foundation
import os

/// Unified Logging for the macOS surface. Filter in Console.app:
/// subsystem `app.nerve.Nerve`. Also appends to `~/Library/Logs/Nerve/nerve-macos.log`
/// because a Debug accessory app's os.Logger lines often never show up in `log show`.
enum NerveLog {
    private static let subsystem = "app.nerve.Nerve"
    static let hub = Logger(subsystem: subsystem, category: "hub")
    static let notify = Logger(subsystem: subsystem, category: "notify")
    static let tunnel = Logger(subsystem: subsystem, category: "tunnel")

    private static let fileQueue = DispatchQueue(label: "app.nerve.Nerve.log")

    static func record(_ message: String) {
        hub.info("\(message, privacy: .public)")
        fileQueue.async {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Logs/Nerve", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appending(path: "nerve-macos.log")
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
