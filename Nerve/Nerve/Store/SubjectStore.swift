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

/// Read-only client cache of what `nerve-hub` publishes, plus the display
/// derivations the menu-bar ribbon and status panel read.
///
/// State semantics — apply / commit / evict / reap / retention — live in the
/// hub, never here: two implementations of the same rules would drift. Every
/// mutation of ``jobs`` / ``timelines`` arrives through ``applyFrame(jobs:timelines:)``,
/// which overwrites wholesale because a hub frame is the full truth, not a delta.
/// Commands the user triggers (Clear, Load demo) leave through the request sinks
/// so the hub stays the single writer.
@Observable
final class JobStore {
    private(set) var jobs: [String: Job] = [:]
    private(set) var timelines: [String: [TimelineEntry]] = [:]

    /// Every stored job that is not legacy noise, in panel order.
    ///
    /// Derived once per write rather than per read. It feeds the ribbon, the
    /// panel sections, the header counts and the keyboard list — several of
    /// which one SwiftUI update asks for more than once — and each of those
    /// used to filter the dictionary and sort the result again.
    ///
    /// Sorted here is what lets every reader below filter and stop: a filter
    /// keeps order, so a section carved out of this list is already in it.
    private(set) var conversationJobs: [Job] = []

    /// The open half of ``conversationJobs`` — the only jobs a surface paints.
    /// Ended rows leave on `SessionEnd`, so this is what "active" means.
    private(set) var openJobs: [Job] = []
    /// Dormant: the producer action queue lives in the hub and no surface path
    /// fills this yet. Kept exposed so the panel's observation surface is stable.
    private(set) var pendingActions: [PendingActionRequest] = []

    private let clock: () -> Date

    var panelOpen: Bool = false
    var selectedJobId: String?
    var lastError: String?
    /// Accessibility: focused row in status list (keyboard)
    var focusedListIndex: Int = 0
    /// Bumps on every subject mutation so the menu-bar ribbon can redraw immediately.
    private(set) var revision: UInt64 = 0

    /// Set by AppModel after construction. Driven by `HubClient` once per
    /// changed job, from the `(previous, next)` pairs `FrameDiffer` recovers.
    var notificationSink: ((Job?, Job) -> Void)?
    /// Fired after any state change that should refresh the ribbon.
    var ribbonInvalidationSink: (() -> Void)?
    var settingsProvider: (() -> SettingsStore)?
    /// Set by AppModel: forwards a panel Clear to the hub. Clearing locally
    /// would be undone by the next frame — a visible bug, not a stale cache.
    var clearRequestSink: (() -> Void)?
    /// Set by AppModel: asks the hub to load its demo jobs.
    var demoRequestSink: (() -> Void)?

    /// In-memory only. Subjects/timelines/pending actions are never written to disk.
    init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
        Persistence.wipeLegacyDiskStoreIfPresent()
    }

    // MARK: - Queries

    var activeJobs: [Job] { openJobs }

    /// Open conversation jobs only (legacy subagent child rows excluded).
    var activeCount: Int { openJobs.count }

    /// Jobs that may paint the ribbon (respects Settings.ribbonRootsOnly).
    private func ribbonEligibleJobs() -> [Job] {
        let open = openJobs
        let rootsOnly = settingsProvider?().ribbonRootsOnly ?? true
        if rootsOnly {
            return open.filter(\.paintsRibbon)
        }
        // Style opt-in: also paint attention/problem members.
        return open.filter { job in
            if job.paintsRibbon { return true }
            if job.isMemberJob {
                let s = job.status
                return s == .problem || s == .attention
            }
            return false
        }
    }

    /// Top-level panel rows only (groups + standalone jobs). Members nest under groups.
    private func panelVisibleJobs() -> [Job] {
        openJobs.filter { !$0.isMemberJob }
    }

    /// Child members for a group row, filtered by Settings.panelMemberVisibility.
    func members(of groupId: String) -> [Job] {
        let visibility = settingsProvider?().panelMemberVisibility ?? .attention
        let kids = openJobs.filter { job in
            job.isMemberJob && job.groupId == groupId
        }
        let filtered: [Job]
        switch visibility {
        case .never:
            filtered = []
        case .attention:
            filtered = kids.filter { job in
                let s = job.status
                return s == .problem || s == .attention || s == .waiting
            }
        case .all:
            filtered = kids
        }
        return filtered
    }

    // MARK: Status counts (single source of truth = `Job.status`)

    /// Open jobs with `status == .running`. Same number the ribbon/panel paint blue.
    var runningCount: Int {
        countOpen(where: { $0.status == .running })
    }

    /// Open jobs painted orange (attention, and waiting which shares that hue).
    var attentionCount: Int {
        countOpen(where: { $0.status == .attention || $0.status == .waiting })
    }

    private func countOpen(where pred: (Job) -> Bool) -> Int {
        openJobs.reduce(into: 0) { n, job in
            if pred(job) { n += 1 }
        }
    }

    /// Priority-mode bucket for a status (Attention / Active / Recent). View grouping only.
    /// Open Monitor (watching a stream) stays Active — Recent is unused
    /// because SessionEnd removes the row immediately.
    private func priorityGroup(for status: Status) -> PanelGroup {
        switch status {
        case .problem, .attention, .waiting: return .attention
        case .running, .monitor, .inactive, .success: return .active
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

    /// Priority sections — bucketed only by `Job.status` (no second ruleset).
    func jobsInPriorityGroup(_ group: PanelGroup) -> [Job] {
        switch group {
        case .attention, .active:
            return openJobs.filter { priorityGroup(for: $0.status) == group }
        case .recent:
            // Session close removes the job immediately — no Recent linger.
            return []
        }
    }

    /// Open jobs eligible for the status list (member visibility from Settings).
    private func panelListJobs() -> [Job] {
        panelVisibleJobs()
    }

    private func statusGroupedSections() -> [StatusSection] {
        let list = panelListJobs()
        var buckets: [Status: [Job]] = [:]
        for job in list {
            buckets[job.status, default: []].append(job)
        }
        return Status.painted.compactMap { status in
            guard let items = buckets[status], !items.isEmpty else { return nil }
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
                StatusSection(id: "machine:\(key)", title: key, jobs: items)
            }
            .sorted { a, b in
                a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    func job(id: String) -> Job? { jobs[id] }

    func timeline(for jobId: String) -> [TimelineEntry] {
        (timelines[jobId] ?? []).sorted { $0.timestamp > $1.timestamp }
    }


    /// Panel order: attention, then health, then failure, then recency.
    ///
    /// Applied once, in ``rederive()``. Every section below inherits it by
    /// filtering rather than re-sorting.
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
    /// Members stay off the ribbon unless Settings.ribbonRootsOnly is false.
    func ribbonColorJobs() -> [Job] {
        ribbonEligibleJobs()
    }

    /// Ribbon layout follows the status-panel grouping mode.
    /// Subjects keep the same left→right order as the panel list under that mode;
    /// adjacent same-status subjects merge into one color band so switching
    /// Priority / Status / Source visibly reorders the continuous light strip.
    func ribbonSegments(mode: PanelGroupMode? = nil) -> [RibbonSegment] {
        let resolved = mode ?? settingsProvider?().panelGroupMode ?? .machine
        let painted = ribbonColorJobs()
        let paintIds = Set(painted.map(\.id))
        guard !paintIds.isEmpty else { return [] }

        // Panel order under the active grouping — this is what the user just switched.
        var ordered: [Job] = flatStatusJobs(mode: resolved).filter { paintIds.contains($0.id) }

        if ordered.count < paintIds.count {
            let seen = Set(ordered.map(\.id))
            for s in painted where !seen.contains(s.id) {
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

    // MARK: - Frame intake

    /// Replace the cache with one hub frame.
    ///
    /// Wholesale, never merged: a frame carries every job the hub holds, so a
    /// job missing from it has left, and a timeline missing from it is gone.
    /// That is what makes a dropped connection cost nothing — the next frame
    /// after a reconnect restores the surface completely.
    ///
    /// `ensureLocalActions` runs per job here, the way `commit` used to run it
    /// per write: the hub stores the producer's raw actions and the NSWorkspace
    /// Open/Focus semantics stay on this side.
    func applyFrame(jobs incoming: [Job], timelines incomingTimelines: [String: [TimelineEntry]]) {
        var next: [String: Job] = [:]
        next.reserveCapacity(incoming.count)
        for job in incoming {
            let stored = ensureLocalActions(job)
            next[stored.id] = stored
        }
        jobs = next
        rederive()
        timelines = incomingTimelines
        // A selected row that left the frame must not keep the panel expanded
        // on a job that no longer exists.
        if let selected = selectedJobId, next[selected] == nil {
            selectedJobId = nil
        }
        revision &+= 1
        ribbonInvalidationSink?()
    }

    /// Rebuild the published orderings — the one place a write to ``jobs``
    /// becomes something a view reads.
    private func rederive() {
        conversationJobs = jobs.values
            .filter(\.isConversationJob)
            .sorted(by: sortComparator)
        openJobs = conversationJobs.filter { $0.lifecycle != .ended }
    }

    /// Display-only actions: strip remote control; **Open/Focus first**, then Copy.
    /// Rows leave via SessionEnd / slot supersede / PID reap — no manual Dismiss.
    private func ensureLocalActions(_ job: Job) -> Job {
        guard job.isConversationJob, job.lifecycle != .ended else { return job }
        var j = job
        // Nerve is status display only — never surface reverse-control actions.
        j.actions = j.actions.filter { ActionService.isDisplayAction($0) }
        // Hide dismiss even if a producer still sends it (legacy snapshots).
        j.actions = j.actions.filter {
            let k = $0.kind.lowercased()
            return k != "dismiss" && k != "dismiss_job" && k != "dismissjob"
        }

        // Primary: Open (has openURL) or Focus (focusHint only).
        let hasOpenAction = j.actions.contains { ActionService.isOpenKind($0.kind) }
        if ActionService.canFocus(j), !hasOpenAction {
            let title = ActionService.focusActionTitle(for: j)
            let kind = (j.location?.openURL?.isEmpty == false) ? "open" : "focus"
            j.actions.insert(
                JobAction(id: "open", title: title, kind: kind),
                at: 0
            )
        } else if hasOpenAction {
            // Normalize title + pin Open/Focus to the front.
            if let idx = j.actions.firstIndex(where: { ActionService.isOpenKind($0.kind) }) {
                var action = j.actions.remove(at: idx)
                if ActionService.canFocus(j) {
                    action.title = ActionService.focusActionTitle(for: j)
                    if j.location?.openURL?.isEmpty == false {
                        action.kind = "open"
                    } else if action.kind.lowercased() != "focus" {
                        action.kind = "focus"
                    }
                }
                j.actions.insert(action, at: 0)
            }
        }

        if !j.actions.contains(where: {
            let k = $0.kind.lowercased()
            return k == "copy_summary" || k == "copy"
        }) {
            // After Open when present.
            let insertAt = j.actions.firstIndex(where: { ActionService.isOpenKind($0.kind) })
                .map { $0 + 1 } ?? 0
            j.actions.insert(
                JobAction(id: "copy", title: "Copy", kind: "copy_summary"),
                at: min(insertAt, j.actions.count)
            )
        }
        return j
    }

    // MARK: - Actions

    @MainActor
    @discardableResult
    func performAction(actionId: String, jobId: String, confirmed: Bool = false) -> ActionResult {
        guard let subject = jobs[jobId] else {
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
            return .denied("Display only — Nerve does not control agents or jobs")

        case .unsupportedRemote:
            // Product invariant: status instrument only, never reverse-control.
            return .denied("Display only — Nerve does not control agents or jobs")
        }
    }

    @MainActor
    private func applyLocalResult(_ result: ActionResult, jobId: String, actionId: String) {
        switch result {
        case .succeeded:
            // Open / Copy stay re-clickable; do not freeze them as .succeeded.
            if let kind = jobs[jobId]?.actions.first(where: { $0.id == actionId })?.kind,
               ActionService.reusableKinds.contains(kind.lowercased()) {
                // leave .available
            } else {
                setActionState(jobId: jobId, actionId: actionId, state: .succeeded)
            }
        case .failed:
            setActionState(jobId: jobId, actionId: actionId, state: .failed)
        case .pending, .unsupported, .denied:
            break
        }
    }

    /// Local echo of a click, overwritten by the next frame — the hub owns the
    /// action's real state.
    private func setActionState(jobId: String, actionId: String, state: ActionState) {
        guard var s = jobs[jobId] else { return }
        if let idx = s.actions.firstIndex(where: { $0.id == actionId }) {
            s.actions[idx].state = state
            s.updatedAt = clock()
            jobs[jobId] = s
            rederive()
        }
    }

    // MARK: - Commands (hub round-trips)

    /// Panel Clear. Local-only removal would be refilled by the next frame.
    func clearAll() {
        clearRequestSink?()
    }

    /// First-run coach / Settings demo. The hub owns the demo jobs.
    func loadDemo() {
        demoRequestSink?()
    }

    /// Select + expand a job in the status panel (notification deep-link / keyboard).
    func focusJob(id: String) {
        selectedJobId = id
        panelOpen = true
    }

    /// Notification / deep-link: select the job and run Open/Focus when location exists.
    /// Does **not** approve, submit input, or reverse-control the agent.
    @MainActor
    @discardableResult
    func focusAndOpenJob(id: String) -> ActionResult {
        focusJob(id: id)
        guard let subject = jobs[id] else {
            return .denied("Job not found")
        }
        if let action = subject.actions.first(where: { ActionService.isOpenKind($0.kind) }) {
            return performAction(actionId: action.id, jobId: id, confirmed: true)
        }
        if ActionService.canFocus(subject) {
            return ActionService.openLocation(subject)
        }
        return .succeeded("Focused")
    }
}
