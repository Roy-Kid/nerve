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
