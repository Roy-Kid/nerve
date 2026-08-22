import AppKit
import SwiftUI

private enum PanelConfirmation: Identifiable {
    case clearAll
    case destructiveAction(actionId: String, jobId: String, title: String, producer: String)

    var id: String {
        switch self {
        case .clearAll:
            return "clear-all"
        case let .destructiveAction(actionId, jobId, _, _):
            return "\(jobId):\(actionId)"
        }
    }
}

/// Status list shown under the menu-bar ribbon.
/// All visible chrome and controls are rendered by SwiftUI.
struct StatusPanelView: View {
    @Environment(JobStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @FocusState private var listFocused: Bool
    @State private var expandedId: String?
    @State private var confirmation: PanelConfirmation?
    @State private var resizeOrigin: CGSize?
    @State private var livePanelSize: CGSize?
    /// Pins MenuBarExtra window top-left while dragging so the panel grows down/right
    /// instead of re-centering under the status item (the classic “runs away” bug).
    @State private var resizeAnchor = PanelResizeAnchor()

    /// User preference + system Reduce Motion.
    private var animate: Bool { settings.effectiveAnimationsEnabled && !systemReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let confirmation {
                confirmationBar(confirmation)
            }
            thinDivider
            statusBody
        }
        .frame(
            width: renderedPanelSize.width,
            height: renderedPanelSize.height,
            alignment: .topLeading
        )
        .overlay(alignment: .bottomTrailing) {
            // Three diagonal lines — classic corner resize grip (not bidirectional arrows).
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(-45))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .gesture(resizeGesture)
                .help("Resize panel")
                .accessibilityLabel("Resize panel")
        }
        // Host window bridge: re-pins origin after every layout pass during resize.
        .background(PanelWindowBridge(anchor: resizeAnchor))
        // Keep ↑/↓ keyboard focus without the system blue focus ring around the panel.
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear { listFocused = true }
        .onChange(of: store.selectedJobId) { _, id in
            if let id { expandedId = id }
        }
        .onKeyPress(.downArrow) {
            moveFocus(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveFocus(-1)
            return .handled
        }
        .onKeyPress(.return) {
            toggleFocused()
            return .handled
        }
        .onKeyPress(.space) {
            toggleFocused()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nerve status panel")
        // Inline confirmation only — SwiftUI `.alert` / `.confirmationDialog` often fail
        // to present (or stick) inside MenuBarExtra `.window`, so the trash button looked dead.
        .onAppear { store.panelOpen = true }
        .onDisappear {
            store.panelOpen = false
            confirmation = nil
            resizeAnchor.endResize()
            resizeOrigin = nil
            livePanelSize = nil
        }
    }

    private var renderedPanelSize: CGSize {
        livePanelSize ?? CGSize(
            width: CGFloat(SettingsStore.clampPanelWidth(settings.panelWidth)),
            height: CGFloat(SettingsStore.clampPanelHeight(settings.panelHeight))
        )
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let origin = resizeOrigin ?? renderedPanelSize
                if resizeOrigin == nil {
                    resizeOrigin = origin
                    resizeAnchor.beginResize()
                }
                let next = CGSize(
                    width: CGFloat(SettingsStore.clampPanelWidth(
                        Double(origin.width + value.translation.width)
                    )),
                    height: CGFloat(SettingsStore.clampPanelHeight(
                        Double(origin.height + value.translation.height)
                    ))
                )
                // No implicit animation — size must track the cursor 1:1.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    livePanelSize = next
                }
                // Immediate pin + layout-pass pin (bridge) fights MenuBarExtra re-anchor.
                resizeAnchor.pinTopLeft(contentSize: next)
            }
            .onEnded { _ in
                if let livePanelSize {
                    settings.panelWidth = Double(livePanelSize.width)
                    settings.panelHeight = Double(livePanelSize.height)
                }
                resizeAnchor.endResize()
                resizeOrigin = nil
                // Keep live size one frame so clearing doesn't flash default before
                // settings-backed size is rendered.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.livePanelSize = nil
                }
            }
    }

    private var listedSubjects: [Job] {
        store.flatStatusJobs(mode: settings.panelGroupMode)
    }

    private var thinDivider: some View {
        Divider()
            .accessibilityHidden(true)
    }

    private func moveFocus(_ delta: Int) {
        let list = listedSubjects
        guard !list.isEmpty else { return }
        let next = min(max(0, store.focusedListIndex + delta), list.count - 1)
        store.focusedListIndex = next
        store.selectedJobId = list[next].id
    }

    private func toggleFocused() {
        let list = listedSubjects
        guard list.indices.contains(store.focusedListIndex) else { return }
        let id = list[store.focusedListIndex].id
        withAnimation(animate ? .easeInOut(duration: 0.14) : nil) {
            if expandedId == id { expandedId = nil }
            else {
                expandedId = id
                store.selectedJobId = id
            }
        }
    }

    /// Cycles Machine → Priority → Status. Icon-only (`arrow.up.arrow.down`).
    private var groupModeButton: some View {
        headerIconButton(
            systemName: "arrow.up.arrow.down",
            help: "Group by \(settings.panelGroupMode.title). Click to cycle: Machine → Priority → Status",
            accessibilityLabel: "Group by \(settings.panelGroupMode.title)",
            accessibilityHint: "Cycles grouping mode"
        ) {
            cycleGroupMode()
        }
    }

    private var refreshButton: some View {
        headerIconButton(
            systemName: "arrow.clockwise",
            help: "Refresh ribbon and expire stale pending actions",
            accessibilityLabel: "Refresh",
            accessibilityHint: "Refreshes presentation"
        ) {
            refreshPresentation()
        }
    }

    private var clearButton: some View {
        let isArmed = {
            if case .clearAll = confirmation { return true }
            return false
        }()
        return headerIconButton(
            systemName: isArmed ? "trash.fill" : "trash",
            help: isArmed
                ? "Confirm clear — use the bar below, or click again to cancel"
                : "Clear all jobs from memory",
            accessibilityLabel: isArmed ? "Clear all (confirming)" : "Clear all",
            accessibilityHint: isArmed
                ? "Confirmation bar is open below the header"
                : "Removes all jobs from the panel",
            emphasized: isArmed
        ) {
            confirmClearAll()
        }
        .disabled(store.activeJobs.isEmpty)
    }

    private func headerIconButton(
        systemName: String,
        help: String,
        accessibilityLabel: String,
        accessibilityHint: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(emphasized ? Color.red.opacity(0.9) : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        // `.plain` is more reliable than `.borderless` for icon hits in MenuBarExtra.
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    private func cycleGroupMode() {
        let all = PanelGroupMode.allCases
        guard let idx = all.firstIndex(of: settings.panelGroupMode) else {
            settings.panelGroupMode = .machine
            return
        }
        let next = all[(idx + 1) % all.count]
        withAnimation(animate ? .easeInOut(duration: 0.12) : nil) {
            settings.panelGroupMode = next
            store.focusedListIndex = 0
        }
    }

    private func refreshPresentation() {
        // Job upkeep (expiry, PID reaping) belongs to the hub; the panel only
        // asks the ribbon to repaint what the latest frame already says.
        store.ribbonInvalidationSink?()
    }

    private func confirmClearAll() {
        // Toggle: second click cancels if the bar is already open for clear-all.
        if case .clearAll = confirmation {
            confirmation = nil
            return
        }
        confirmation = .clearAll
    }

    /// Confirmation lives in the panel — system alerts are unreliable in MenuBarExtra windows.
    @ViewBuilder
    private func confirmationBar(_ item: PanelConfirmation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(confirmationTitle(item))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(confirmationMessage(item))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Cancel") {
                confirmation = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .keyboardShortcut(.cancelAction)

            Button(confirmationConfirmLabel(item), role: .destructive) {
                performConfirmed(item)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .tint(.red)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(confirmationTitle(item))
    }

    private func confirmationTitle(_ item: PanelConfirmation) -> String {
        switch item {
        case .clearAll:
            return "Clear all jobs?"
        case let .destructiveAction(_, _, title, _):
            return title
        }
    }

    private func confirmationMessage(_ item: PanelConfirmation) -> String {
        switch item {
        case .clearAll:
            return "Removes every job and timeline from memory."
        case let .destructiveAction(_, _, title, producer):
            return "Run “\(title)”? Provided by \(producer)."
        }
    }

    private func confirmationConfirmLabel(_ item: PanelConfirmation) -> String {
        switch item {
        case .clearAll:
            return "Clear"
        case .destructiveAction:
            return "Confirm"
        }
    }

    private func performConfirmed(_ item: PanelConfirmation) {
        switch item {
        case .clearAll:
            expandedId = nil
            store.clearAll()
        case let .destructiveAction(actionId, jobId, _, _):
            _ = store.performAction(actionId: actionId, jobId: jobId, confirmed: true)
        }
        confirmation = nil
    }

    /// Twin metric chips — counts and colors both from `Job.status`
    /// (same source as ribbon bands and row dots). Not raw active/attention facets.
    private var header: some View {
        HStack(spacing: 10) {
            headerMetric(
                systemName: "play.circle.fill",
                count: store.runningCount,
                status: .running,
                help: "\(store.runningCount) running",
                accessibilityLabel: "\(store.runningCount) running"
            )

            if store.attentionCount > 0 {
                headerMetric(
                    systemName: "exclamationmark.circle.fill",
                    count: store.attentionCount,
                    status: .attention,
                    help: "\(store.attentionCount) need attention",
                    accessibilityLabel: "\(store.attentionCount) attention"
                )
            }

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                groupModeButton
                refreshButton
                clearButton
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 38)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
        .accessibilityAddTraits(.isHeader)
    }

    /// Shared chip: filled-circle SF Symbol + monospaced count.
    /// Color comes from the same status palette as the ribbon / row dots.
    private func headerMetric(
        systemName: String,
        count: Int,
        status: Status,
        help: String,
        accessibilityLabel: String
    ) -> some View {
        let color = RibbonPalette.color(
            for: status,
            scheme: colorScheme,
            map: settings.statusColors
        )
        return HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 14, height: 14)
            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(color)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var statusBody: some View {
        let sections = store.statusSections(mode: settings.panelGroupMode)
        if sections.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        sectionHeader(section.title)
                        ForEach(section.jobs) { job in
                            let children = job.isGroupJob ? store.members(of: job.id) : []
                            let treeOpen = expandedId == job.id
                                || children.contains(where: { $0.id == expandedId })
                            ExpandableSubjectRow(
                                subject: job,
                                depth: 0,
                                children: children,
                                isExpanded: treeOpen,
                                isKeyboardFocused: store.selectedJobId == job.id,
                                timeline: store.timeline(for: job.id),
                                childExpandedId: expandedId,
                                childTimelines: Dictionary(
                                    uniqueKeysWithValues: children.map {
                                        ($0.id, store.timeline(for: $0.id))
                                    }
                                ),
                                onToggle: {
                                    withAnimation(animate ? .easeInOut(duration: 0.14) : nil) {
                                        if treeOpen {
                                            expandedId = nil
                                        } else {
                                            expandedId = job.id
                                            store.selectedJobId = job.id
                                            if let idx = listedSubjects.firstIndex(where: { $0.id == job.id }) {
                                                store.focusedListIndex = idx
                                            }
                                        }
                                    }
                                },
                                onToggleChild: { childId in
                                    withAnimation(animate ? .easeInOut(duration: 0.14) : nil) {
                                        if expandedId == childId {
                                            expandedId = job.id // collapse child detail; keep tree open
                                        } else {
                                            expandedId = childId
                                            store.selectedJobId = childId
                                        }
                                    }
                                },
                                onAction: { actionId in
                                    handleAction(actionId: actionId, subject: job)
                                },
                                onChildAction: { actionId, child in
                                    handleAction(actionId: actionId, subject: child)
                                }
                            )
                            rowDivider
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing Running", systemImage: "waveform.path.ecg")
        } description: {
            Text("Send snapshots to the local ingest API, or POST /v1/demo for sample data. State lives in memory only.")
        } actions: {
            Text("POST \(NerveEndpoint.host):\(NerveEndpoint.port)/v1/snapshot")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .symbolRenderingMode(.hierarchical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 36)
            .accessibilityHidden(true)
    }

    private func handleAction(actionId: String, subject: Job) {
        guard let action = subject.actions.first(where: { $0.id == actionId }) else { return }
        if ActionService.isDestructive(action) {
            confirmation = .destructiveAction(
                actionId: actionId,
                jobId: subject.id,
                title: action.title,
                producer: subject.producer.name ?? subject.producer.id
            )
        } else {
            _ = store.performAction(actionId: actionId, jobId: subject.id, confirmed: true)
        }
    }
}

struct StatusPanelRoot: View {
    @Bindable var store: JobStore
    @Bindable var settings: SettingsStore

    var body: some View {
        StatusPanelView()
            .environment(store)
            .environment(settings)
    }
}

// MARK: - MenuBarExtra resize anchor

/// Holds the hosting `NSWindow` and a screen-space top-left pin for the duration
/// of a corner-drag resize. MenuBarExtra re-centers under the status item whenever
/// content size changes; re-applying the pin after layout keeps growth down/right.
@MainActor
final class PanelResizeAnchor {
    weak var window: NSWindow?
    /// Screen coordinates: x = minX, y = maxY (top edge).
    private var pinnedTopLeft: CGPoint?
    private(set) var isResizing = false

    func beginResize() {
        guard let window else { return }
        isResizing = true
        let frame = window.frame
        pinnedTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
    }

    func endResize() {
        isResizing = false
        pinnedTopLeft = nil
    }

    /// Resize window content to `contentSize` while keeping the captured top-left fixed.
    func pinTopLeft(contentSize: CGSize) {
        guard let window, isResizing else { return }
        let pin = pinnedTopLeft ?? CGPoint(x: window.frame.minX, y: window.frame.maxY)
        pinnedTopLeft = pin

        let contentRect = NSRect(
            x: pin.x,
            y: pin.y - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
        // Convert content rect → full window frame (title bar / shadow chrome).
        let frame = window.frameRect(forContentRect: contentRect)
        // Keep top-left of the *window* aligned with the original content top-left
        // when chrome differs; prefer the explicit content placement above.
        var placed = frame
        // frameRect(forContentRect:) already places correctly in screen space for
        // borderless MenuBarExtra windows; still force top edge in case of drift.
        let contentAfter = window.contentRect(forFrameRect: placed)
        let dy = pin.y - contentAfter.maxY
        let dx = pin.x - contentAfter.minX
        if abs(dx) > 0.5 || abs(dy) > 0.5 {
            placed.origin.x += dx
            placed.origin.y += dy
        }
        if placed != window.frame {
            window.setFrame(placed, display: true, animate: false)
        }
    }

    /// Called from the bridge view after AppKit layout — re-apply pin if the system moved us.
    func reassertPinIfNeeded() {
        guard isResizing, let window, let pin = pinnedTopLeft else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let dx = pin.x - content.minX
        let dy = pin.y - content.maxY
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }
        var frame = window.frame
        frame.origin.x += dx
        frame.origin.y += dy
        window.setFrame(frame, display: true, animate: false)
    }
}

/// Invisible NSView that discovers the MenuBarExtra host window and re-pins it
/// after each layout pass while a resize is active.
private struct PanelWindowBridge: NSViewRepresentable {
    let anchor: PanelResizeAnchor

    func makeNSView(context: Context) -> PanelResizeBridgeView {
        let view = PanelResizeBridgeView()
        view.anchor = anchor
        return view
    }

    func updateNSView(_ nsView: PanelResizeBridgeView, context: Context) {
        nsView.anchor = anchor
        if let window = nsView.window {
            anchor.window = window
        }
    }
}

private final class PanelResizeBridgeView: NSView {
    var anchor: PanelResizeAnchor?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        anchor?.window = window
    }

    override func layout() {
        super.layout()
        if let window {
            anchor?.window = window
        }
        // After MenuBarExtra reflows content size it recenters; pull origin back.
        anchor?.reassertPinIfNeeded()
    }

    /// Window-discovery only — never intercept clicks meant for SwiftUI controls.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

// MARK: - Status color dot

/// Native semantic status marker with the standard delayed help tip.
private struct StatusColorDot: View {
    let status: Status
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
            .frame(width: 8, height: 8)
            // Keep the native help target comfortable without enlarging the dot.
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .help(status.title)
            .accessibilityLabel(status.title)
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Single-line expandable subject (tree: subtasks + details)

struct ExpandableSubjectRow: View {
    let subject: Job
    /// Indent level (0 = root, 1 = subtask under a group).
    var depth: Int = 0
    /// Direct children (group members). Empty for leaves / standalone jobs.
    var children: [Job] = []
    let isExpanded: Bool
    var isKeyboardFocused: Bool = false
    var timeline: [TimelineEntry]
    /// Which child id is expanded for detail (parent may stay expanded for tree).
    var childExpandedId: String? = nil
    var childTimelines: [String: [TimelineEntry]] = [:]
    var onToggle: () -> Void
    var onToggleChild: ((String) -> Void)? = nil
    var onAction: (String) -> Void
    var onChildAction: ((String, Job) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(SettingsStore.self) private var settings
    @State private var hovered = false

    private var indent: CGFloat { CGFloat(depth) * 14 }

    private var hasSubtasks: Bool { !children.isEmpty || subject.isGroupJob }

    /// Columns for this paint — hide `.updated` on hover so primary fields get the width.
    private var visibleColumns: [PanelColumn] {
        let cols = settings.panelColumns
        if hovered {
            return cols.filter { $0 != .updated }
        }
        return cols
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Tree disclosure + status
                if depth == 0 && hasSubtasks {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                        .accessibilityHidden(true)
                } else if depth > 0 {
                    // Subtask marker
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .frame(width: 10)
                        .accessibilityHidden(true)
                }

                StatusColorDot(
                    status: subject.status,
                    color: RibbonPalette.color(
                        for: subject.status,
                        scheme: colorScheme,
                        map: settings.statusColors
                    )
                )

                Button(action: onToggle) {
                    HStack(spacing: 8) {
                        ForEach(visibleColumns) { column in
                            columnCell(column)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.quaternary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 12, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 12 + indent)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .background { rowSelectionBackground }
            .onHover { hovered = $0 }
            .animation(nil, value: hovered)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityRowLabel)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expandHint)
            .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
            .accessibilityAction { onToggle() }

            if isExpanded {
                expandedContent
                    .padding(.leading, 28 + indent)
                    .padding(.trailing, 10)
                    .padding(.bottom, 9)
                    .transition(.opacity)
            }
        }
    }

    private var expandHint: String {
        if hasSubtasks && depth == 0 {
            return isExpanded ? "Collapse subtasks and details" : "Expand subtasks and details"
        }
        return isExpanded ? "Collapse details" : "Expand details"
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // --- Subtasks (group members) ---
            if !children.isEmpty {
                sectionLabel("Subtasks", count: children.count)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(children) { child in
                        ExpandableSubjectRow(
                            subject: child,
                            depth: depth + 1,
                            children: [],
                            isExpanded: childExpandedId == child.id,
                            isKeyboardFocused: false,
                            timeline: childTimelines[child.id] ?? [],
                            onToggle: { onToggleChild?(child.id) },
                            onAction: { actionId in
                                onChildAction?(actionId, child)
                            }
                        )
                    }
                }
                .padding(.leading, 4)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03))
                }
            } else if subject.isGroupJob {
                // Group with no visible members under current Settings filter
                Text(emptySubtasksHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }

            // --- Details (metadata / local actions / timeline) ---
            sectionLabel("Details")
            detailBlock
        }
    }

    private var emptySubtasksHint: String {
        switch settings.panelMemberVisibility {
        case .never:
            return "Subtasks hidden (Settings → Batch members: Groups only)"
        case .attention:
            return "No problem/attention subtasks"
        case .all:
            return "No subtasks reported"
        }
    }

    private func sectionLabel(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            if let count {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func columnCell(_ column: PanelColumn) -> some View {
        let text = text(for: column)
        Text(text)
            .font(columnFont(column))
            .foregroundStyle(column == .name ? Color.primary : Color.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
                minWidth: column.isFlexible ? 40 : column.width,
                idealWidth: column.isFlexible ? nil : column.width,
                maxWidth: column.isFlexible ? .infinity : column.width,
                alignment: .leading
            )
            .layoutPriority(column.isFlexible ? 0 : 1)
            .help(text)
            .opacity(text.isEmpty ? 0.35 : 1)
    }

    private func columnFont(_ column: PanelColumn) -> Font {
        switch column {
        case .name: return .body.weight(.medium)
        case .updated: return .caption2.monospacedDigit()
        default: return .caption
        }
    }

    private var accessibilityRowLabel: String {
        visibleColumns
            .map { text(for: $0) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func text(for column: PanelColumn) -> String {
        switch column {
        case .name:
            return subject.name
        case .summary:
            return activityText
        case .producer:
            return subject.producer.name ?? subject.producer.id
        case .machine:
            return subject.alias
        case .status:
            return subject.status.title
        case .updated:
            return timeLabel
        }
    }

    private var activityText: String {
        if subject.attention.level >= .suggested, let title = subject.attention.title, !title.isEmpty {
            return title
        }
        if let s = subject.current?.summary, !s.isEmpty { return s }
        if let n = subject.current?.name, !n.isEmpty { return n }
        return ""
    }

    @ViewBuilder
    private var rowSelectionBackground: some View {
        if hovered || isExpanded || isKeyboardFocused {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowSelectionColor)
                .padding(.horizontal, 6)
        }
    }

    private var rowSelectionColor: Color {
        if isKeyboardFocused {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.30 : 0.14)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055)
    }

    private var detailBlock: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                meta("Status", subject.status.title)
                if let summary = subject.current?.summary ?? subject.current?.name, !summary.isEmpty {
                    meta("Doing", summary)
                }
                let producerLabel = subject.producer.name ?? subject.producer.id
                if !producerLabel.isEmpty {
                    meta("Producer", producerLabel)
                }
                if let project = subject.context?.project, !project.isEmpty, project != subject.name {
                    meta("Project", project)
                }
                if !subject.alias.isEmpty {
                    meta("Machine", subject.alias)
                }
                meta("Updated", format(subject.updatedAt))

                if !subject.actions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(subject.actions) { action in
                            actionButton(action)
                        }
                    }
                    .padding(.top, 5)
                }

                if !timeline.isEmpty {
                    Divider()
                        .padding(.vertical, 3)

                    Text("Recent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)

                    ForEach(timeline.prefix(5)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.quaternary)
                                .frame(width: 52, alignment: .leading)
                            Text(entry.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(2)
        }
        .groupBoxStyle(.automatic)
        .font(.caption)
    }

    private func meta(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: JobAction) -> some View {
        let isOpen = ActionService.isOpenKind(action.kind)
        let helpText = isOpen
            ? "Jump to the agent UI / workspace (Nerve does not type or approve)"
            : action.kind
        if isOpen {
            Button(action.title) {
                onAction(action.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .disabled(action.state != .available)
            .help(helpText)
        } else {
            Button(
                action.title,
                role: ActionService.isDestructive(action) ? .destructive : nil
            ) {
                onAction(action.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(action.state != .available)
            .help(helpText)
        }
    }

    private var timeLabel: String {
        if subject.lifecycle == .ended, let end = subject.endedAt {
            return relative(end)
        }
        if let start = subject.startedAt {
            return relative(start)
        }
        return relative(subject.updatedAt)
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Menu-bar ribbon ambient clock

/// Owns the RunLoop timer so a SwiftUI `View` value type never captures `@State`.
@MainActor
final class RibbonAmbientClock: ObservableObject {
    @Published private(set) var tick: UInt64 = 0
    private var timer: Timer?

    var phase: TimeInterval { Double(tick) / 20.0 }

    func setActive(_ active: Bool) {
        if active {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick &+= 1
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - Menu-bar ribbon label

/// MenuBarExtra label — pure SwiftUI `Canvas` (always visible) + class-owned timer
/// for ambient frames. `NSViewRepresentable` in the status item often paints blank.
struct MenuBarRibbonLabel: View {
    @Bindable var store: JobStore
    @Bindable var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var clock = RibbonAmbientClock()

    private var animate: Bool { settings.effectiveAnimationsEnabled }

    private var ambientActive: Bool {
        animate
            && settings.ribbonMotionStyle.usesAmbientMotion
            && store.activeCount > 0
            && RibbonRenderer.ambientRelevant(store: store, settings: settings)
    }

    private var motion: RibbonMotionStyle {
        ambientActive ? settings.ribbonMotionStyle : .transitionsOnly
    }

    private var phase: TimeInterval { ambientActive ? clock.phase : 0 }

    var body: some View {
        // Observe ambient ticks while motion is on.
        let _ = clock.tick
        ribbonImage
            // Explicit frame keeps MenuBarExtra from collapsing a zero-size label.
            .frame(width: preferredWidth, height: 22)
            .animation(animate ? .easeInOut(duration: 0.28) : nil, value: visualSignature)
            .contentShape(Rectangle())
            .accessibilityLabel("Nerve")
            .accessibilityValue("\(store.activeCount) active jobs")
            .onAppear { clock.setActive(ambientActive) }
            .onDisappear { clock.setActive(false) }
            .onChange(of: ambientActive) { _, on in clock.setActive(on) }
    }

    /// Same `Image(size:)` path that painted the ribbon before the NSView attempt.
    private var ribbonImage: Image {
        let width = max(14, preferredWidth)
        let height: CGFloat = 22
        let barHeight = min(18, max(3, CGFloat(settings.ribbonThickness)))
        let rect = CGRect(
            x: 2,
            y: (height - barHeight) / 2,
            width: max(6, width - 4),
            height: barHeight
        )
        let path = Path(roundedRect: rect, cornerRadius: barHeight / 2, style: .continuous)
        let stops = ribbonStops(motion: motion, time: phase)
        let shimmerCycle = shimmerOverlay(motion: motion, time: phase)
        let dark = colorScheme == .dark
        // Include tick in the label so Image identity refreshes each ambient frame.
        let label = Text("Nerve ribbon \(clock.tick)")

        return Image(
            size: CGSize(width: width, height: height),
            label: label,
            opaque: false,
            colorMode: .nonLinear
        ) { context in
            context.fill(
                path,
                with: .linearGradient(
                    Gradient(stops: stops),
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )
            if let cycle = shimmerCycle {
                context.drawLayer { layer in
                    layer.clip(to: path)
                    let travel = rect.width + rect.width * 0.7
                    let centerX = rect.minX - rect.width * 0.35 + CGFloat(cycle) * travel
                    // Original wider glint (~48% of bar), soft white so color still reads.
                    let half = max(10, rect.width * 0.24)
                    let shine = Path(CGRect(
                        x: centerX - half,
                        y: rect.minY,
                        width: half * 2,
                        height: rect.height
                    ))
                    // Keep this a veil, never a solid wash (peak << 0.3).
                    let peak = dark ? 0.20 : 0.14
                    layer.fill(
                        shine,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: .white.opacity(0), location: 0),
                                .init(color: .white.opacity(peak * 0.4), location: 0.32),
                                .init(color: .white.opacity(peak), location: 0.5),
                                .init(color: .white.opacity(peak * 0.4), location: 0.68),
                                .init(color: .white.opacity(0), location: 1),
                            ]),
                            startPoint: CGPoint(x: centerX - half, y: rect.midY),
                            endPoint: CGPoint(x: centerX + half, y: rect.midY)
                        )
                    )
                }
            }
            context.stroke(path, with: .color(Color.primary.opacity(0.22)), lineWidth: 0.5)
        }
        .renderingMode(.original)
    }

    private var preferredWidth: CGFloat {
        let count = store.activeCount
        if count == 0 {
            return max(14, (22 * CGFloat(settings.ribbonLengthScale)).rounded())
        }
        let base = 28 + (100 - 28) * store.ribbonLengthFactor()
        return min(400, max(16, base * CGFloat(settings.ribbonLengthScale))).rounded()
    }

    private var visualSignature: String {
        "\(store.ribbonSignature(mode: settings.panelGroupMode))|\(settings.ribbonLengthScale)|\(settings.ribbonThickness)|\(settings.statusColors)|\(settings.ribbonMotionStyle.rawValue)"
    }

    private func ribbonStops(motion: RibbonMotionStyle, time: TimeInterval) -> [Gradient.Stop] {
        let segments = store.ribbonSegments(mode: settings.panelGroupMode)
        guard !segments.isEmpty else {
            let idle = baseStatusColor(.inactive).opacity(0.55)
            return [
                .init(color: idle, location: 0),
                .init(color: idle, location: 1),
            ]
        }

        var stops: [Gradient.Stop] = []
        var cursor: CGFloat = 0
        for (index, segment) in segments.enumerated() {
            let color = animatedColor(for: segment.status, motion: motion, time: time)
            let end = min(1, cursor + segment.weight)
            if index == 0 {
                stops.append(.init(color: color, location: 0))
            }
            if index < segments.count - 1 {
                let next = segments[index + 1]
                let nextColor = animatedColor(for: next.status, motion: motion, time: time)
                let blend = min(0.045, min(segment.weight, next.weight) * 0.28)
                stops.append(.init(color: color, location: max(cursor, end - blend)))
                stops.append(.init(color: nextColor, location: min(1, end + blend)))
            } else {
                stops.append(.init(color: color, location: 1))
            }
            cursor = end
        }
        return stops
    }

    /// Progress 0…1 of the shimmer cycle, or nil when shimmer is off.
    private func shimmerOverlay(motion: RibbonMotionStyle, time: TimeInterval) -> Double? {
        guard motion == .shimmer || motion == .full else { return nil }
        let period: TimeInterval = 1.8
        return (time.truncatingRemainder(dividingBy: period)) / period
    }

    private func animatedColor(
        for status: Status,
        motion: RibbonMotionStyle,
        time: TimeInterval
    ) -> Color {
        let base = baseStatusColor(status)
        let pulse = pulseAmount(for: status, motion: motion, time: time)
        guard pulse > 0.001 else { return base }
        // Hard cap: never wash a segment to white (was 0.4–0.6 → full bleach).
        return lift(base, towardWhite: min(0.16, pulse))
    }

    private func pulseAmount(
        for status: Status,
        motion: RibbonMotionStyle,
        time: TimeInterval
    ) -> CGFloat {
        func wave(period: TimeInterval, amplitude: CGFloat) -> CGFloat {
            guard period > 0 else { return 0 }
            let p = (time.truncatingRemainder(dividingBy: period)) / period
            // sin in [-1,1] → 0…1, scaled by amplitude (keep amplitudes small).
            return amplitude * CGFloat((sin(p * 2 * Double.pi - Double.pi / 2) + 1) / 2)
        }
        switch motion {
        case .transitionsOnly, .shimmer:
            return 0
        case .breathe:
            switch status {
            case .running, .waiting: return wave(period: 2.2, amplitude: 0.14)
            default: return 0
            }
        case .statusPulse, .full:
            // Full mode also runs shimmer — keep body pulse subtle so they don't stack to white.
            switch status {
            case .running, .waiting: return wave(period: 2.2, amplitude: 0.12)
            case .attention: return wave(period: 1.4, amplitude: 0.16)
            case .problem: return wave(period: 0.9, amplitude: 0.18)
            default: return 0
            }
        }
    }

    private func baseStatusColor(_ status: Status) -> Color {
        let rgb = settings.statusColors.color(for: status)
        let lift = colorScheme == .dark ? 0.04 : 0
        return Color(
            red: rgb.r + (1 - rgb.r) * lift,
            green: rgb.g + (1 - rgb.g) * lift,
            blue: rgb.b + (1 - rgb.b) * lift
        )
    }

    private func lift(_ color: Color, towardWhite amount: CGFloat) -> Color {
        let a = min(1, max(0, amount))
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        return Color(
            red: r + (1 - r) * a,
            green: g + (1 - g) * a,
            blue: b + (1 - b) * a,
            opacity: alpha
        )
    }
}
