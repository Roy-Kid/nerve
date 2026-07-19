import Foundation

/// Nerve does **not** persist subjects, timelines, or pending actions.
/// This helper only removes any leftover Application Support files from older builds.
enum Persistence {
    static func wipeLegacyDiskStoreIfPresent() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let dir = base.appendingPathComponent("Nerve", isDirectory: true)
        guard fm.fileExists(atPath: dir.path) else { return }
        try? fm.removeItem(at: dir)
    }
}
