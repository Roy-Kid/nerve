import AppKit
import SwiftUI

// MARK: - Window

/// Mos-style Preferences window (tabbed, not a long context menu).
@MainActor
final class PreferencesWindowController: NSWindowController {
    private static var shared: PreferencesWindowController?

    static func show(
        store: SubjectStore,
        settings: SettingsStore,
        onRibbonRefresh: (() -> Void)? = nil
    ) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = PreferencesView(
            store: store,
            settings: settings,
            onRibbonRefresh: onRibbonRefresh
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 460))

        let controller = PreferencesWindowController(window: window)
        shared = controller
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                shared = nil
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Root

private enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case customize
    case notifications
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .customize: return "Customize"
        case .notifications: return "Notifications"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .customize: return "slider.horizontal.3"
        case .notifications: return "bell"
        case .about: return "info.circle"
        }
    }
}

struct PreferencesView: View {
    @Bindable var store: SubjectStore
    @Bindable var settings: SettingsStore
    var onRibbonRefresh: (() -> Void)?

    @State private var tab: PreferencesTab = .general

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                Group {
                    switch tab {
                    case .general:
                        generalPane
                    case .customize:
                        customizePane
                    case .notifications:
                        notificationsPane
                    case .about:
                        aboutPane
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, idealWidth: 520, minHeight: 420, idealHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(PreferencesTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 16, weight: .medium))
                            .frame(height: 20)
                        Text(item.title)
                            .font(.system(size: 11, weight: tab == item ? .semibold : .regular))
                    }
                    .foregroundStyle(tab == item ? Color.accentColor : Color.secondary)
                    .frame(width: 100, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == item ? Color.primary.opacity(0.08) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: General

    private var generalPane: some View {
        PrefForm {
            PrefSection(label: "Ribbon") {
                PrefToggle(
                    title: "Animations",
                    description: "Soft motion on the menu-bar ribbon and status panel",
                    isOn: Binding(
                        get: { settings.animationsEnabled },
                        set: { settings.animationsEnabled = $0 }
                    )
                )
                PrefToggle(
                    title: "Hide When Idle",
                    description: "Hide the ribbon when nothing is active",
                    isOn: Binding(
                        get: { settings.hideWhenIdle },
                        set: {
                            settings.hideWhenIdle = $0
                            onRibbonRefresh?()
                        }
                    )
                )
            }
        }
    }

    // MARK: Customize

    private var customizePane: some View {
        PrefForm {
            PrefSection(label: "Status colors") {
                Text("Pick a color for each ribbon status. Defaults match the product palette.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(RibbonStatus.allCases, id: \.self) { status in
                        statusColorRow(status)
                    }
                }

                HStack(spacing: 10) {
                    Button("Reset Defaults") {
                        settings.resetStatusColors()
                        onRibbonRefresh?()
                    }
                    .controlSize(.small)
                    .disabled(settings.statusColors.isDefault)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func statusColorRow(_ status: RibbonStatus) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(settings.statusColors.color(for: status).color)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 1) {
                Text(status.panelTitle)
                    .font(.system(size: 13, weight: .medium))
                Text(statusColorHint(status))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            ColorPicker(
                "",
                selection: Binding(
                    get: {
                        settings.statusColors.color(for: status).color
                    },
                    set: { newColor in
                        var map = settings.statusColors
                        map.set(RGBColor(newColor), for: status)
                        settings.statusColors = map
                        onRibbonRefresh?()
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 44)
            .accessibilityLabel("\(status.panelTitle) color")
        }
    }

    private func statusColorHint(_ status: RibbonStatus) -> String {
        switch status {
        case .problem: return "Failed or cannot continue"
        case .attention: return "Needs input, auth, or a decision"
        case .waiting: return "Waiting on system, resources, or dependencies"
        case .running: return "Actively executing"
        case .success: return "Recently completed successfully"
        case .inactive: return "Paused, idle, or unknown"
        }
    }

    // MARK: Notifications

    private var notificationsPane: some View {
        PrefForm {
            PrefSection(label: "Delivery") {
                PrefToggle(
                    title: "Pause All Notifications",
                    description: "Silence every Nerve alert until turned back on",
                    isOn: $settings.notificationsPaused
                )
                PrefToggle(
                    title: "Notification Sound",
                    description: "Play a sound with allowed notifications",
                    isOn: $settings.notificationSoundEnabled
                )
            }

            PrefSection(label: "Events") {
                PrefToggle(
                    title: "Required Attention",
                    description: "When a subject needs a decision or input",
                    isOn: $settings.notifyRequired
                )
                PrefToggle(
                    title: "Urgent Attention",
                    description: "High-priority attention signals",
                    isOn: $settings.notifyUrgent
                )
                PrefToggle(
                    title: "Failures",
                    description: "When a subject reports a problem",
                    isOn: $settings.notifyFailure
                )
                PrefToggle(
                    title: "Unresponsive",
                    description: "When a subject stops reporting",
                    isOn: $settings.notifyUnresponsive
                )
                PrefToggle(
                    title: "Long Task Success",
                    description: "Celebrate long-running work that finishes cleanly",
                    isOn: $settings.notifyLongSuccess
                )
            }

            PrefSection(label: "Quiet hours") {
                PrefToggle(
                    title: "Do Not Disturb Schedule",
                    description: "Block notifications during a daily window (overnight wrap OK)",
                    isOn: $settings.dndEnabled
                )
                if settings.dndEnabled {
                    HStack(spacing: 12) {
                        PrefCycleButton(
                            title: "Start",
                            value: settings.dndStartLabel,
                            action: { settings.cycleDNDStart() }
                        )
                        PrefCycleButton(
                            title: "End",
                            value: settings.dndEndLabel,
                            action: { settings.cycleDNDEnd() }
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 2)
                }
            }

            if !store.knownSources.isEmpty {
                PrefSection(label: "Mute source") {
                    ForEach(store.knownSources, id: \.id) { src in
                        PrefToggle(
                            title: src.name ?? src.id,
                            description: "No notifications from this source",
                            isOn: Binding(
                                get: { settings.mutedSourceIds.contains(src.id) },
                                set: { _ in settings.toggleMute(sourceId: src.id) }
                            )
                        )
                    }
                }
            }

            if !store.knownProjects.isEmpty {
                PrefSection(label: "Mute project") {
                    ForEach(store.knownProjects, id: \.self) { project in
                        PrefToggle(
                            title: project,
                            description: "No notifications for this project",
                            isOn: Binding(
                                get: { settings.mutedProjectIds.contains(project) },
                                set: { _ in settings.toggleMuteProject(project) }
                            )
                        )
                    }
                }
            }
        }
    }

    // MARK: About

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nerve")
                .font(.system(size: 20, weight: .semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("A menu-bar pulse for local agent work. Left-click the ribbon for status; right-click → Preferences for settings.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Privacy")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 4)
            Text("Nerve does not write subjects, timelines, or pending actions to disk. State is memory-only for the session. Only preference toggles (colors, notifications, etc.) are saved in UserDefaults.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Ingest")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 4)
            Text("http://127.0.0.1:\(settings.ingestPort)/v1/snapshot")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("POST /v1/demo loads sample data; POST /v1/clear clears memory.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button("Show Welcome Tips…") {
                FirstRunCoachController().show { loadDemo in
                    if loadDemo {
                        store.loadDemo()
                        onRibbonRefresh?()
                    }
                    settings.hasSeenCoachMarks = true
                }
            }
            .controlSize(.small)
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Form chrome (Mos-like)

private struct PrefForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrefSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(label):")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(width: 108, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PrefToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(.regular)
    }
}

private struct PrefCycleButton: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button(action: action) {
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minWidth: 52)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Click to cycle \(title.lowercased()) time")
        }
    }
}

// MARK: - Legacy Settings scene placeholder

/// System Settings scene fallback — primary UI is `PreferencesWindowController`.
struct SettingsView: View {
    var body: some View {
        Text("Open Preferences from the menu-bar ribbon (right-click → Preferences…).")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(20)
            .frame(width: 320, alignment: .leading)
    }
}
