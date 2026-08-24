import Foundation

/// One `GET /v1/stream` frame from `nerve-hub` — the whole truth, never a delta.
///
/// `jobs` is every live job the hub holds and `departed` carries the terminal
/// state of jobs evicted since the previous frame — the only signal a surface
/// gets that a job ended.
///
/// The hub publishes each job's timeline *inside* the job object, next to the
/// job's own fields. `Job` is a closed `Codable` that would drop that key
/// silently, so decoding lifts every timeline out into ``timelines``, keyed by
/// job id. Departed rows publish an empty timeline by hub contract (eviction
/// forgets it), so only live jobs contribute.
///
/// Decode-only on purpose: a surface receives frames and never sends one, and a
/// synthesised encoder would quietly drop the timelines it cannot re-nest.
///
/// Decoding is deliberately tolerant: hub and surface ship separately, so
/// unknown keys are ignored and a missing array decodes as empty rather than
/// throwing away the whole frame.
struct HubFrame: Decodable, Sendable, Equatable {
    var jobs: [Job]
    var departed: [Job]
    /// Hub-owned observation log per job id. Absent key = that job has none.
    var timelines: [String: [TimelineEntry]]

    init(
        jobs: [Job] = [],
        departed: [Job] = [],
        timelines: [String: [TimelineEntry]] = [:]
    ) {
        self.jobs = jobs
        self.departed = departed
        self.timelines = timelines
    }

    private enum CodingKeys: String, CodingKey {
        case jobs
        case departed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let live = try c.decodeIfPresent([PublishedJob].self, forKey: .jobs) ?? []
        let gone = try c.decodeIfPresent([PublishedJob].self, forKey: .departed) ?? []
        jobs = live.map(\.job)
        departed = gone.map(\.job)
        timelines = Self.timelines(from: live)
    }

    /// `GET /v1/jobs` — bare array, same rows as a connect frame's `jobs`.
    init(jobsListJSON data: Data, decoder: JSONDecoder) throws {
        let live = try decoder.decode([PublishedJob].self, from: data)
        jobs = live.map(\.job)
        departed = []
        timelines = Self.timelines(from: live)
    }

    private static func timelines(from live: [PublishedJob]) -> [String: [TimelineEntry]] {
        live.reduce(into: [:]) { result, published in
            guard !published.timeline.isEmpty else { return }
            result[published.job.id] = published.timeline
        }
    }
}

/// One job as the hub publishes it: the `Job` fields flattened alongside the
/// hub-maintained `timeline` array.
private struct PublishedJob: Decodable {
    let job: Job
    let timeline: [TimelineEntry]

    private enum CodingKeys: String, CodingKey {
        case timeline
    }

    init(from decoder: Decoder) throws {
        job = try Job(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A timeline the surface cannot read (older or newer entry shape) costs
        // one detail strip; the job itself still has to render, so an
        // unreadable timeline decodes as none rather than failing the frame.
        timeline = (try? c.decode([TimelineEntry].self, forKey: .timeline)) ?? []
    }
}
