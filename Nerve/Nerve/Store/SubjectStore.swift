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
final class SubjectStore {
    private(set) var subjects: [String: Subject] = [:]
    private(set) var timelines: [String: [TimelineEntry]] = [:]
    private(set) var pendingActions: [PendingActionRequest] = []

    private var seenEventIds: Set<String> = []
    private var seenEventOrder: [String] = []
    private let maxSeenEvents = 4_000
    private let maxRecentEnded = 50
    private let maxTimelinePerSubject = 40
    private let maxPendingActions = 200

    private let clock: () -> Date
    private var suppressRibbonInvalidation = false
    private var pendingRibbonInvalidation = false

    var panelOpen: Bool = false
    var selectedSubjectId: String?
    var lastError: String?
    /// Accessibility: focused row in status list (keyboard)
    var focusedListIndex: Int = 0
    /// Bumps on every subject mutation so the menu-bar ribbon can redraw immediately.
    private(set) var revision: UInt64 = 0

    /// Set by AppModel after construction.
    var notificationSink: ((Subject?, Subject) -> Void)?
    /// Fired after any state change that should refresh the ribbon.
    var ribbonInvalidationSink: (() -> Void)?
    var settingsProvider: (() -> SettingsStore)?

    /// In-memory only. Subjects/timelines/pending actions are never written to disk.
    init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
        Persistence.wipeLegacyDiskStoreIfPresent()
    }

    // MARK: - Queries

    var allSubjects: [Subject] { Array(subjects.values) }

    var activeSubjects: [Subject] {
        subjects.values.filter { $0.lifecycle != .ended }.sorted(by: sortComparator)
    }

    var activeCount: Int { activeSubjects.count }

    var attentionCount: Int {
        subjects.values.filter { $0.lifecycle != .ended && $0.attention.level >= .suggested }.count
    }

    var knownSources: [SourceInfo] {
        var map: [String: SourceInfo] = [:]
        for s in subjects.values { map[s.source.id] = s.source }
        return map.values.sorted { ($0.name ?? $0.id) < ($1.name ?? $1.id) }
    }

    var knownProjects: [String] {
        var set = Set<String>()
        for s in subjects.values {
            if let p = s.context?.project { set.insert(p) }
            if let w = s.context?.workspace { set.insert(w) }
        }
        return set.sorted()
    }

    /// Flat list for keyboard navigation under the default priority grouping.
    var flatStatusSubjects: [Subject] {
        flatStatusSubjects(mode: .priority)
    }

    /// Flat list for keyboard navigation under a chosen grouping mode.
    func flatStatusSubjects(mode: PanelGroupMode) -> [Subject] {
        statusSections(mode: mode).flatMap(\.subjects)
    }

    /// Sections for the status panel. Empty sections are omitted.
    /// Grouping changes section headers only; within each section, subjects
    /// use the default sort (attention → health → outcome → recency).
    func statusSections(mode: PanelGroupMode) -> [StatusSection] {
        switch mode {
        case .priority:
            return PanelGroup.allCases.compactMap { group in
                let items = subjects(in: group)
                guard !items.isEmpty else { return nil }
                return StatusSection(id: group.id, title: group.title, subjects: items)
            }
        case .status:
            return statusGroupedSections()
        case .source:
            return sourceGroupedSections()
        }
    }

    func openPendingActions(forSource sourceId: String?) -> [PendingActionRequest] {
        let now = clock()
        return pendingActions.filter { req in
            guard req.state == .pending else { return false }
            if let exp = req.expiresAt, exp < now { return false }
            if let sourceId { return req.sourceId == sourceId }
            return true
        }
    }

    func subjects(in group: PanelGroup) -> [Subject] {
        switch group {
        case .attention:
            return subjects.values
                .filter { $0.lifecycle != .ended && $0.attention.level >= .informational }
                .sorted(by: sortComparator)
        case .active:
            return subjects.values
                .filter {
                    $0.lifecycle != .ended
                        && $0.attention.level < .informational
                        && ($0.lifecycle == .active || $0.lifecycle == .pending
                            || $0.lifecycle == .created || $0.lifecycle == .suspended)
                }
                .sorted(by: sortComparator)
        case .recent:
            return subjects.values
                .filter { $0.lifecycle == .ended }
                .sorted { a, b in
                    (a.endedAt ?? a.updatedAt) > (b.endedAt ?? b.updatedAt)
                }
                .prefix(maxRecentEnded)
                .map { $0 }
        }
    }

    /// Subjects eligible for the status list: all non-ended + capped recent ended.
    private func panelListSubjects() -> [Subject] {
        let active = subjects.values.filter { $0.lifecycle != .ended }
        let recent = subjects.values
            .filter { $0.lifecycle == .ended }
            .sorted { (a, b) in
                (a.endedAt ?? a.updatedAt) > (b.endedAt ?? b.updatedAt)
            }
            .prefix(maxRecentEnded)
        return Array(active) + Array(recent)
    }

    private func statusGroupedSections() -> [StatusSection] {
        let list = panelListSubjects()
        var buckets: [RibbonStatus: [Subject]] = [:]
        for s in list {
            buckets[s.ribbonStatus, default: []].append(s)
        }
        return RibbonStatus.allCases.compactMap { status in
            guard var items = buckets[status], !items.isEmpty else { return nil }
            items.sort(by: sortComparator)
            return StatusSection(id: "status:\(status.rawValue)", title: status.panelTitle, subjects: items)
        }
    }

    private func sourceGroupedSections() -> [StatusSection] {
        let list = panelListSubjects()
        var buckets: [String: (label: String, items: [Subject])] = [:]
        for s in list {
            let key = s.source.id
            let label = s.source.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (label?.isEmpty == false) ? label! : s.source.id
            if buckets[key] == nil {
                buckets[key] = (label: title, items: [])
            }
            buckets[key]!.items.append(s)
        }
        return buckets
            .map { key, value in
                var items = value.items
                items.sort(by: sortComparator)
                return StatusSection(id: "source:\(key)", title: value.label, subjects: items)
            }
            .sorted { a, b in
                // Sources with higher-attention subjects first, then name.
                let aTop = a.subjects.first?.attention.level ?? .none
                let bTop = b.subjects.first?.attention.level ?? .none
                if aTop != bTop { return aTop > bTop }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    func subject(id: String) -> Subject? { subjects[id] }

    func timeline(for subjectId: String) -> [TimelineEntry] {
        (timelines[subjectId] ?? []).sorted { $0.timestamp > $1.timestamp }
    }


    private func sortComparator(_ a: Subject, _ b: Subject) -> Bool {
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
        var status: RibbonStatus
        var count: Int
        var weight: CGFloat
    }

    /// Subjects that paint the ribbon colors.
    /// Active work always counts; **recent ended** failure/success also count so red/green show
    /// (SPEC: failure red, recent success green — both are typically ended subjects).
    func ribbonColorSubjects() -> [Subject] {
        var list = activeSubjects
        let seen = Set(list.map(\.id))
        // Recent ended with a clear outcome (same window as panel Recent)
        for s in subjects(in: .recent) {
            guard !seen.contains(s.id) else { continue }
            switch s.ribbonStatus {
            case .problem, .success:
                list.append(s)
            default:
                break
            }
        }
        return list
    }

    /// Ribbon layout follows the status-panel grouping mode.
    /// Subjects keep the same left→right order as the panel list under that mode;
    /// adjacent same-status subjects merge into one color band so switching
    /// Priority / Status / Source visibly reorders the continuous light strip.
    func ribbonSegments(mode: PanelGroupMode? = nil) -> [RibbonSegment] {
        let resolved = mode ?? settingsProvider?().panelGroupMode ?? .priority
        let paintIds = Set(ribbonColorSubjects().map(\.id))
        guard !paintIds.isEmpty else { return [] }

        // Panel order under the active grouping — this is what the user just switched.
        var ordered: [Subject] = flatStatusSubjects(mode: resolved).filter { paintIds.contains($0.id) }

        // Ribbon-only extras (e.g. recent success/failure) not present in the flat list.
        if ordered.count < paintIds.count {
            let seen = Set(ordered.map(\.id))
            for s in ribbonColorSubjects() where !seen.contains(s.id) {
                ordered.append(s)
            }
        }
        guard !ordered.isEmpty else { return [] }

        // Merge adjacent same-status runs so the band stays continuous, not speckled.
        var runs: [(status: RibbonStatus, count: Int)] = []
        for s in ordered {
            let status = s.ribbonStatus
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
        _ runs: [(status: RibbonStatus, count: Int)],
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

    /// Signature of ribbon appearance for cheap change detection.
    func ribbonSignature(mode: PanelGroupMode? = nil) -> String {
        let resolved = mode ?? settingsProvider?().panelGroupMode ?? .priority
        let segs = ribbonSegments(mode: resolved)
        let body = segs.map { "\($0.id):\($0.status.rawValue):\($0.count)" }.joined(separator: ",")
        return "n=\(activeCount)|r=\(revision)|g=\(resolved.rawValue)|\(body)"
    }

    // MARK: - Ingest

    @discardableResult
    func apply(envelope: IngestEnvelope) -> Int {
        beginRibbonBatch()
        defer { endRibbonBatch() }
        var applied = 0
        if let list = envelope.subjects {
            for s in list {
                applySnapshot(s)
                applied += 1
            }
        }
        if let events = envelope.events {
            for e in events {
                if apply(event: e) { applied += 1 }
            }
        }
        pruneEnded()
        return applied
    }

    @discardableResult
    func apply(event: NerveEvent) -> Bool {
        if seenEventIds.contains(event.id) {
            return false
        }
        rememberEventId(event.id)

        if event.kind == .snapshot, let full = event.subject {
            applySnapshot(full)
            appendTimeline(
                subjectId: full.id,
                kind: event.kind.rawValue,
                title: "Snapshot",
                at: event.timestamp
            )
            return true
        }

        if let full = event.subject, event.kind == .subjectCreated || subjects[event.subjectId] == nil {
            applySnapshot(full)
            appendTimeline(
                subjectId: full.id,
                kind: event.kind.rawValue,
                title: "Created",
                at: event.timestamp
            )
            return true
        }

        guard var existing = subjects[event.subjectId] else {
            if event.kind == .subjectCreated || event.name != nil {
                let src = SourceInfo(id: event.sourceId)
                var s = Subject.make(
                    id: event.subjectId,
                    type: event.type ?? "custom.unknown",
                    name: event.name ?? event.subjectId,
                    source: src,
                    lifecycle: event.lifecycle ?? .active,
                    now: event.timestamp
                )
                let before: Subject? = nil
                applyPatch(event, to: &s)
                commit(before: before, next: s)
                appendTimeline(
                    subjectId: s.id,
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
        commit(before: before, next: existing)
        appendTimeline(
            subjectId: existing.id,
            kind: event.kind.rawValue,
            title: timelineTitle(for: event),
            at: event.timestamp
        )
        return true
    }

    func applySnapshot(_ subject: Subject) {
        let before = subjects[subject.id]
        if let existing = before, subject.version < existing.version {
            return
        }
        commit(before: before, next: subject)
    }

    private func commit(before: Subject?, next: Subject) {
        subjects[next.id] = next
        bumpRevision()
        notificationSink?(before, next)
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

    private func applyPatch(_ event: NerveEvent, to s: inout Subject) {
        if let name = event.name { s.name = name }
        if let type = event.type { s.type = type }
        if let parentId = event.parentId { s.parentId = parentId }
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
        case .subjectEnded:
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
        case .subjectEnded:
            return "Ended"
        case .progressUpdated:
            return event.progress?.label ?? "Progress"
        case .heartbeat:
            return "Heartbeat"
        default:
            return event.kind.rawValue
        }
    }

    private func appendTimeline(subjectId: String, kind: String, title: String, at: Date) {
        // Skip pure heartbeats from cluttering
        if kind == EventKind.heartbeat.rawValue { return }
        var list = timelines[subjectId] ?? []
        let entry = TimelineEntry(
            id: UUID().uuidString,
            subjectId: subjectId,
            kind: kind,
            title: title,
            timestamp: at
        )
        list.insert(entry, at: 0)
        if list.count > maxTimelinePerSubject {
            list = Array(list.prefix(maxTimelinePerSubject))
        }
        timelines[subjectId] = list
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

    private func pruneEnded() {
        let ended = subjects.values.filter { $0.lifecycle == .ended }
            .sorted { ($0.endedAt ?? $0.updatedAt) > ($1.endedAt ?? $1.updatedAt) }
        if ended.count > maxRecentEnded {
            for old in ended.dropFirst(maxRecentEnded) {
                subjects.removeValue(forKey: old.id)
            }
        }
    }

    // MARK: - Actions

    @MainActor
    @discardableResult
    func performAction(actionId: String, subjectId: String, confirmed: Bool = false) -> ActionResult {
        guard var subject = subjects[subjectId] else {
            return .denied("Subject not found")
        }
        guard let action = subject.actions.first(where: { $0.id == actionId }) else {
            return .denied("Action not declared on this Subject")
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
            applyLocalResult(result, subjectId: subjectId, actionId: actionId)
            return result

        case .localIfOpenURLElseRemote:
            if subject.location?.openURL != nil || subject.location?.focusHint != nil {
                let result = ActionService.performLocal(action: action, on: subject)
                applyLocalResult(result, subjectId: subjectId, actionId: actionId)
                return result
            }
            return enqueueRemote(action: action, subject: &subject)

        case .remote:
            return enqueueRemote(action: action, subject: &subject)
        }
    }

    @MainActor
    private func applyLocalResult(_ result: ActionResult, subjectId: String, actionId: String) {
        switch result {
        case .succeeded(let msg):
            setActionState(subjectId: subjectId, actionId: actionId, state: .succeeded)
            appendTimeline(subjectId: subjectId, kind: "action.completed", title: msg, at: clock())
        case .failed:
            setActionState(subjectId: subjectId, actionId: actionId, state: .failed)
        case .pending, .unsupported, .denied:
            break
        }
    }

    @MainActor
    private func enqueueRemote(action: SubjectAction, subject: inout Subject) -> ActionResult {
        // Bind to owning source only
        let req = PendingActionRequest(
            id: UUID().uuidString,
            subjectId: subject.id,
            sourceId: subject.source.id,
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
        setActionState(subjectId: subject.id, actionId: action.id, state: .pending)
        appendTimeline(
            subjectId: subject.id,
            kind: "action.pending",
            title: "\(action.title) → source",
            at: clock()
        )
        return .pending("Queued for source")
    }

    private func setActionState(subjectId: String, actionId: String, state: ActionState) {
        guard var s = subjects[subjectId] else { return }
        if let idx = s.actions.firstIndex(where: { $0.id == actionId }) {
            s.actions[idx].state = state
            s.updatedAt = clock()
            subjects[subjectId] = s
        }
    }

    /// Source reports action outcome. Source may only complete its own actions.
    @discardableResult
    func completePendingAction(id: String, state: ActionState, message: String?, sourceId: String?) -> Bool {
        guard let idx = pendingActions.firstIndex(where: { $0.id == id }) else { return false }
        var req = pendingActions[idx]
        if let sourceId, req.sourceId != sourceId {
            return false // source isolation
        }
        guard state == .succeeded || state == .failed || state == .expired else { return false }
        req.state = state
        req.resultMessage = message
        pendingActions[idx] = req
        setActionState(subjectId: req.subjectId, actionId: req.actionId, state: state)
        // Reset action to available after success/fail so it can be used again if source re-declares
        if state == .succeeded || state == .failed {
            DispatchQueue.main.async { [weak self] in
                // brief delay then allow re-use if still present
                self?.setActionState(subjectId: req.subjectId, actionId: req.actionId, state: .available)
            }
        }
        appendTimeline(
            subjectId: req.subjectId,
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
                    subjectId: pendingActions[i].subjectId,
                    actionId: pendingActions[i].actionId,
                    state: .expired
                )
                changed = true
            }
        }
        if changed { bumpRevision() }
    }


    // MARK: - Demo / utilities

    func clearAll() {
        subjects.removeAll()
        seenEventIds.removeAll()
        seenEventOrder.removeAll()
        timelines.removeAll()
        pendingActions.removeAll()
        selectedSubjectId = nil
        bumpRevision()
    }

    func loadDemo() {
        beginRibbonBatch()
        defer { endRibbonBatch() }
        let now = clock()
        let src = SourceInfo(id: "demo", name: "Demo Source", kind: "demo")
        let demo: [Subject] = [
            {
                var s = Subject.make(id: "demo-1", type: "agent.session", name: "Claude Code — nerve", source: src, now: now.addingTimeInterval(-3600))
                s.current = Current(type: "editing", name: "Implement ribbon", summary: "Drawing menu-bar ribbon", startedAt: now.addingTimeInterval(-120))
                s.actions = [
                    SubjectAction(id: "copy", title: "Copy", kind: "copy_summary"),
                ]
                return s
            }(),
            {
                var s = Subject.make(id: "demo-2", type: "build", name: "xcodebuild Nerve", source: src, now: now.addingTimeInterval(-600))
                s.current = Current(type: "building", summary: "Compiling 42 files", startedAt: now.addingTimeInterval(-90))
                s.progress = Progress(kind: .indeterminate, label: "Building")
                return s
            }(),
            {
                var s = Subject.make(id: "demo-3", type: "test", name: "Unit tests", source: src, now: now.addingTimeInterval(-300))
                s.current = Current(type: "waiting", summary: "Waiting for approval to run tests", startedAt: now.addingTimeInterval(-60))
                s.attention = Attention(level: .required, reason: "approval", title: "Approve test run", summary: "Needs permission to execute tests")
                s.actions = [SubjectAction(id: "approve", title: "Approve", kind: "approve", confirmationRequired: true)]
                return s
            }(),
            {
                var s = Subject.make(id: "demo-4", type: "process", name: "long-job", source: src, now: now.addingTimeInterval(-900))
                s.current = Current(type: "computing", summary: "No heartbeat", startedAt: now.addingTimeInterval(-900))
                s.health = .unresponsive
                s.attention = Attention(level: .suggested, reason: "stale", title: "Possibly stuck", summary: "No update for 15m")
                return s
            }(),
            {
                var s = Subject.make(id: "demo-5", type: "workflow.run", name: "Nightly pipeline", source: src, now: now.addingTimeInterval(-7200))
                s.lifecycle = .ended
                s.endedAt = now.addingTimeInterval(-120)
                s.outcome = .failure
                s.current = Current(type: "testing", summary: "3 tests failed")
                s.attention = Attention(level: .informational, reason: "failure", title: "Pipeline failed")
                return s
            }(),
            {
                var s = Subject.make(id: "demo-6", type: "agent.session", name: "Codex — docs", source: src, now: now.addingTimeInterval(-4000))
                s.lifecycle = .ended
                s.endedAt = now.addingTimeInterval(-30)
                s.outcome = .success
                s.startedAt = now.addingTimeInterval(-4000)
                s.current = Current(type: "writing", summary: "Updated README")
                return s
            }(),
        ]
        for s in demo {
            applySnapshot(s)
            appendTimeline(subjectId: s.id, kind: "snapshot", title: "Demo loaded", at: now)
        }
        bumpRevision() // ensure at least one invalidation after batch
    }

    func focusSubject(id: String) {
        selectedSubjectId = id
        panelOpen = true
    }
}
