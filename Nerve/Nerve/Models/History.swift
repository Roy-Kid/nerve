import Foundation

/// Compact timeline observation kept for panel detail (not a full history product).
struct TimelineEntry: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var jobId: String
    var kind: String
    var title: String
    var timestamp: Date
}
