import Foundation

enum PanelGroup: String, CaseIterable, Identifiable {
    case attention
    case active
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: return "Attention"
        case .active: return "Active"
        case .recent: return "Recent"
        }
    }
}

@Observable
final class JobStore {
    private(set) var jobs: [String: Job] = [:]
    private(set) var timelines: [String: [TimelineEntry]] = [:]
    private(set) var pendingActions: [PendingActionRequest] = []

    private var seenEventIds: Set<String> = []
    private var seenEventOrder: [String] = []
    private let maxSeenEvents = 4_000
    private let maxTimelinePerJob = 40
    private let maxPendingActions = 200

    private let clock: () -> Date
    private var suppressRibbonInvalidation = false
    private var pendingRibbonInvalidation = false

    var panelOpen: Bool = false
    var selectedJobId: String?
    var lastError: String?
    /// Accessibility: focused row in status list (keyboard)
    var focusedListIndex: Int = 0
    /// Bumps on every subject mutation so the menu-bar ribbon can redraw immediately.
    private(set) var revision: UInt64 = 0

    /// Set by AppModel after construction.
    var notificationSink: ((Job?, Job) -> Void)?
    /// Fired after any state change that should refresh the ribbon.
    var ribbonInvalidationSink: (() -> Void)?
    var settingsProvider: (() -> SettingsStore)?

    /// In-memory only. Subjects/timelines/pending actions are never written to disk.
    init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
        Persistence.wipeLegacyDiskStoreIfPresent()
    }

    // MARK: - Queries

    /// Public job list (API + debug). Conversation jobs only — no legacy children.
    var allJobs: [Job] { conversationJobs }

    var activeJobs: [Job] {
        conversationJobs
            .filter { $0.lifecycle != .ended }
            .sorted(by: sortComparator)
    }

    /// Open conversation jobs only (legacy subagent child rows excluded).
    var activeCount: Int { activeJobs.count }

    /// All stored conversation-level jobs (excludes legacy child/subagent rows).
    private var conversationJobs: [Job] {
        jobs.values.filter(\.isConversationJob)
    }

    // MARK: Status counts (single source of truth = `Job.status`)

    /// Open jobs with `status == .running`. Same number the ribbon/panel paint blue.
    var runningCount: Int {
        countOpen(where: { $0.status == .running })
    }

    /// Open jobs with `status == .attention`. Same number painted orange.
    var attentionCount: Int {
        countOpen(where: { $0.status == .attention })
    }

    private func countOpen(where pred: (Job) -> Bool) -> Int {
        conversationJobs.reduce(into: 0) { n, job in
            if job.lifecycle != .ended, pred(job) { n += 1 }
        }
    }

    /// Priority-mode bucket for a status (Attention / Active / Recent). View grouping only.
    /// Open Success (monitor waiting for feedback) stays Active — Recent is unused
    /// because SessionEnd removes the row immediately.
    private func priorityGroup(for status: Status) -> PanelGroup {
        switch status {
        case .problem, .attention, .waiting: return .attention
        case .running, .inactive, .success: return .active
        }
    }

    var knownProducers: [ProducerInfo] {
        var map: [String: ProducerInfo] = [:]
        for s in jobs.values { map[s.producer.id] = s.producer }
        return map.values.sorted { ($0.name ?? $0.id) < ($1.name ?? $1.id) }
    }

    var knownProjects: [String] {
        var set = Set<String>()
        for s in jobs.values {
            if let p = s.context?.project { set.insert(p) }
            if let w = s.context?.workspace { set.insert(w) }
        }
        return set.sorted()
    }

    /// Flat list for keyboard navigation under the default priority grouping.
    var flatStatusJobs: [Job] {
        flatStatusJobs(mode: .machine)
    }

    /// Flat list for keyboard navigation under a chosen grouping mode.
    func flatStatusJobs(mode: PanelGroupMode) -> [Job] {
        statusSections(mode: mode).flatMap(\.jobs)
    }

    /// Sections for the status panel. Empty sections are omitted.
    /// Grouping changes section headers only; within each section, jobs
    /// use the default sort (attention → health → outcome → recency).
    func statusSections(mode: PanelGroupMode) -> [StatusSection] {
        switch mode {
        case .priority:
            return PanelGroup.allCases.compactMap { group in
                let items = jobsInPriorityGroup(group)
                guard !items.isEmpty else { return nil }
                return StatusSection(id: group.id, title: group.title, jobs: items)
            }
        case .status:
            return statusGroupedSections()
        case .machine:
            return machineGroupedSections()
        }
    }

    func openPendingActions(forProducer producerId: String?) -> [PendingActionRequest] {
        let now = clock()
        return pendingActions.filter { req in
            guard req.state == .pending else { return false }
            if let exp = req.expiresAt, exp < now { return false }
            if let producerId { return req.producerId == producerId }
            return true
        }
    }

    /// Priority sections — bucketed only by `Job.status` (no second ruleset).
    func jobsInPriorityGroup(_ group: PanelGroup) -> [Job] {
        switch group {
        case .attention, .active:
            return conversationJobs
                .filter { $0.lifecycle != .ended && priorityGroup(for: $0.status) == group }
                .sorted(by: sortComparator)
        case .recent:
            // Session close removes the job immediately — no Recent linger.
            return []
        }
    }

    /// Open conversation jobs eligible for the status list (no legacy child rows).
    private func panelListJobs() -> [Job] {
        conversationJobs.filter { $0.lifecycle != .ended }
    }

    private func statusGroupedSections() -> [StatusSection] {
        let list = panelListJobs()
        var buckets: [Status: [Job]] = [:]
        for job in list {
            buckets[job.status, default: []].append(job)
        }
        return Status.allCases.compactMap { status in
            guard var items = buckets[status], !items.isEmpty else { return nil }
            items.sort(by: sortComparator)
            return StatusSection(id: "status:\(status.rawValue)", title: status.title, jobs: items)
        }
    }

    private func machineGroupedSections() -> [StatusSection] {
        let list = panelListJobs()
        var buckets: [String: [Job]] = [:]
        for s in list {
            let key = s.alias.trimmingCharacters(in: .whitespacesAndNewlines)
            buckets[key.isEmpty ? "unknown" : key, default: []].append(s)
        }
        return buckets
            .map { key, items in
                var sorted = items
                sorted.sort(by: sortComparator)
                return StatusSection(id: "machine:\(key)", title: key, jobs: sorted)
            }
            .sorted { a, b in
                a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    func job(id: String) -> Job? { jobs[id] }

    func timeline(for jobId: String) -> [TimelineEntry] {
        (timelines[jobId] ?? []).sorted { $0.timestamp > $1.timestamp }
    }


    private func sortComparator(_ a: Job, _ b: Job) -> Bool {
        if a.attention.level != b.attention.level {
            return a.attention.level > b.attention.level
        }
        if a.health.severity != b.health.severity {
            return a.health.severity > b.health.severity
        }
        let aFail = a.outcome == .failure
        let bFail = b.outcome == .failure
        if aFail != bFail { return aFail && !bFail }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return (a.startedAt ?? a.createdAt) > (b.startedAt ?? b.createdAt)
    }

    // MARK: - Ribbon segments

    /// One colored band on the menu-bar ribbon.
    /// `status` is the color key (worst / dominant status of the bucket).
    struct RibbonSegment: Identifiable, Equatable {
        var id: String
        var status: Status
        var count: Int
        var weight: CGFloat
    }

    /// Subjects that paint the ribbon colors — open work only.
    /// Ended sessions leave on `SessionEnd` and do not paint Success/Problem wedges.
    func ribbonColorJobs() -> [Job] {
        activeJobs
    }

    /// Ribbon layout follows the status-panel grouping mode.
    /// Subjects keep the same left→right order as the panel list under that mode;
    /// adjacent same-status subjects merge into one color band so switching
    /// Priority / Status / Source visibly reorders the continuous light strip.
    func ribbonSegments(mode: PanelGroupMode? = nil) -> [RibbonSegment] {
        let resolved = mode ?? settingsProvider?().panelGroupMode ?? .machine
        let paintIds = Set(ribbonColorJobs().map(\.id))
        guard !paintIds.isEmpty else { return [] }

        // Panel order under the active grouping — this is what the user just switched.
        var ordered: [Job] = flatStatusJobs(mode: resolved).filter { paintIds.contains($0.id) }

        if ordered.count < paintIds.count {
            let seen = Set(ordered.map(\.id))
            for s in ribbonColorJobs() where !seen.contains(s.id) {
                ordered.append(s)
            }
        }
        guard !ordered.isEmpty else { return [] }

        // Merge adjacent same-status runs so the band stays continuous, not speckled.
        var runs: [(status: Status, count: Int)] = []
        for s in ordered {
            let status = s.status
            if let last = runs.last, last.status == status {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((status, 1))
            }
        }

        return weightedStatusRuns(runs, mode: resolved)
    }

    /// Proportional widths with minimum wedges for high-priority / success colors.
    private func weightedStatusRuns(
        _ runs: [(status: Status, count: Int)],
        mode: PanelGroupMode
    ) -> [RibbonSegment] {
        guard !runs.isEmpty else { return [] }

        let total = max(1, CGFloat(runs.reduce(0) { $0 + $1.count }))
        let minHigh: CGFloat = 0.12
        let minSuccess: CGFloat = 0.10

        var weights: [CGFloat] = Array(repeating: 0, count: runs.count)
        var reserved: CGFloat = 0
        var freeCount: CGFloat = 0

        for (i, run) in runs.enumerated() {
            let c = CGFloat(run.count)
            if run.status.isHighPriority {
                let w = max(c / total, minHigh)
                weights[i] = w
                reserved += w
            } else if run.status == .success {
                let w = max(c / total, minSuccess)
                weights[i] = w
                reserved += w
            } else {
                freeCount += c
                weights[i] = -1
            }
        }

        let freeBudget = max(0.0001, 1 - reserved)
        for i in weights.indices where weights[i] < 0 {
            let c = CGFloat(runs[i].count)
            weights[i] = freeCount > 0 ? (c / freeCount) * freeBudget : 0
        }

        let sum = weights.reduce(0, +)
        return runs.enumerated().map { index, run in
            RibbonSegment(
                id: "\(mode.rawValue):\(index):\(run.status.rawValue)",
                status: run.status,
                count: run.count,
                weight: sum > 0 ? weights[index] / sum : 0
            )
        }
    }

    /// Maps active count → 0...1 with clear steps at low N (1/2/3/5/8/12+).
    /// 0…1 scale for menu-bar ribbon length (piecewise; user length scale applied in renderer).
    func ribbonLengthFactor() -> CGFloat {
        let n = activeCount
        if n <= 0 { return 0 }
        // Piecewise so 1→2→5 feels obvious; high N still compresses.
        switch n {
        case 1: return 0.18
        case 2: return 0.32
        case 3: return 0.44
        case 4: return 0.54
        case 5: return 0.62
        case 6, 7: return 0.72
        case 8, 9: return 0.82
        case 10, 11, 12: return 0.90
        default:
            let extra = min(1.0, CGFloat(n - 12) / 20.0)
            return min(1.0, 0.90 + 0.10 * extra)
        }
    }

    /// Visual signature of the ribbon (segments / counts / weights) for change detection.
    /// Intentionally excludes `revision` so tool churn that does not change ribbon
    /// colors or length does not force a redraw / animation restart.
    func ribbonSignature(mode: PanelGroupMode? = nil) -> String {
        let resolved = mode ?? settingsProvider?().panelGroupMode ?? .machine
        let segs = ribbonSegments(mode: resolved)
        let body = segs.map {
            "\($0.status.rawValue):\($0.count):\(String(format: "%.3f", Double($0.weight)))"
        }.joined(separator: ",")
        return "n=\(activeCount)|g=\(resolved.rawValue)|\(body)"
    }

    // MARK: - Ingest

    @discardableResult
    func apply(envelope: IngestEnvelope) -> Int {
        beginRibbonBatch()
        defer { endRibbonBatch() }
        var applied = 0
        let envelopeAlias = envelope.alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let list = envelope.jobs {
            for var job in list {
                if job.alias.isEmpty, let envelopeAlias, !envelopeAlias.isEmpty {
                    job.alias = envelopeAlias
                }
                if job.alias.isEmpty {
                    job.alias = LocalMachine.alias
                }
                applySnapshot(job)
                applied += 1
            }
        }
        if let events = envelope.events {
            for e in events {
                if apply(event: e) { applied += 1 }
            }
        }
        return applied
    }

    @discardableResult
    func apply(event: NerveEvent) -> Bool {
        if seenEventIds.contains(event.id) {
            return false
        }
        rememberEventId(event.id)

        if event.kind == .snapshot, let full = event.job {
            applySnapshot(full)
            appendTimeline(
                jobId: full.id,
                kind: event.kind.rawValue,
                title: "Snapshot",
                at: event.timestamp
            )
            return true
        }

        if let full = event.job, event.kind == .jobCreated || jobs[event.jobId] == nil {
            applySnapshot(full)
            appendTimeline(
                jobId: full.id,
                kind: event.kind.rawValue,
                title: "Created",
                at: event.timestamp
            )
            return true
        }

        guard var existing = jobs[event.jobId] else {
            if event.kind == .jobCreated || event.name != nil {
                let src = ProducerInfo(id: event.producerId)
                var s = Job.make(
                    id: event.jobId,
                    kind: event.jobKind ?? "session",
                    name: event.name ?? event.jobId,
                    alias: event.alias ?? LocalMachine.alias,
                    producer: src,
                    lifecycle: event.lifecycle ?? .active,
                    now: event.timestamp
                )
                let before: Job? = nil
                applyPatch(event, to: &s)
                if s.lifecycle == .ended {
                    // Never insert a closed session into the panel.
                    evictEnded(before: before, ended: s)
                    return true
                }
                commit(before: before, next: s)
                appendTimeline(
                    jobId: s.id,
                    kind: event.kind.rawValue,
                    title: timelineTitle(for: event),
                    at: event.timestamp
                )
                return true
            }
            return false
        }

        if let v = event.version, v < existing.version {
            return false
        }

        let before = existing
        applyPatch(event, to: &existing)
        if let v = event.version {
            existing.version = max(existing.version, v)
        } else {
            existing.version += 1
        }
        existing.updatedAt = max(existing.updatedAt, event.timestamp)
        if existing.lifecycle == .ended {
            // Same policy as full snapshot: notify outcome, then leave the panel.
            evictEnded(before: before, ended: existing)
            return true
        }

        commit(before: before, next: existing)
        appendTimeline(
            jobId: existing.id,
            kind: event.kind.rawValue,
            title: timelineTitle(for: event),
            at: event.timestamp
        )
        return true
    }

    func applySnapshot(_ job: Job) {
        // Legacy per-subagent rows are not conversation jobs — drop and ignore.
        if !job.isConversationJob {
            dropLegacyChild(job.id)
            return
        }
        let before = jobs[job.id]
        if let existing = before, job.version < existing.version {
            return
        }
        if job.lifecycle == .ended {
            var ended = job
            // Preserve duration anchors for long-success notifications.
            if let before {
                ended.createdAt = before.createdAt
                ended.startedAt = before.startedAt ?? before.createdAt
            }
            if ended.endedAt == nil {
                ended.endedAt = clock()
            }
            evictEnded(before: before, ended: ended)
            return
        }
        commit(before: before, next: job)
        // Parent updates also scrub any leftover child rows for this session.
        if purgeLegacyChildren(of: job.id) {
            bumpRevision()
        }
    }

    /// Ensure Copy + Dismiss exist on every open conversation row (demo / older hooks).
    private func ensureLocalActions(_ job: Job) -> Job {
        guard job.isConversationJob, job.lifecycle != .ended else { return job }
        var j = job
        if !j.actions.contains(where: { $0.kind.lowercased() == "copy_summary" || $0.kind.lowercased() == "copy" }) {
            j.actions.insert(
                JobAction(id: "copy", title: "Copy", kind: "copy_summary"),
                at: 0
            )
        }
        if !j.actions.contains(where: {
            let k = $0.kind.lowercased()
            return k == "dismiss" || k == "dismiss_job" || k == "dismissjob"
        }) {
            j.actions.append(
                JobAction(id: "dismiss", title: "Dismiss", kind: "dismiss")
            )
        }
        return j
    }

    /// User or local policy closes a row (Dismiss button, dead PID, …).
    @MainActor
    func endJobLocally(
        id: String,
        reason: String,
        summary: String? = nil,
        outcome: Outcome = .cancelled
    ) {
        guard var job = jobs[id], job.lifecycle != .ended else { return }
        let before = job
        let now = clock()
        job.lifecycle = .ended
        job.outcome = outcome
        job.endedAt = now
        job.updatedAt = now
        job.version += 1
        job.attention = .none
        job.health = .ok
        job.current = Current(
            type: "idle",
            summary: summary ?? "Session ended (\(reason))"
        )
        job.extensions["endReason"] = .string(reason)
        evictEnded(before: before, ended: job)
    }

    /// Dismiss one open job from the panel (local only — does not signal the agent).
    @MainActor
    @discardableResult
    func dismissJob(id: String) -> Bool {
        guard jobs[id] != nil, jobs[id]?.lifecycle != .ended else { return false }
        endJobLocally(id: id, reason: "dismissed", summary: "Dismissed")
        return true
    }

    /// Reap local sessions whose producer PID is gone (closed terminal / kill).
    /// Remote aliases are skipped — their PIDs are not visible on this Mac.
    @MainActor
    func reapDeadLocalProducers() {
        let localAlias = LocalMachine.alias
        let now = clock()
        // Avoid thrashing brand-new rows (PID may not be ready / race on spawn).
        let minAge: TimeInterval = 3
        var toEnd: [(id: String, summary: String)] = []
        for job in jobs.values {
            guard job.lifecycle != .ended else { continue }
            guard job.isConversationJob else { continue }
            // Only local machine snapshots — remote PIDs are meaningless here.
            guard job.alias == localAlias else { continue }
            guard now.timeIntervalSince(job.createdAt) >= minAge else { continue }
            guard let pid = producerPID(from: job) else { continue }
            if !processIsAlive(pid) {
                toEnd.append((job.id, "Process gone (pid \(pid))"))
            }
        }
        for item in toEnd {
            endJobLocally(
                id: item.id,
                reason: "process_gone",
                summary: item.summary,
                outcome: .cancelled
            )
        }
    }

    private func producerPID(from job: Job) -> Int32? {
        switch job.extensions["pid"] {
        case .number(let n):
            let v = Int32(n)
            return v > 1 ? v : nil
        case .string(let s):
            guard let v = Int32(s), v > 1 else { return nil }
            return v
        default:
            return nil
        }
    }

    /// Best-effort: `kill(pid, 0)` — exists (or EPERM) vs gone (ESRCH).
    private func processIsAlive(_ pid: Int32) -> Bool {
        if pid <= 1 { return false }
        let rc = kill(pid, 0)
        if rc == 0 { return true }
        // EPERM: process exists but we cannot signal it — still alive.
        return errno == EPERM
    }

    private func commit(before: Job?, next: Job) {
        let stored = next.lifecycle == .ended ? next : ensureLocalActions(next)
        jobs[stored.id] = stored
        bumpRevision()
        notificationSink?(before, stored)
    }

    /// Session closed (`lifecycle == ended`): fire outcome notifications, then drop from panel/store.
    /// No Success/Recent linger — only open sessions stay visible.
    private func evictEnded(before: Job?, ended: Job) {
        notificationSink?(before, ended)
        let id = ended.id
        var changed = false
        if jobs.removeValue(forKey: id) != nil || before != nil {
            timelines.removeValue(forKey: id)
            if selectedJobId == id {
                selectedJobId = nil
            }
            changed = true
        }
        // Children of this conversation (legacy hooks) leave with the parent.
        if purgeLegacyChildren(of: id) {
            changed = true
        }
        if changed {
            bumpRevision()
        }
    }

    /// Drop a single non-conversation row (legacy subagent child).
    private func dropLegacyChild(_ id: String) {
        guard jobs[id] != nil || timelines[id] != nil else { return }
        jobs.removeValue(forKey: id)
        timelines.removeValue(forKey: id)
        if selectedJobId == id { selectedJobId = nil }
        bumpRevision()
    }

    /// Remove leftover child rows for `parentId` (`parentJobId` or id prefix).
    @discardableResult
    private func purgeLegacyChildren(of parentId: String) -> Bool {
        let childIds = jobs.keys.filter { id in
            guard let job = jobs[id], !job.isConversationJob else { return false }
            if case .string(let pid) = job.extensions["parentJobId"], pid == parentId {
                return true
            }
            // Legacy id shape: `{parentId}:{agentId}`
            return id.hasPrefix(parentId + ":")
        }
        guard !childIds.isEmpty else { return false }
        for id in childIds {
            jobs.removeValue(forKey: id)
            timelines.removeValue(forKey: id)
            if selectedJobId == id { selectedJobId = nil }
        }
        return true
    }

    /// Drop every non-conversation row still in memory (one-shot hygiene).
    func purgeAllLegacyChildJobs() {
        let ids = jobs.keys.filter { jobs[$0].map { !$0.isConversationJob } ?? false }
        guard !ids.isEmpty else { return }
        for id in ids {
            jobs.removeValue(forKey: id)
            timelines.removeValue(forKey: id)
            if selectedJobId == id { selectedJobId = nil }
        }
        bumpRevision()
    }

    private func beginRibbonBatch() {
        suppressRibbonInvalidation = true
        pendingRibbonInvalidation = false
    }

    private func endRibbonBatch() {
        suppressRibbonInvalidation = false
        if pendingRibbonInvalidation {
            pendingRibbonInvalidation = false
            ribbonInvalidationSink?()
        }
    }

    private func bumpRevision() {
        revision &+= 1
        if suppressRibbonInvalidation {
            pendingRibbonInvalidation = true
        } else {
            ribbonInvalidationSink?()
        }
    }

    private func applyPatch(_ event: NerveEvent, to s: inout Job) {
        if let name = event.name { s.name = name }
        if let k = event.jobKind { s.kind = k }
        if let lifecycle = event.lifecycle {
            s.lifecycle = lifecycle
            if lifecycle == .ended {
                s.endedAt = event.timestamp
            }
        }
        if let current = event.current { s.current = current }
        if let attention = event.attention { s.attention = attention }
        if let health = event.health { s.health = health }
        if let outcome = event.outcome { s.outcome = outcome }
        if let progress = event.progress { s.progress = progress }
        if let context = event.context { s.context = context }
        if let location = event.location { s.location = location }
        if let capabilities = event.capabilities { s.capabilities = capabilities }
        if let actions = event.actions { s.actions = actions }
        if let ext = event.extensions {
            for (k, v) in ext { s.extensions[k] = v }
        }

        switch event.kind {
        case .jobEnded:
            s.lifecycle = .ended
            s.endedAt = event.timestamp
        default:
            break
        }
    }

    private func timelineTitle(for event: NerveEvent) -> String {
        switch event.kind {
        case .attentionChanged:
            return "Attention → \(event.attention?.level.rawValue ?? "?")"
        case .lifecycleChanged:
            return "Lifecycle → \(event.lifecycle?.rawValue ?? "?")"
        case .currentChanged:
            return event.current?.summary ?? event.current?.name ?? "Current changed"
        case .healthChanged:
            return "Health → \(event.health?.rawValue ?? "?")"
        case .outcomeReported:
            return "Outcome → \(event.outcome?.rawValue ?? "?")"
        case .jobEnded:
            return "Ended"
        case .progressUpdated:
            return event.progress?.label ?? "Progress"
        case .heartbeat:
            return "Heartbeat"
        default:
            return event.kind.rawValue
        }
    }

    private func appendTimeline(jobId: String, kind: String, title: String, at: Date) {
        // Skip pure heartbeats from cluttering
        if kind == EventKind.heartbeat.rawValue { return }
        var list = timelines[jobId] ?? []
        let entry = TimelineEntry(
            id: UUID().uuidString,
            jobId: jobId,
            kind: kind,
            title: title,
            timestamp: at
        )
        list.insert(entry, at: 0)
        if list.count > maxTimelinePerJob {
            list = Array(list.prefix(maxTimelinePerJob))
        }
        timelines[jobId] = list
    }



    private func rememberEventId(_ id: String) {
        if seenEventIds.insert(id).inserted {
            seenEventOrder.append(id)
            if seenEventOrder.count > maxSeenEvents {
                let drop = seenEventOrder.prefix(500)
                for d in drop { seenEventIds.remove(d) }
                seenEventOrder.removeFirst(min(500, seenEventOrder.count))
            }
        }
    }

    // MARK: - Actions

    @MainActor
    @discardableResult
    func performAction(actionId: String, jobId: String, confirmed: Bool = false) -> ActionResult {
        guard var subject = jobs[jobId] else {
            return .denied("Job not found")
        }
        guard let action = subject.actions.first(where: { $0.id == actionId }) else {
            return .denied("Action not declared on this Job")
        }
        guard action.state == .available else {
            return .denied("Action is \(action.state.rawValue)")
        }

        if ActionService.isDestructive(action), !confirmed {
            return .denied("Confirmation required")
        }

        // Dismiss is store-local eviction (no agent signal).
        let kind = action.kind.lowercased()
        if kind == "dismiss" || kind == "dismiss_job" || kind == "dismissjob" {
            let ok = dismissJob(id: jobId)
            return ok ? .succeeded("Dismissed") : .failed("Job not found")
        }

        let klass = ActionService.classify(action: action)
        switch klass {
        case .local:
            let result = ActionService.performLocal(action: action, on: subject)
            applyLocalResult(result, jobId: jobId, actionId: actionId)
            return result

        case .localIfOpenURLElseRemote:
            if subject.location?.openURL != nil || subject.location?.focusHint != nil {
                let result = ActionService.performLocal(action: action, on: subject)
                applyLocalResult(result, jobId: jobId, actionId: actionId)
                return result
            }
            return enqueueRemote(action: action, subject: &subject)

        case .remote:
            return enqueueRemote(action: action, subject: &subject)
        }
    }

    @MainActor
    private func applyLocalResult(_ result: ActionResult, jobId: String, actionId: String) {
        switch result {
        case .succeeded(let msg):
            setActionState(jobId: jobId, actionId: actionId, state: .succeeded)
            appendTimeline(jobId: jobId, kind: "action.completed", title: msg, at: clock())
        case .failed:
            setActionState(jobId: jobId, actionId: actionId, state: .failed)
        case .pending, .unsupported, .denied:
            break
        }
    }

    @MainActor
    private func enqueueRemote(action: JobAction, subject: inout Job) -> ActionResult {
        // Bind to owning producer only
        let req = PendingActionRequest(
            id: UUID().uuidString,
            jobId: subject.id,
            producerId: subject.producer.id,
            actionId: action.id,
            actionKind: action.kind,
            title: action.title,
            requestedAt: clock(),
            state: .pending,
            resultMessage: nil,
            expiresAt: clock().addingTimeInterval(3600)
        )
        pendingActions.insert(req, at: 0)
        if pendingActions.count > maxPendingActions {
            pendingActions = Array(pendingActions.prefix(maxPendingActions))
        }
        setActionState(jobId: subject.id, actionId: action.id, state: .pending)
        appendTimeline(
            jobId: subject.id,
            kind: "action.pending",
            title: "\(action.title) → source",
            at: clock()
        )
        return .pending("Queued for source")
    }

    private func setActionState(jobId: String, actionId: String, state: ActionState) {
        guard var s = jobs[jobId] else { return }
        if let idx = s.actions.firstIndex(where: { $0.id == actionId }) {
            s.actions[idx].state = state
            s.updatedAt = clock()
            jobs[jobId] = s
        }
    }

    /// Source reports action outcome. Source may only complete its own actions.
    @discardableResult
    func completePendingAction(id: String, state: ActionState, message: String?, producerId: String?) -> Bool {
        guard let idx = pendingActions.firstIndex(where: { $0.id == id }) else { return false }
        var req = pendingActions[idx]
        if let producerId, req.producerId != producerId {
            return false
        }
        guard state == .succeeded || state == .failed || state == .expired else { return false }
        req.state = state
        req.resultMessage = message
        pendingActions[idx] = req
        setActionState(jobId: req.jobId, actionId: req.actionId, state: state)
        // Reset action to available after success/fail so it can be used again if source re-declares
        if state == .succeeded || state == .failed {
            DispatchQueue.main.async { [weak self] in
                // brief delay then allow re-use if still present
                self?.setActionState(jobId: req.jobId, actionId: req.actionId, state: .available)
            }
        }
        appendTimeline(
            jobId: req.jobId,
            kind: "action.completed",
            title: message ?? "\(req.title): \(state.rawValue)",
            at: clock()
        )
        return true
    }

    func expireStalePendingActions() {
        let now = clock()
        var changed = false
        for i in pendingActions.indices {
            if pendingActions[i].state == .pending,
               let exp = pendingActions[i].expiresAt,
               exp < now {
                pendingActions[i].state = .expired
                setActionState(
                    jobId: pendingActions[i].jobId,
                    actionId: pendingActions[i].actionId,
                    state: .expired
                )
                changed = true
            }
        }
        if changed { bumpRevision() }
    }

    /// Periodic maintenance: expire pending actions + reap dead local producer PIDs.
    @MainActor
    func runMaintenanceTick() {
        expireStalePendingActions()
        reapDeadLocalProducers()
    }


    // MARK: - Demo / utilities

    func clearAll() {
        jobs.removeAll()
        seenEventIds.removeAll()
        seenEventOrder.removeAll()
        timelines.removeAll()
        pendingActions.removeAll()
        selectedJobId = nil
        bumpRevision()
    }

    func loadDemo() {
        beginRibbonBatch()
        defer { endRibbonBatch() }
        let now = clock()
        let src = ProducerInfo(id: "demo", name: "Demo", kind: "demo")
        let alias = LocalMachine.alias
        let demo: [Job] = [
            {
                var s = Job.make(id: "demo-1", kind: "session", name: "nerve", alias: alias, producer: src, now: now.addingTimeInterval(-3600))
                s.current = Current(type: "editing", name: "Implement ribbon", summary: "Drawing menu-bar ribbon", startedAt: now.addingTimeInterval(-120))
                s.actions = [
                    JobAction(id: "copy", title: "Copy", kind: "copy_summary"),
                ]
                return s
            }(),
            {
                var s = Job.make(id: "demo-2", kind: "build", name: "xcodebuild Nerve", alias: alias, producer: src, now: now.addingTimeInterval(-600))
                s.current = Current(type: "building", summary: "Compiling 42 files", startedAt: now.addingTimeInterval(-90))
                s.progress = Progress(kind: .indeterminate, label: "Building")
                return s
            }(),
            {
                var s = Job.make(id: "demo-3", kind: "test", name: "Unit tests", alias: alias, producer: src, now: now.addingTimeInterval(-300))
                s.current = Current(type: "waiting", summary: "Waiting for approval to run tests", startedAt: now.addingTimeInterval(-60))
                s.attention = Attention(level: .required, reason: "approval", title: "Approve test run", summary: "Needs permission to execute tests")
                s.actions = [JobAction(id: "approve", title: "Approve", kind: "approve", confirmationRequired: true)]
                return s
            }(),
            {
                var s = Job.make(id: "demo-4", kind: "process", name: "long-job", alias: alias, producer: src, now: now.addingTimeInterval(-900))
                s.current = Current(type: "computing", summary: "No heartbeat", startedAt: now.addingTimeInterval(-900))
                s.health = .unresponsive
                s.attention = Attention(level: .suggested, reason: "stale", title: "Possibly stuck", summary: "No update for 15m")
                return s
            }(),
            // Ended jobs are not demo'd: SessionEnd evicts immediately (no Recent/Success linger).
        ]
        for s in demo {
            applySnapshot(s)
            appendTimeline(jobId: s.id, kind: "snapshot", title: "Demo loaded", at: now)
        }
        bumpRevision() // ensure at least one invalidation after batch
    }

    func focusJob(id: String) {
        selectedJobId = id
        panelOpen = true
    }
}
