//
//  FrameDifferTests.swift
//  Nerve — unit harness (NOT part of the app target)
//
//  Run with: `bash scripts/test_swift_units.sh`
//  Compiled by swiftc together with `Nerve/Nerve/Models/*.swift` and
//  `Nerve/Nerve/Services/Hub/{HubFrame,FrameDiffer}.swift` into one throwaway
//  executable. The repo has no XCTest / swift-testing target on purpose
//  (see `.claude/specs/nerve-macos-surface-01-cutover.md` → "Out of scope"),
//  so this file carries its own zero-dependency assertion harness.
//
//  ============================================================================
//  API CONTRACT (this file is the contract; spec task T2 implements it)
//  ============================================================================
//
//  `Nerve/Nerve/Services/Hub/HubFrame.swift`
//  -----------------------------------------
//      struct HubFrame: Codable, Sendable, Equatable {
//          var jobs: [Job]
//          var departed: [Job]
//
//          init(jobs: [Job] = [], departed: [Job] = [])
//          init(from decoder: Decoder) throws   // custom, tolerant
//      }
//
//  * One SSE frame from `nerve-hub` `GET /v1/stream` — full state, no deltas.
//  * `jobs`     — every live job the hub currently holds (hub-maintained
//                 `timeline` rides inside each job; the surface never appends).
//  * `departed` — TERMINAL states of jobs evicted since the previous frame.
//  * Decoding must be tolerant: unknown keys ignored, a MISSING `jobs` or
//    `departed` key decodes as `[]` (never throws, never nil). Forward
//    compatibility is a hard requirement — hub and surface ship separately.
//  * Pure value type; Foundation-only; no side effects, no networking.
//
//  `Nerve/Nerve/Services/Hub/FrameDiffer.swift`
//  --------------------------------------------
//      struct FrameDiffer {
//          init()
//          mutating func pairs(for frame: HubFrame) -> [(previous: Job?, next: Job)]
//      }
//
//  * Plain struct — NOT `@MainActor`, no networking, no clock, no I/O.
//    Holds only the previous frame as `[String: Job]` keyed by `Job.id`.
//  * Output feeds `NotificationService.evaluate(previous:next:)`
//    (`Services/NotificationService.swift:46`) unchanged — the differ is the
//    ONLY producer of those pairs after the hub cutover.
//
//  Rules (`pairs(for:)`):
//
//    (1) IN-FRAME — each job in `frame.jobs` pairs with the same id from the
//        previous frame. A job whose id is unknown (first sighting) yields
//        `(previous: nil, next: job)`.
//    (2) DEPARTED — each job in `frame.departed` yields
//        `(previous: <previous frame's job for that id>, next: <terminal state>)`.
//        This is the ONLY trigger left for `notifyLongSuccess`
//        (`NotificationService.swift:137-151`, needs `next.lifecycle == .ended`
//        + `previous?.lifecycle != .ended` + `startedAt/createdAt`) and for
//        sticky attention-banner removal (`:154-161`, needs a real
//        `previous` with `attention.level >= .suggested`). Losing this pair is
//        a SILENT regression — no crash, just missing notifications.
//        When the previous frame has NO entry for a departed id, the pair is
//        still emitted as `(previous: nil, next: <terminal state>)` — never
//        dropped. The hub cannot promise a job was ever listed in `jobs`
//        before eviction: an ingest for an already-`ended` job goes straight
//        to `departed`, and a short-lived session can be born and die inside
//        one 150 ms coalesce window. This mirrors the pre-cutover Swift truth
//        — `JobStore.evictEnded` (removed from SubjectStore.swift by the hub
//        cutover) called
//        `notificationSink?(before, ended)` unconditionally, and
//        `NotificationService.evaluate(previous:next:)` already handles a nil
//        `previous` (`:56`, `:105`, `:140`, `:154`). A nil-previous departed
//        pair simply cannot clear a sticky banner (`:154-161` needs a real
//        previous) — that is inherent, not a reason to swallow the pair.
//    (3) UNCHANGED — a job byte-identical to its previous-frame value emits NO
//        pair (matches the old `JobStore.commit` "only on write" behaviour and
//        keeps heartbeat frames silent). `Job` is `Hashable`/`Equatable`, so
//        equality is whole-value.
//    (4) ORDER — `frame.jobs` order first, then `frame.departed` order.
//        Deterministic ordering keeps banner order reproducible.
//    (5) STATE — after the call the remembered frame is exactly `frame.jobs`;
//        departed ids are forgotten, so a re-used id later reads as a first
//        sighting (`previous == nil`).
//
//  Test wire format = the hub wire format: JSON with ISO-8601 dates
//  (`JSONDecoder.dateDecodingStrategy = .iso8601`), decoded into the real
//  `Job` model from `Nerve/Nerve/Models/Subject.swift`. All fixtures below are
//  hard-coded — no network, no clock, no filesystem, no live third party.
//

import Foundation

// MARK: - Fixtures (hard-coded hub wire payloads)

/// Frames are literal `GET /v1/stream` payloads. Two job ids only:
/// `claude-code:s1` (stays live, attention escalates) and
/// `codex:s2` (runs, then departs as a long success).
private enum Fixture {
    /// j1 open and quiet — the "before" side of the A1 attention escalation.
    static let frameJ1AttentionNone = """
    {
      "jobs": [
        {
          "id": "claude-code:s1", "kind": "session", "name": "nerve", "alias": "local",
          "lifecycle": "active",
          "current": { "type": "thinking", "summary": "Planning the cutover" },
          "attention": { "level": "none" },
          "health": "ok",
          "progress": { "kind": "none" },
          "producer": { "id": "claude-code", "name": "Claude Code" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "startedAt": "2026-08-22T08:00:00Z",
          "updatedAt": "2026-08-22T08:10:00Z",
          "version": 1,
          "extensions": {}
        }
      ],
      "departed": []
    }
    """

    /// Same job id, attention escalated to `required` (permission prompt).
    static let frameJ1AttentionRequired = """
    {
      "jobs": [
        {
          "id": "claude-code:s1", "kind": "session", "name": "nerve", "alias": "local",
          "lifecycle": "active",
          "current": { "type": "tool", "summary": "Waiting for approval" },
          "attention": {
            "level": "required", "reason": "approval",
            "title": "Approval needed: nerve", "summary": "Allow Bash(swiftc)?"
          },
          "health": "ok",
          "progress": { "kind": "none" },
          "producer": { "id": "claude-code", "name": "Claude Code" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "startedAt": "2026-08-22T08:00:00Z",
          "updatedAt": "2026-08-22T08:11:00Z",
          "version": 2,
          "extensions": {}
        }
      ],
      "departed": []
    }
    """

    /// j2 alone and active — the "before" side of the A2 departed pair.
    static let frameJ2Active = """
    {
      "jobs": [
        {
          "id": "codex:s2", "kind": "session", "name": "index-page", "alias": "local",
          "lifecycle": "active",
          "current": { "type": "tool", "summary": "Running the site build" },
          "attention": { "level": "none" },
          "health": "ok",
          "progress": { "kind": "indeterminate", "label": "Building" },
          "producer": { "id": "codex", "name": "Codex" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "startedAt": "2026-08-22T08:00:00Z",
          "updatedAt": "2026-08-22T08:30:00Z",
          "version": 4,
          "extensions": {}
        }
      ],
      "departed": []
    }
    """

    /// j2 evicted: `jobs` no longer lists it, `departed` carries the terminal
    /// state. startedAt → endedAt spans 65 min, well past the 300 s
    /// `longTaskSuccessThresholdSeconds` default, so the downstream
    /// long_success gate is meaningfully exercised by A8's manual pass.
    static let frameDepartedJ2Success = """
    {
      "jobs": [],
      "departed": [
        {
          "id": "codex:s2", "kind": "session", "name": "index-page", "alias": "local",
          "lifecycle": "ended",
          "current": { "type": "info", "summary": "Site build finished" },
          "attention": { "level": "none" },
          "health": "ok",
          "outcome": "success",
          "progress": { "kind": "none" },
          "producer": { "id": "codex", "name": "Codex" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "startedAt": "2026-08-22T08:00:00Z",
          "endedAt": "2026-08-22T09:05:00Z",
          "updatedAt": "2026-08-22T09:05:00Z",
          "version": 5,
          "extensions": {}
        }
      ]
    }
    """

    /// A departed id the differ has never seen in any previous frame.
    static let frameDepartedUnknownJob = """
    {
      "jobs": [],
      "departed": [
        {
          "id": "ghost:s9", "kind": "session", "name": "ghost", "alias": "local",
          "lifecycle": "ended",
          "attention": { "level": "none" },
          "health": "ok",
          "outcome": "success",
          "progress": { "kind": "none" },
          "producer": { "id": "ghost" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "startedAt": "2026-08-22T08:00:00Z",
          "endedAt": "2026-08-22T09:05:00Z",
          "updatedAt": "2026-08-22T09:05:00Z",
          "version": 2,
          "extensions": {}
        }
      ]
    }
    """

    /// Both jobs live — setup for the mixed in-frame + departed ordering case.
    static let frameJ1NoneAndJ2Active = """
    {
      "jobs": [
        {
          "id": "claude-code:s1", "kind": "session", "name": "nerve", "alias": "local",
          "lifecycle": "active",
          "current": { "type": "thinking", "summary": "Planning the cutover" },
          "attention": { "level": "none" },
          "health": "ok",
          "progress": { "kind": "none" },
          "producer": { "id": "claude-code", "name": "Claude Code" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "startedAt": "2026-08-22T08:00:00Z",
          "updatedAt": "2026-08-22T08:10:00Z",
          "version": 1,
          "extensions": {}
        },
        {
          "id": "codex:s2", "kind": "session", "name": "index-page", "alias": "local",
          "lifecycle": "active",
          "current": { "type": "tool", "summary": "Running the site build" },
          "attention": { "level": "none" },
          "health": "ok",
          "progress": { "kind": "indeterminate", "label": "Building" },
          "producer": { "id": "codex", "name": "Codex" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "startedAt": "2026-08-22T08:00:00Z",
          "updatedAt": "2026-08-22T08:30:00Z",
          "version": 4,
          "extensions": {}
        }
      ],
      "departed": []
    }
    """

    /// j1 escalates and j2 departs in the SAME frame.
    static let frameJ1RequiredAndDepartedJ2 = """
    {
      "jobs": [
        {
          "id": "claude-code:s1", "kind": "session", "name": "nerve", "alias": "local",
          "lifecycle": "active",
          "current": { "type": "tool", "summary": "Waiting for approval" },
          "attention": {
            "level": "required", "reason": "approval",
            "title": "Approval needed: nerve", "summary": "Allow Bash(swiftc)?"
          },
          "health": "ok",
          "progress": { "kind": "none" },
          "producer": { "id": "claude-code", "name": "Claude Code" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "startedAt": "2026-08-22T08:00:00Z",
          "updatedAt": "2026-08-22T08:11:00Z",
          "version": 2,
          "extensions": {}
        }
      ],
      "departed": [
        {
          "id": "codex:s2", "kind": "session", "name": "index-page", "alias": "local",
          "lifecycle": "ended",
          "current": { "type": "info", "summary": "Site build finished" },
          "attention": { "level": "none" },
          "health": "ok",
          "outcome": "success",
          "progress": { "kind": "none" },
          "producer": { "id": "codex", "name": "Codex" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "startedAt": "2026-08-22T08:00:00Z",
          "endedAt": "2026-08-22T09:05:00Z",
          "updatedAt": "2026-08-22T09:05:00Z",
          "version": 5,
          "extensions": {}
        }
      ]
    }
    """

    // MARK: Decoding tolerance payloads (A3)

    /// Older / minimal hub build: no `departed` key at all.
    static let payloadWithoutDepartedKey = """
    {
      "jobs": [
        {
          "id": "claude-code:s1", "kind": "session", "name": "nerve", "alias": "local",
          "lifecycle": "active",
          "attention": { "level": "none" },
          "health": "ok",
          "progress": { "kind": "none" },
          "producer": { "id": "claude-code" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "updatedAt": "2026-08-22T08:10:00Z",
          "version": 1,
          "extensions": {}
        }
      ]
    }
    """

    /// Newer hub build: extra frame-level and job-level keys the surface does
    /// not know yet. Must decode, must not throw, unknown keys dropped.
    static let payloadWithUnknownKeys = """
    {
      "schema": "v2",
      "seq": 42,
      "serverTime": "2026-08-22T09:00:00Z",
      "retention": { "maxJobs": 200 },
      "jobs": [
        {
          "id": "claude-code:s1", "kind": "session", "name": "nerve", "alias": "local",
          "lifecycle": "active",
          "attention": { "level": "none" },
          "health": "ok",
          "progress": { "kind": "none" },
          "producer": { "id": "claude-code" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "updatedAt": "2026-08-22T08:10:00Z",
          "version": 1,
          "extensions": {},
          "timeline": [
            { "at": "2026-08-22T08:05:00Z", "text": "started" }
          ],
          "hubOnlyField": true
        }
      ],
      "departed": []
    }
    """

    /// A job carrying the prompt the hub kept for it, and one with a blank
    /// spelling of the same key.
    static let payloadWithPrompts = """
    {
      "jobs": [
        {
          "id": "claude-code:s1", "kind": "session", "name": "nerve", "alias": "local",
          "lifecycle": "active",
          "current": { "type": "tool", "name": "Bash", "summary": "Using Bash" },
          "attention": { "level": "none" },
          "health": "ok",
          "progress": { "kind": "none" },
          "producer": { "id": "claude-code" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "updatedAt": "2026-08-22T08:10:00Z",
          "version": 1,
          "extensions": { "lastPrompt": "  fix the sidebar preview  ", "pid": 4242 }
        },
        {
          "id": "codex:s2", "kind": "session", "name": "index", "alias": "local",
          "lifecycle": "active",
          "attention": { "level": "none" },
          "health": "ok",
          "progress": { "kind": "none" },
          "producer": { "id": "codex" },
          "capabilities": [], "actions": [],
          "createdAt": "2026-08-22T08:00:00Z",
          "updatedAt": "2026-08-22T08:10:00Z",
          "version": 1,
          "extensions": { "lastPrompt": "   " }
        }
      ]
    }
    """

    /// Idle hub: both arrays empty (the common heartbeat frame).
    static let payloadEmptyArrays = """
    { "jobs": [], "departed": [] }
    """

    /// Neither key present — an empty object is still a valid frame.
    static let payloadEmptyObject = "{}"
}

// MARK: - Decoding helper (hub wire: ISO-8601 dates)

private func decodeFrame(_ json: String) throws -> HubFrame {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(HubFrame.self, from: Data(json.utf8))
}

private func firstJob(of pairs: [(previous: Job?, next: Job)], id: String) -> (previous: Job?, next: Job)? {
    pairs.first { $0.next.id == id }
}

// MARK: - Tests: A1 — in-frame pairing

/// Escalating attention on a known job emits exactly one pair carrying both sides.
private func test_pairsEmitsOnePairForAttentionEscalation(_ t: TestRun) throws {
    var differ = FrameDiffer()
    _ = differ.pairs(for: try decodeFrame(Fixture.frameJ1AttentionNone))

    let pairs = differ.pairs(for: try decodeFrame(Fixture.frameJ1AttentionRequired))

    t.equal(pairs.count, 1, "escalation frame emits exactly one pair")
    guard let pair = pairs.first else { return }
    t.equal(pair.next.id, "claude-code:s1", "pair is for the escalating job")
    let previous = try t.unwrap(pair.previous, "escalation pair keeps the previous frame's job")
    t.equal(previous.attention.level, .none, "previous side is the pre-escalation attention")
    t.equal(pair.next.attention.level, .required, "next side is the escalated attention")
}

/// A byte-identical frame is a heartbeat: nothing to notify about.
private func test_pairsEmitsNothingForIdenticalFrames(_ t: TestRun) throws {
    var differ = FrameDiffer()
    let frame = try decodeFrame(Fixture.frameJ1AttentionNone)
    _ = differ.pairs(for: frame)

    let pairs = differ.pairs(for: frame)

    t.equal(pairs.count, 0, "unchanged frame emits no pairs")
}

/// First sighting of a job has no previous side.
private func test_pairsMarksFirstSightingWithNilPrevious(_ t: TestRun) throws {
    var differ = FrameDiffer()

    let pairs = differ.pairs(for: try decodeFrame(Fixture.frameJ1AttentionNone))

    t.equal(pairs.count, 1, "first frame emits one pair per job")
    guard let pair = pairs.first else { return }
    t.equal(pair.next.id, "claude-code:s1", "pair is for the newly seen job")
    t.check(pair.previous == nil, "first sighting has previous == nil")
}

/// An empty frame on a fresh differ is a no-op (and must not crash).
private func test_pairsEmitsNothingForEmptyFrame(_ t: TestRun) throws {
    var differ = FrameDiffer()

    let pairs = differ.pairs(for: HubFrame(jobs: []))

    t.equal(pairs.count, 0, "empty frame emits no pairs")
}

// MARK: - Tests: A2 — departed pairing

/// The departed entry must pair against the REAL previous state, otherwise
/// `notifyLongSuccess` (NotificationService.swift:137-151) and sticky-banner
/// removal (:154-161) silently stop firing after the hub cutover.
private func test_pairsEmitsDepartedPairWithRealPrevious(_ t: TestRun) throws {
    var differ = FrameDiffer()
    _ = differ.pairs(for: try decodeFrame(Fixture.frameJ2Active))

    let pairs = differ.pairs(for: try decodeFrame(Fixture.frameDepartedJ2Success))

    t.equal(pairs.count, 1, "departed frame emits exactly one pair")
    guard let pair = pairs.first else { return }
    t.equal(pair.next.id, "codex:s2", "pair is for the departed job")
    let previous = try t.unwrap(pair.previous, "departed pair MUST carry a real previous")
    t.equal(previous.lifecycle, .active, "previous side is the pre-eviction live state")
    t.equal(pair.next.lifecycle, .ended, "next side is the terminal lifecycle")
    t.equal(pair.next.outcome, .success, "next side keeps the terminal outcome")
}

/// A departed id the differ never saw still emits a pair, with `previous == nil`.
/// The hub may push a terminal state that was never listed in `jobs` (ingest for
/// an already-ended job; a session born and dead inside one coalesce window).
/// Matches `JobStore.evictEnded` (removed from SubjectStore.swift by the hub
/// cutover), which fired `notificationSink?(before, ended)` even when `before == nil`.
private func test_pairsEmitsDepartedPairWithNilPreviousWhenUnseen(_ t: TestRun) throws {
    var differ = FrameDiffer()

    let pairs = differ.pairs(for: try decodeFrame(Fixture.frameDepartedUnknownJob))

    t.equal(pairs.count, 1, "unseen departed job still emits exactly one pair")
    guard let pair = pairs.first else { return }
    t.check(pair.previous == nil, "unseen departed job has previous == nil")
    t.equal(pair.next.id, "ghost:s9", "pair is for the departed job")
    t.equal(pair.next.lifecycle, .ended, "next side is the terminal lifecycle")
    t.equal(pair.next.outcome, .success, "next side keeps the terminal outcome")
}

/// Departed ids are forgotten: a re-used id later reads as a first sighting.
private func test_pairsForgetsDepartedJobForLaterFrames(_ t: TestRun) throws {
    var differ = FrameDiffer()
    _ = differ.pairs(for: try decodeFrame(Fixture.frameJ2Active))
    _ = differ.pairs(for: try decodeFrame(Fixture.frameDepartedJ2Success))

    let pairs = differ.pairs(for: try decodeFrame(Fixture.frameJ2Active))

    t.equal(pairs.count, 1, "re-appearing id emits one pair")
    guard let pair = pairs.first else { return }
    t.check(pair.previous == nil, "departed state is not retained as previous")
}

/// Mixed frame: in-frame pairs come first, departed pairs after — deterministic
/// order keeps banner order reproducible.
private func test_pairsOrdersInFrameJobsBeforeDeparted(_ t: TestRun) throws {
    var differ = FrameDiffer()
    _ = differ.pairs(for: try decodeFrame(Fixture.frameJ1NoneAndJ2Active))

    let pairs = differ.pairs(for: try decodeFrame(Fixture.frameJ1RequiredAndDepartedJ2))

    t.equal(pairs.count, 2, "one in-frame change plus one departure")
    t.equal(pairs.first?.next.id, "claude-code:s1", "in-frame pair comes first")
    t.equal(pairs.last?.next.id, "codex:s2", "departed pair comes last")
    let escalation = try t.unwrap(firstJob(of: pairs, id: "claude-code:s1"), "in-frame pair present")
    t.equal(escalation.next.attention.level, .required, "in-frame pair carries the escalation")
    let departure = try t.unwrap(firstJob(of: pairs, id: "codex:s2"), "departed pair present")
    t.check(departure.previous != nil, "departed pair still carries a real previous")
}

// MARK: - Tests: A3 — HubFrame decoding tolerance

/// A frame without the `departed` key decodes with an empty `departed`.
private func test_decodeFrameWithoutDepartedKeyYieldsEmptyArray(_ t: TestRun) throws {
    let frame = try decodeFrame(Fixture.payloadWithoutDepartedKey)

    t.equal(frame.jobs.count, 1, "jobs decode when departed is absent")
    t.equal(frame.departed.count, 0, "missing departed key decodes as empty array")
}

/// Unknown frame-level and job-level keys are ignored, never fatal.
private func test_decodeFrameIgnoresUnknownKeys(_ t: TestRun) throws {
    let frame = try decodeFrame(Fixture.payloadWithUnknownKeys)

    t.equal(frame.jobs.count, 1, "job decodes despite unknown keys")
    t.equal(frame.jobs.first?.id, "claude-code:s1", "known fields survive unknown keys")
    t.equal(frame.departed.count, 0, "empty departed stays empty")
}

/// Empty arrays and a fully empty object both decode to an empty frame.
private func test_decodeFrameAcceptsEmptyPayloads(_ t: TestRun) throws {
    let empty = try decodeFrame(Fixture.payloadEmptyArrays)
    t.equal(empty.jobs.count, 0, "empty jobs array decodes")
    t.equal(empty.departed.count, 0, "empty departed array decodes")

    let bare = try decodeFrame(Fixture.payloadEmptyObject)
    t.equal(bare.jobs.count, 0, "missing jobs key decodes as empty array")
    t.equal(bare.departed.count, 0, "missing departed key decodes as empty array")
}

// MARK: - Tests: last prompt (panel detail)

/// The prompt the hub kept reaches the panel, trimmed.
private func test_lastPromptDecodesFromExtensions(_ t: TestRun) throws {
    let frame = try decodeFrame(Fixture.payloadWithPrompts)
    let job = try t.unwrap(frame.jobs.first { $0.id == "claude-code:s1" }, "prompt job decodes")

    t.equal(job.lastPrompt, "fix the sidebar preview", "prompt is exposed, trimmed")
    // The row still says what the agent is doing now — the two are different facts.
    t.equal(job.current?.summary, "Using Bash", "current activity is untouched by the prompt")
}

/// A blank prompt is no prompt: the panel must not paint an empty block.
private func test_blankOrAbsentPromptIsNil(_ t: TestRun) throws {
    let frame = try decodeFrame(Fixture.payloadWithPrompts)
    let blank = try t.unwrap(frame.jobs.first { $0.id == "codex:s2" }, "blank-prompt job decodes")
    t.check(blank.lastPrompt == nil, "whitespace-only prompt reads as no prompt")

    let plain = try decodeFrame(Fixture.payloadWithoutDepartedKey)
    t.check(plain.jobs.first?.lastPrompt == nil, "a job that never reported one has no prompt")
}

// MARK: - Tests: which machine a job runs on

/// A job's machine is a name comparison, and only that.
private func test_foreignAliasIsNameComparisonOnly(_ t: TestRun) throws {
    let mac = "RoydeMacBook-Air"
    t.check(RemoteMachine.foreignAlias(of: "arrhenius1", local: mac) == "arrhenius1",
            "another machine keeps its own name")
    t.check(RemoteMachine.foreignAlias(of: " roydemacbook-air ", local: mac) == nil,
            "this machine, spelled differently, is still this machine")
    t.check(RemoteMachine.foreignAlias(of: "", local: mac) == nil,
            "a job that named no machine is never foreign")
}

/// The ssh Host that reaches a machine, scored best-first.
private func test_bestHostPrefersTheClosestName(_ t: TestRun) throws {
    let hosts = [
        (alias: "dardel", hostName: "dardel.pdc.kth.se"),
        (alias: "Arrhenius", hostName: "login.hpc.arrhenius.naiss.se"),
        (alias: "hpc", hostName: "arrhenius1.hpc.example"),
    ]
    // `HostName arrhenius1…` names the machine outright; `Host Arrhenius` only
    // shares a prefix with it.
    t.equal(RemoteMachine.bestHost(for: "arrhenius1", among: hosts), "hpc",
            "the config entry that names the machine wins")
    t.equal(RemoteMachine.bestHost(for: "dardel", among: hosts), "dardel",
            "an exact Host token matches")
    t.check(RemoteMachine.bestHost(for: "beskow", among: hosts) == nil,
            "a machine the config cannot reach has no host")
}

/// Scoring is exact > first label > shared prefix, and never a coincidence.
private func test_hostScoreRanksExactAboveLabelAbovePrefix(_ t: TestRun) throws {
    t.check(RemoteMachine.score(host: "arrhenius1", alias: "arrhenius1") == 3, "exact name")
    t.check(RemoteMachine.score(host: "arrhenius1.uu.se", alias: "arrhenius1") == 2, "first label")
    t.check(RemoteMachine.score(host: "Arrhenius", alias: "arrhenius1") == 1, "shared prefix")
    t.check(RemoteMachine.score(host: "a", alias: "arrhenius1") == nil, "one letter is not a machine")
    t.check(RemoteMachine.score(host: "dardel", alias: "arrhenius1") == nil, "unrelated hosts")
}

/// The panel button says where it goes when that is not this Mac.
private func test_openTitleNamesTheOtherMachine(_ t: TestRun) throws {
    var remote = Job.make(
        id: "claude-code:s1",
        name: "molcrafts",
        alias: "arrhenius1",
        producer: ProducerInfo(id: "claude-code")
    )
    remote.location = LocationInfo(openURL: "file:///nobackup/proj/molcrafts")
    t.equal(ActionService.focusActionTitle(for: remote), "Open on arrhenius1",
            "a job elsewhere is not labelled `Open`")

    var here = Job.make(
        id: "claude-code:s2",
        name: "nerve",
        alias: LocalMachine.alias,
        producer: ProducerInfo(id: "claude-code")
    )
    here.location = LocationInfo(openURL: "file:///Users/me/nerve")
    t.equal(ActionService.focusActionTitle(for: here), "Open", "a local workspace still opens")
}

// MARK: - Minimal assertion harness (no XCTest / swift-testing in this repo)

private struct TestAbort: Error {
    let reason: String
}

private final class TestRun {
    private(set) var failures: [String] = []
    private var currentTest = "<none>"

    func begin(_ name: String) {
        currentTest = name
    }

    func check(_ ok: Bool, _ what: String, line: UInt = #line) {
        if !ok {
            record("\(what) — line \(line)")
        }
    }

    func equal<T: Equatable>(_ actual: T, _ expected: T, _ what: String, line: UInt = #line) {
        if actual != expected {
            record("\(what) — expected \(expected), got \(actual) — line \(line)")
        }
    }

    /// Records a failure and aborts the current test when the value is nil.
    func unwrap<T>(_ value: T?, _ what: String, line: UInt = #line) throws -> T {
        guard let value else {
            record("\(what) — expected non-nil — line \(line)")
            throw TestAbort(reason: what)
        }
        return value
    }

    func record(_ message: String) {
        failures.append("\(currentTest): \(message)")
    }
}

@main
enum FrameDifferTestMain {
    private static let tests: [(name: String, body: (TestRun) throws -> Void)] = [
        // A1 — in-frame pairing
        ("test_pairsEmitsOnePairForAttentionEscalation", test_pairsEmitsOnePairForAttentionEscalation),
        ("test_pairsEmitsNothingForIdenticalFrames", test_pairsEmitsNothingForIdenticalFrames),
        ("test_pairsMarksFirstSightingWithNilPrevious", test_pairsMarksFirstSightingWithNilPrevious),
        ("test_pairsEmitsNothingForEmptyFrame", test_pairsEmitsNothingForEmptyFrame),
        // A2 — departed pairing
        ("test_pairsEmitsDepartedPairWithRealPrevious", test_pairsEmitsDepartedPairWithRealPrevious),
        ("test_pairsEmitsDepartedPairWithNilPreviousWhenUnseen", test_pairsEmitsDepartedPairWithNilPreviousWhenUnseen),
        ("test_pairsForgetsDepartedJobForLaterFrames", test_pairsForgetsDepartedJobForLaterFrames),
        ("test_pairsOrdersInFrameJobsBeforeDeparted", test_pairsOrdersInFrameJobsBeforeDeparted),
        // A3 — HubFrame decoding tolerance
        ("test_decodeFrameWithoutDepartedKeyYieldsEmptyArray", test_decodeFrameWithoutDepartedKeyYieldsEmptyArray),
        ("test_decodeFrameIgnoresUnknownKeys", test_decodeFrameIgnoresUnknownKeys),
        ("test_decodeFrameAcceptsEmptyPayloads", test_decodeFrameAcceptsEmptyPayloads),
        // Panel detail — what the human asked
        ("test_lastPromptDecodesFromExtensions", test_lastPromptDecodesFromExtensions),
        ("test_blankOrAbsentPromptIsNil", test_blankOrAbsentPromptIsNil),
        // Machines — a job in the panel is not always a job on this Mac
        ("test_foreignAliasIsNameComparisonOnly", test_foreignAliasIsNameComparisonOnly),
        ("test_bestHostPrefersTheClosestName", test_bestHostPrefersTheClosestName),
        ("test_hostScoreRanksExactAboveLabelAbovePrefix", test_hostScoreRanksExactAboveLabelAbovePrefix),
        ("test_openTitleNamesTheOtherMachine", test_openTitleNamesTheOtherMachine),
    ]

    static func main() {
        let run = TestRun()
        var failedTests = 0

        print("FrameDiffer / HubFrame unit harness — \(tests.count) tests")
        for test in tests {
            let before = run.failures.count
            run.begin(test.name)
            do {
                try test.body(run)
            } catch is TestAbort {
                // `unwrap` already recorded the failure; stop this test only.
            } catch {
                run.record("unexpected error: \(error)")
            }
            let failedHere = run.failures.count - before
            if failedHere == 0 {
                print("  PASS  \(test.name)")
            } else {
                failedTests += 1
                print("  FAIL  \(test.name)")
            }
        }

        if run.failures.isEmpty {
            print("OK — \(tests.count) tests passed")
            exit(0)
        }

        print("")
        print("Failures (\(run.failures.count) in \(failedTests) test(s)):")
        for failure in run.failures {
            print("  - \(failure)")
        }
        print("")
        print("FAILED — \(failedTests)/\(tests.count) tests")
        exit(1)
    }
}
