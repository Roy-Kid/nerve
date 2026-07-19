import SwiftUI
import AppKit

/// Borderless status list. Left-click ribbon opens this.
struct StatusPanelView: View {
    @Environment(SubjectStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @FocusState private var listFocused: Bool
    @State private var expandedId: String?

    /// User preference + system Reduce Motion.
    private var animate: Bool { settings.effectiveAnimationsEnabled && !systemReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            thinDivider
            statusBody
        }
        .frame(width: 340)
        .frame(minHeight: 160, maxHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($listFocused)
        .onAppear { listFocused = true }
        .onChange(of: store.selectedSubjectId) { _, id in
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
    }

    private var listedSubjects: [Subject] {
        store.flatStatusSubjects(mode: settings.panelGroupMode)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private func moveFocus(_ delta: Int) {
        let list = listedSubjects
        guard !list.isEmpty else { return }
        let next = min(max(0, store.focusedListIndex + delta), list.count - 1)
        store.focusedListIndex = next
        store.selectedSubjectId = list[next].id
    }

    private func toggleFocused() {
        let list = listedSubjects
        guard list.indices.contains(store.focusedListIndex) else { return }
        let id = list[store.focusedListIndex].id
        withAnimation(animate ? .easeInOut(duration: 0.14) : nil) {
            if expandedId == id { expandedId = nil }
            else {
                expandedId = id
                store.selectedSubjectId = id
            }
        }
    }

    /// Center control: click cycles Priority → Status → Source → …
    private var groupModeToggle: some View {
        Button(action: cycleGroupMode) {
            HStack(spacing: 4) {
                Text(settings.panelGroupMode.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Click to switch grouping: Priority → Status → Source")
        .accessibilityLabel("Group by \(settings.panelGroupMode.title)")
        .accessibilityHint("Cycles grouping mode")
        .accessibilityAddTraits(.isButton)
    }

    private func cycleGroupMode() {
        let all = PanelGroupMode.allCases
        guard let idx = all.firstIndex(of: settings.panelGroupMode) else {
            settings.panelGroupMode = .priority
            return
        }
        let next = all[(idx + 1) % all.count]
        withAnimation(animate ? .easeInOut(duration: 0.12) : nil) {
            settings.panelGroupMode = next
            store.focusedListIndex = 0
        }
    }

    /// Status (left) + group mode (center) + counts (right) on one row.
    private var header: some View {
        ZStack {
            HStack(spacing: 8) {
                Text("Status")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Text("\(store.activeCount)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                if store.attentionCount > 0 {
                    Text("\(store.attentionCount) attention")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.48, blue: 0.08))
                }
            }
            groupModeToggle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                        ForEach(section.subjects) { subject in
                            ExpandableSubjectRow(
                                subject: subject,
                                isExpanded: expandedId == subject.id,
                                isKeyboardFocused: store.selectedSubjectId == subject.id,
                                timeline: store.timeline(for: subject.id),
                                onToggle: {
                                    withAnimation(animate ? .easeInOut(duration: 0.14) : nil) {
                                        if expandedId == subject.id {
                                            expandedId = nil
                                        } else {
                                            expandedId = subject.id
                                            store.selectedSubjectId = subject.id
                                            if let idx = listedSubjects.firstIndex(where: { $0.id == subject.id }) {
                                                store.focusedListIndex = idx
                                            }
                                        }
                                    }
                                },
                                onAction: { actionId in
                                    handleAction(actionId: actionId, subject: subject)
                                }
                            )
                            rowDivider
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing running")
                .font(.system(size: 12, weight: .medium))
            Text("Send snapshots to the local ingest API, or POST /v1/demo for sample data. State lives in memory only.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("POST 127.0.0.1:\(settings.ingestPort)/v1/snapshot")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 28)
            .accessibilityHidden(true)
    }

    private func handleAction(actionId: String, subject: Subject) {
        guard let action = subject.actions.first(where: { $0.id == actionId }) else { return }
        if ActionService.isDestructive(action) {
            let alert = NSAlert()
            alert.messageText = action.title
            alert.informativeText = "Run “\(action.title)” on \(subject.name)? This is provided by \(subject.source.name ?? subject.source.id)."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Confirm")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                _ = store.performAction(actionId: actionId, subjectId: subject.id, confirmed: true)
            }
        } else {
            _ = store.performAction(actionId: actionId, subjectId: subject.id, confirmed: true)
        }
    }
}

// MARK: - Single-line expandable subject

struct ExpandableSubjectRow: View {
    let subject: Subject
    let isExpanded: Bool
    var isKeyboardFocused: Bool = false
    var timeline: [TimelineEntry]
    var onToggle: () -> Void
    var onAction: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(SettingsStore.self) private var settings
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(RibbonPalette.color(for: subject.ribbonStatus, scheme: colorScheme, map: settings.statusColors))
                        .frame(width: 7, height: 7)
                        .shadow(
                            color: RibbonPalette.color(for: subject.ribbonStatus, scheme: colorScheme, map: settings.statusColors).opacity(0.65),
                            radius: 2.5
                        )
                        .accessibilityHidden(true)

                    Text(subject.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .layoutPriority(1)

                    Text(subject.displaySummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(timeLabel)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .fixedSize()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                hovered || isExpanded || isKeyboardFocused
                    ? Color.primary.opacity(isKeyboardFocused ? 0.08 : 0.045)
                    : Color.clear
            )
            .overlay(
                isKeyboardFocused
                    ? RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
                    : nil
            )
            .onHover { hovered = $0 }
            .accessibilityLabel("\(subject.name), \(subject.displaySummary), \(subject.ribbonStatus.rawValue)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")
            .accessibilityAddTraits(isExpanded ? [.isSelected] : [])

            if isExpanded {
                detailBlock
                    .padding(.leading, 27)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
    }

    private var detailBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            meta("Type", subject.type)
            meta("Lifecycle", subject.lifecycle.rawValue)
            meta("Current", subject.current?.summary ?? subject.current?.name ?? "—")
            meta("Attention", attentionText)
            meta("Health", subject.health.rawValue)
            meta("Outcome", subject.outcome?.rawValue ?? "—")
            meta("Progress", progressText)
            meta("Source", subject.source.name ?? subject.source.id)
            if let project = subject.context?.project ?? subject.context?.workspace {
                meta("Project", project)
            }
            meta("Started", format(subject.startedAt ?? subject.createdAt))
            meta("Updated", format(subject.updatedAt))

            if !subject.actions.isEmpty {
                HStack(spacing: 12) {
                    ForEach(subject.actions) { action in
                        Button(action.title) {
                            onAction(action.id)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(action.state == .available ? Color.accentColor : Color.secondary)
                        .disabled(action.state != .available)
                        .help(action.kind)
                    }
                }
                .padding(.top, 4)
            }

            if !timeline.isEmpty {
                Text("Timeline")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
                ForEach(timeline.prefix(8)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.quaternary)
                            .frame(width: 52, alignment: .leading)
                        Text(entry.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .font(.system(size: 11))
    }

    private func meta(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var attentionText: String {
        var parts = [subject.attention.level.rawValue]
        if let t = subject.attention.title { parts.append(t) }
        else if let r = subject.attention.reason { parts.append(r) }
        return parts.joined(separator: " · ")
    }

    private var progressText: String {
        switch subject.progress.kind {
        case .none: return "—"
        case .indeterminate: return subject.progress.label ?? "Indeterminate"
        case .determinate:
            if let r = subject.progress.ratio { return "\(Int(r * 100))%" }
            return subject.progress.label ?? "Determinate"
        case .metrics:
            if let m = subject.progress.metrics?.first {
                if let c = m.current, let t = m.total {
                    return "\(Int(c)) / \(Int(t)) \(m.unit ?? "")"
                }
                return m.label
            }
            return subject.progress.label ?? "Metrics"
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
