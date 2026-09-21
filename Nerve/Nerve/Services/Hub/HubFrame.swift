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
    /// Who may raise an OS banner. Absent (older hub) means everyone.
    var notify: NotifyLease

    init(
        jobs: [Job] = [],
        departed: [Job] = [],
        timelines: [String: [TimelineEntry]] = [:],
        notify: NotifyLease = .legacy
    ) {
        self.jobs = jobs
        self.departed = departed
        self.timelines = timelines
        self.notify = notify
    }

    private enum CodingKeys: String, CodingKey {
        case jobs
        case departed
        case notify
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Per-job, not per-array: one unreadable row must not blank the panel.
        let live = (try? c.decode(LossyArray<PublishedJob>.self, forKey: .jobs))?.elements ?? []
        let gone = (try? c.decode(LossyArray<PublishedJob>.self, forKey: .departed))?.elements ?? []
        jobs = live.map(\.job)
        departed = gone.map(\.job)
        timelines = Self.timelines(from: live)
        notify = try c.decodeIfPresent(NotifyLease.self, forKey: .notify) ?? .legacy
    }

    /// `GET /v1/jobs` — bare array, same rows as a connect frame's `jobs`.
    init(jobsListJSON data: Data, decoder: JSONDecoder) throws {
        let live = (try? decoder.decode(LossyArray<PublishedJob>.self, from: data))?.elements ?? []
        jobs = live.map(\.job)
        departed = []
        timelines = Self.timelines(from: live)
        notify = .legacy
    }

    private static func timelines(from live: [PublishedJob]) -> [String: [TimelineEntry]] {
        live.reduce(into: [:]) { result, published in
            guard !published.timeline.isEmpty else { return }
            result[published.job.id] = published.timeline
        }
    }
}

/// Decode an array, skipping elements that fail instead of failing the frame.
private struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var parsed: [Element] = []
        while !container.isAtEnd {
            let index = container.currentIndex
            do {
                parsed.append(try container.decode(Element.self))
            } catch {
                _ = try? container.decode(JSONValue.self)
                if container.currentIndex == index {
                    break
                }
            }
        }
        elements = parsed
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

/// Who may raise an OS banner, as the hub published it.
///
/// `legacy` is what an older hub (no `notify` key) means: every surface
/// decides for itself. `single` elects one `owner` among the connected
/// surfaces so the menu bar and a Tether plugin do not both fire.
struct NotifyLease: Decodable, Sendable, Equatable {
    enum Policy: String, Decodable, Sendable, Equatable {
        case all
        case single
    }

    var policy: Policy
    var owner: String?
    var surfaces: [String]
    var watchers: Int

    /// An older hub omitted the key. Everyone may fire.
    static let legacy = NotifyLease(policy: .all, owner: nil, surfaces: [], watchers: 0)

    private enum CodingKeys: String, CodingKey {
        case policy, owner, surfaces, watchers
    }

    init(policy: Policy, owner: String?, surfaces: [String], watchers: Int) {
        self.policy = policy
        self.owner = owner
        self.surfaces = surfaces
        self.watchers = watchers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .policy)?.lowercased()
        policy = raw.flatMap(Policy.init(rawValue:)) ?? .single
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        surfaces = try c.decodeIfPresent([String].self, forKey: .surfaces) ?? []
        watchers = try c.decodeIfPresent(Int.self, forKey: .watchers) ?? 0
    }

    func mayInterrupt(surface: String) -> Bool {
        switch policy {
        case .all: return true
        case .single: return owner == surface
        }
    }
}
