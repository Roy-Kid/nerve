import Foundation

/// Turns consecutive ``HubFrame`` values into `(previous, next)` job pairs for
/// `NotificationService.evaluate(previous:next:)`.
///
/// The hub owns all state semantics and only ships full frames, so this is the
/// single place where the surface recovers "what changed". Plain value type —
/// no actor, no clock, no I/O; it remembers nothing but the last frame's jobs.
struct FrameDiffer {
    /// Last frame's jobs keyed by ``Job/id``. Departed ids are dropped, so a
    /// re-used id later reads as a first sighting.
    private var previousJobs: [String: Job] = [:]

    init() {}

    /// Pairs for one frame: changed in-frame jobs first (frame order), then
    /// every departure (frame order).
    ///
    /// A job identical to its previous value emits nothing, which keeps
    /// heartbeat frames silent. Departures always emit — that is the only
    /// trigger left for long-success notifications and for clearing a sticky
    /// attention banner — even when the id was never seen live, because the hub
    /// can evict a job that never appeared in `jobs` (an ingest for an already
    /// ended job, or a session born and dead inside one coalesce window).
    mutating func pairs(for frame: HubFrame) -> [(previous: Job?, next: Job)] {
        var pairs: [(previous: Job?, next: Job)] = []

        for job in frame.jobs {
            let previous = previousJobs[job.id]
            if let previous, previous == job { continue }
            pairs.append((previous: previous, next: job))
        }

        for job in frame.departed {
            pairs.append((previous: previousJobs[job.id], next: job))
        }

        // Remember exactly this frame's jobs. Last id wins rather than trapping
        // on a duplicate the hub should never send.
        previousJobs = frame.jobs.reduce(into: [:]) { result, job in
            result[job.id] = job
        }

        return pairs
    }
}
