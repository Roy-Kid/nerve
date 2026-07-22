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
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 8, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
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
        store.runMaintenanceTick()
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
                            ExpandableSubjectRow(
                                subject: job,
                                isExpanded: expandedId == job.id,
                                isKeyboardFocused: store.selectedJobId == job.id,
                                timeline: store.timeline(for: job.id),
                                onToggle: {
                                    withAnimation(animate ? .easeInOut(duration: 0.14) : nil) {
                                        if expandedId == job.id {
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
                                onAction: { actionId in
                                    handleAction(actionId: actionId, subject: job)
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
            Text("POST 127.0.0.1:\(settings.ingestPort)/v1/snapshot")
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

// MARK: - Single-line expandable subject

struct ExpandableSubjectRow: View {
    let subject: Job
    let isExpanded: Bool
    var isKeyboardFocused: Bool = false
    var timeline: [TimelineEntry]
    var onToggle: () -> Void
    var onAction: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(SettingsStore.self) private var settings
    @State private var hovered = false

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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background { rowSelectionBackground }
            .onHover { hovered = $0 }
            .animation(nil, value: hovered)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityRowLabel)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")
            .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
            .accessibilityAction { onToggle() }

            if isExpanded {
                detailBlock
                    .padding(.leading, 28)
                    .padding(.trailing, 10)
                    .padding(.bottom, 9)
                    .transition(.opacity)
            }
        }
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
                            Button(
                                action.title,
                                role: ActionService.isDestructive(action) ? .destructive : nil
                            ) {
                                onAction(action.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(action.state != .available)
                            .help(action.kind)
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

// MARK: - SwiftUI menu-bar label

struct MenuBarRibbonLabel: View {
    @Bindable var store: JobStore
    @Bindable var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var animate: Bool {
        settings.effectiveAnimationsEnabled && !systemReduceMotion
    }

    var body: some View {
        ribbonImage
            .contentShape(Rectangle())
            .animation(
                animate ? .easeInOut(duration: 0.28) : nil,
                value: visualSignature
            )
            .accessibilityLabel("Nerve")
            .accessibilityValue("\(store.activeCount) active jobs")
    }

    private var ribbonImage: Image {
        let width = preferredWidth
        let height: CGFloat = 22
        let barHeight = min(18, max(3, CGFloat(settings.ribbonThickness)))
        let rect = CGRect(
            x: 2,
            y: (height - barHeight) / 2,
            width: max(6, width - 4),
            height: barHeight
        )
        let path = Path(
            roundedRect: rect,
            cornerRadius: barHeight / 2,
            style: .continuous
        )
        let gradient = Gradient(stops: ribbonStops)

        return Image(
            size: CGSize(width: width, height: height),
            label: Text("Nerve status ribbon"),
            opaque: false,
            colorMode: .nonLinear
        ) { context in
            context.fill(
                path,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )
            context.stroke(
                path,
                with: .color(Color.primary.opacity(0.22)),
                lineWidth: 0.5
            )
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
        "\(store.ribbonSignature(mode: settings.panelGroupMode))|\(settings.ribbonLengthScale)|\(settings.ribbonThickness)|\(settings.statusColors)"
    }

    private var ribbonStops: [Gradient.Stop] {
        let segments = store.ribbonSegments(mode: settings.panelGroupMode)
        guard !segments.isEmpty else {
            let idle = statusColor(.inactive).opacity(0.55)
            return [
                .init(color: idle, location: 0),
                .init(color: idle, location: 1),
            ]
        }

        var stops: [Gradient.Stop] = []
        var cursor: CGFloat = 0

        for (index, segment) in segments.enumerated() {
            let color = statusColor(segment.status)
            let end = min(1, cursor + segment.weight)

            if index == 0 {
                stops.append(.init(color: color, location: 0))
            }

            if index < segments.count - 1 {
                let next = segments[index + 1]
                let blend = min(0.045, min(segment.weight, next.weight) * 0.28)
                stops.append(.init(color: color, location: max(cursor, end - blend)))
                stops.append(.init(color: statusColor(next.status), location: min(1, end + blend)))
            } else {
                stops.append(.init(color: color, location: 1))
            }

            cursor = end
        }

        return stops
    }

    private func statusColor(_ status: Status) -> Color {
        let rgb = settings.statusColors.color(for: status)
        let lift = colorScheme == .dark ? 0.04 : 0
        return Color(
            red: rgb.r + (1 - rgb.r) * lift,
            green: rgb.g + (1 - rgb.g) * lift,
            blue: rgb.b + (1 - rgb.b) * lift
        )
    }
}
