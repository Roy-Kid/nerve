import os

/// Unified Logging for the Tether surface. Filter in Console.app:
/// subsystem `app.nerve.tether`.
enum NerveLog {
    private static let subsystem = "app.nerve.tether"
    static let hub = Logger(subsystem: subsystem, category: "hub")
}
