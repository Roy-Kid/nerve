import AppKit
import SwiftUI

// MARK: - Window

@MainActor
final class PreferencesWindowController: NSWindowController {
    private static var shared: PreferencesWindowController?

    static func show(
        store: JobStore,
        settings: SettingsStore,
        tunnels: MachineTunnelManager,
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
            tunnels: tunnels,
            onRibbonRefresh: onRibbonRefresh
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Nerve Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.tabbingMode = .disallowed
        window.appearance = nil
        window.contentViewController = hosting
        window.minSize = NSSize(width: 660, height: 500)
        window.setContentSize(NSSize(width: 700, height: 540))
        window.center()
        window.isReleasedWhenClosed = false

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
    case machines
    case appearance
    case notifications
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .machines: return "Machines"
        case .appearance: return "Appearance"
        case .notifications: return "Notifications"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Menu bar behavior and local connections"
        case .machines: return "This Mac and remotes via SSH"
        case .appearance: return "Ribbon size, system appearance, and status colors"
        case .notifications: return "Choose when Nerve may get your attention"
        case .about: return "Version, privacy, and connection details"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .machines: return "desktopcomputer"
        case .appearance: return "paintpalette.fill"
        case .notifications: return "bell.badge.fill"
        case .about: return "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(nsColor: .systemGray)
        case .machines: return Color(nsColor: .systemTeal)
        case .appearance: return Color(nsColor: .systemIndigo)
        case .notifications: return Color(nsColor: .systemRed)
        case .about: return Color(nsColor: .systemBlue)
        }
    }
}

struct PreferencesView: View {
    @Bindable var store: JobStore
    @Bindable var settings: SettingsStore
    @Bindable var tunnels: MachineTunnelManager
    var onRibbonRefresh: (() -> Void)?

    @State private var tab: PreferencesTab? = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var editingMachine: MachineConfig?
    @State private var showEditor = false

    private var selectedTab: PreferencesTab { tab ?? .general }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(PreferencesTab.allCases, selection: $tab) { item in
                SettingsSidebarLabel(item: item)
                    .tag(item)
                    .accessibilityLabel(item.title)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 184, max: 210)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarFooter
            }
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    generalPane
                case .machines:
                    machinesPane
                case .appearance:
                    appearancePane
                case .notifications:
                    notificationsPane
                case .about:
                    aboutPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, idealWidth: 700, minHeight: 500, idealHeight: 540)
        .sheet(isPresented: $showEditor) {
            if let draft = editingMachine {
                MachineEditorSheet(
                    machine: draft,
                    onSave: { saved in
                        settings.upsertMachine(saved)
                        tunnels.syncConfig()
                        if saved.enabled {
                            tunnels.connect(id: saved.id)
                        } else {
                            tunnels.disconnect(id: saved.id, clearError: true)
                        }
                        showEditor = false
                        editingMachine = nil
                    },
                    onCancel: {
                        showEditor = false
                        editingMachine = nil
                    }
                )
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)

                Text("Nerve")
                    .font(.caption.weight(.medium))

                Spacer(minLength: 4)

                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    // MARK: General

    private var generalPane: some View {
        SettingsPage(tab: .general) {
            Form {
                Section("Menu Bar") {
                    PreferenceToggleRow(
                        title: "Animate status changes",
                        description: "Use subtle motion when the ribbon or status list changes.",
                        isOn: $settings.animationsEnabled
                    )

                    PreferenceToggleRow(
                        title: "Hide when idle",
                        description: "Remove Nerve from the menu bar when no work is active.",
                        isOn: Binding(
                            get: { settings.hideWhenIdle },
                            set: {
                                settings.hideWhenIdle = $0
                                onRibbonRefresh?()
                            }
                        )
                    )
                }

                Section {
                    Picker(
                        "Group items by",
                        selection: Binding(
                            get: { settings.panelGroupMode },
                            set: {
                                settings.panelGroupMode = $0
                                onRibbonRefresh?()
                            }
                        )
                    ) {
                        ForEach(PanelGroupMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Status Panel")
                } footer: {
                    Text("Default is Machine (by reported alias). Ribbon uses the same grouping.")
                }

                Section {
                    LabeledContent("Endpoint") {
                        Text("127.0.0.1:\(settings.ingestPort)")
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Local Connection")
                } footer: {
                    Text("Nerve accepts loopback connections only. Jobs stay in memory and clear when the app quits. Remotes reach this endpoint through SSH tunnels managed under Machines.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Machines

    private var machinesPane: some View {
        SettingsPage(tab: .machines) {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "laptopcomputer")
                            .foregroundStyle(Color(nsColor: .systemBlue))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalMachine.alias)
                                .font(.body.weight(.medium))
                            Text("This Mac · always available · kind \(LocalMachine.kind)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Local")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(nsColor: .systemGreen).opacity(0.15), in: Capsule())
                            .foregroundStyle(Color(nsColor: .systemGreen))
                    }
                } header: {
                    Text("This Mac")
                } footer: {
                    Text("Local jobs typically report alias “\(LocalMachine.alias)”. Any alias is accepted and shown — this list is only for tunnels, not an allow-list.")
                }

                Section {
                    if settings.machines.isEmpty {
                        Text("No remote tunnels yet. Add a machine only if you need SSH reverse-forward so a remote can reach this Mac’s ingest at 127.0.0.1.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(settings.machines) { machine in
                            machineRow(machine)
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                let id = settings.machines[i].id
                                tunnels.disconnect(id: id, clearError: true)
                                settings.removeMachine(id: id)
                            }
                            tunnels.syncConfig()
                        }
                    }

                    Button {
                        editingMachine = MachineConfig(
                            alias: "",
                            hostName: "",
                            user: NSUserName()
                        )
                        showEditor = true
                    } label: {
                        Label("Add Machine…", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Remote Tunnels")
                } footer: {
                    Text("Optional. Jobs do not need to be registered here — ingest shows whatever alias arrives. Configure a remote only to open SSH reverse-forward and optionally normalize its name variants.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func machineRow(_ machine: MachineConfig) -> some View {
        let state = tunnels.state(for: machine.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.alias.isEmpty ? "Untitled" : machine.alias)
                        .font(.body.weight(.semibold))
                    Text("\(machine.user)@\(machine.hostName):\(machine.sshPort)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                machineStateBadge(state)
            }

            if let err = tunnels.error(for: machine.id), state == .error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                Toggle("Enabled", isOn: Binding(
                    get: { machine.enabled },
                    set: { on in
                        var m = machine
                        m.enabled = on
                        settings.upsertMachine(m)
                        tunnels.syncConfig()
                        if on {
                            tunnels.connect(id: m.id)
                        } else {
                            tunnels.disconnect(id: m.id, clearError: true)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                Text(machine.enabled ? "On" : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Connect") { tunnels.connect(id: machine.id) }
                    .disabled(!machine.enabled)
                Button("Disconnect") { tunnels.disconnect(id: machine.id, clearError: true) }
                Button("Edit…") {
                    editingMachine = machine
                    showEditor = true
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func machineStateBadge(_ state: MachineLinkState) -> some View {
        let (label, color): (String, NSColor) = {
            switch state {
            case .idle: return ("Idle", .secondaryLabelColor)
            case .connecting: return ("Connecting", .systemOrange)
            case .connected: return ("Connected", .systemGreen)
            case .error: return ("Error", .systemRed)
            }
        }()
        return Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(nsColor: color).opacity(0.15), in: Capsule())
            .foregroundStyle(Color(nsColor: color))
    }

    // MARK: Appearance

    private var appearancePane: some View {
        SettingsPage(tab: .appearance) {
            Form {
                Section("Interface") {
                    LabeledContent {
                        Label("System", systemImage: "circle.lefthalf.filled")
                            .foregroundStyle(.secondary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Appearance")
                            Text("Light and dark mode follow macOS automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Length")
                            Spacer()
                            Text(ribbonLengthLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { settings.ribbonLengthScale },
                                set: {
                                    settings.ribbonLengthScale = $0
                                    onRibbonRefresh?()
                                }
                            ),
                            in: SettingsStore.ribbonLengthScaleRange,
                            step: 0.05
                        )
                        .accessibilityLabel("Ribbon length")
                        .accessibilityValue(ribbonLengthLabel)

                        Text("How far the ribbon stretches across the menu bar as work piles up.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Thickness")
                            Spacer()
                            Text(ribbonThicknessLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { settings.ribbonThickness },
                                set: {
                                    settings.ribbonThickness = $0
                                    onRibbonRefresh?()
                                }
                            ),
                            in: SettingsStore.ribbonThicknessRange,
                            step: 0.5
                        )
                        .accessibilityLabel("Ribbon thickness")
                        .accessibilityValue(ribbonThicknessLabel)

                        Text("Vertical width of the continuous band inside the menu-bar item.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        settings.ribbonLengthScale = SettingsStore.defaultRibbonLengthScale
                        settings.ribbonThickness = SettingsStore.defaultRibbonThickness
                        onRibbonRefresh?()
                    } label: {
                        Label("Reset Ribbon Size", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(
                        settings.ribbonLengthScale == SettingsStore.defaultRibbonLengthScale
                            && settings.ribbonThickness == SettingsStore.defaultRibbonThickness
                    )
                } header: {
                    Text("Ribbon Size")
                } footer: {
                    Text("Length scales with active work; thickness is fixed. Changes apply immediately to the menu bar.")
                }

                Section {
                    ForEach(RibbonStatus.allCases, id: \.self) { status in
                        ColorPicker(
                            selection: Binding(
                                get: { settings.statusColors.color(for: status).color },
                                set: { newColor in
                                    var map = settings.statusColors
                                    map.set(RGBColor(newColor), for: status)
                                    settings.statusColors = map
                                    onRibbonRefresh?()
                                }
                            ),
                            supportsOpacity: false
                        ) {
                            HStack(spacing: 10) {
                                Image(systemName: statusSymbol(status))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(settings.statusColors.color(for: status).color)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(status.panelTitle)
                                    Text(statusColorHint(status))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Status Colors")
                } footer: {
                    Text("These semantic colors are shared by the menu-bar ribbon and status panel.")
                }

                Section {
                    Button {
                        settings.resetStatusColors()
                        onRibbonRefresh?()
                    } label: {
                        Label("Restore Default Colors", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(settings.statusColors.isDefault)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    private var ribbonLengthLabel: String {
        let pct = Int((settings.ribbonLengthScale * 100).rounded())
        return "\(pct)%"
    }

    private var ribbonThicknessLabel: String {
        let t = settings.ribbonThickness
        if t == t.rounded() {
            return "\(Int(t)) pt"
        }
        return String(format: "%.1f pt", t)
    }

    // MARK: Notifications

    private var notificationsPane: some View {
        SettingsPage(tab: .notifications) {
            Form {
                Section("Delivery") {
                    PreferenceToggleRow(
                        title: "Pause all notifications",
                        description: "Silence every Nerve notification until this is turned off.",
                        isOn: $settings.notificationsPaused
                    )

                    PreferenceToggleRow(
                        title: "Play notification sounds",
                        description: "Use the system notification sound for allowed alerts.",
                        isOn: $settings.notificationSoundEnabled
                    )
                }

                Section("Notify Me About") {
                    NotificationToggle(title: "Required attention", systemImage: "person.crop.circle.badge.exclamationmark", isOn: $settings.notifyRequired)
                    NotificationToggle(title: "Urgent attention", systemImage: "exclamationmark.triangle", isOn: $settings.notifyUrgent)
                    NotificationToggle(title: "Failures", systemImage: "xmark.circle", isOn: $settings.notifyFailure)
                    NotificationToggle(title: "Unresponsive work", systemImage: "bolt.slash", isOn: $settings.notifyUnresponsive)
                    NotificationToggle(title: "Long task completions", systemImage: "checkmark.circle", isOn: $settings.notifyLongSuccess)
                }

                Section("Quiet Hours") {
                    PreferenceToggleRow(
                        title: "Use quiet hours",
                        description: "Hold notifications during a daily schedule.",
                        isOn: $settings.dndEnabled
                    )

                    if settings.dndEnabled {
                        HStack(spacing: 18) {
                            DatePicker("From", selection: timeBinding(\.dndStartMinutes), displayedComponents: .hourAndMinute)
                            DatePicker("Until", selection: timeBinding(\.dndEndMinutes), displayedComponents: .hourAndMinute)
                        }
                        .datePickerStyle(.field)
                    }
                }

                if !store.knownProducers.isEmpty {
                    Section("Muted Sources") {
                        ForEach(store.knownProducers, id: \.id) { source in
                            Toggle(source.name ?? source.id, isOn: Binding(
                                get: { settings.mutedSourceIds.contains(source.id) },
                                set: { _ in settings.toggleMute(producerId: source.id) }
                            ))
                            .toggleStyle(.switch)
                        }
                    }
                }

                if !store.knownProjects.isEmpty {
                    Section("Muted Projects") {
                        ForEach(store.knownProjects, id: \.self) { project in
                            Toggle(project, isOn: Binding(
                                get: { settings.mutedProjectIds.contains(project) },
                                set: { _ in settings.toggleMuteProject(project) }
                            ))
                            .toggleStyle(.switch)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: About

    private var aboutPane: some View {
        SettingsPage(tab: .about) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.accentColor.gradient)
                                .frame(width: 82, height: 82)
                                .shadow(color: Color.accentColor.opacity(0.18), radius: 10, y: 5)

                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 39, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .accessibilityHidden(true)

                        VStack(spacing: 3) {
                            Text("Nerve")
                                .font(.title2.weight(.semibold))
                            Text("Version \(appVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("A quiet menu-bar pulse for builds, agents, tests, and long-running local work.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 390)
                    }

                    VStack(spacing: 0) {
                        AboutInfoRow(
                            title: "Private by design",
                            detail: "Subjects, timelines, and pending actions stay in memory. Only app settings are saved on this Mac.",
                            systemImage: "lock.shield.fill",
                            tint: Color(nsColor: .systemGreen)
                        )

                        Divider()
                            .padding(.leading, 52)

                        AboutInfoRow(
                            title: "Local endpoint",
                            detail: "http://127.0.0.1:\(settings.ingestPort)/v1/snapshot",
                            systemImage: "network",
                            tint: Color(nsColor: .systemBlue),
                            monospacedDetail: true
                        )
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }

                    Button("Show Welcome Tips…") {
                        FirstRunCoachController().show { loadDemo in
                            if loadDemo {
                                store.loadDemo()
                                onRibbonRefresh?()
                            }
                            settings.hasSeenCoachMarks = true
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = settings[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func statusColorHint(_ status: RibbonStatus) -> String {
        switch status {
        case .problem: return "Failed or unable to continue"
        case .attention: return "Needs input, authorization, or a decision"
        case .waiting: return "Waiting for resources or dependencies"
        case .running: return "Actively executing"
        case .success: return "Completed successfully"
        case .inactive: return "Paused, idle, or unknown"
        }
    }

    private func statusSymbol(_ status: RibbonStatus) -> String {
        switch status {
        case .problem: return "xmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .waiting: return "clock.fill"
        case .running: return "play.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .inactive: return "pause.circle.fill"
        }
    }
}

// MARK: - Machine editor

private struct MachineEditorSheet: View {
    @State private var draft: MachineConfig
    var onSave: (MachineConfig) -> Void
    var onCancel: () -> Void

    init(machine: MachineConfig, onSave: @escaping (MachineConfig) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: machine)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var canSave: Bool {
        !MachineConfig.sanitizeAlias(draft.alias).isEmpty
            && !draft.hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(draft.alias.isEmpty ? "New Machine" : "Edit Machine")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var m = draft
                    m.alias = MachineConfig.sanitizeAlias(m.alias)
                    m.hostName = m.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
                    m.user = m.user.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(m)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()

            Divider()

            Form {
                Section {
                    TextField("Alias (hostname short name)", text: $draft.alias)
                        .textFieldStyle(.roundedBorder)
                    TextField("Host (IP or DNS)", text: $draft.hostName)
                        .textFieldStyle(.roundedBorder)
                    TextField("SSH user", text: $draft.user)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("SSH port")
                        Spacer()
                        TextField("", value: $draft.sshPort, format: .number)
                            .frame(width: 72)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Remote Nerve port")
                        Spacer()
                        TextField("", value: $draft.remoteIngestPort, format: .number)
                            .frame(width: 72)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Identity file (optional)", text: Binding(
                        get: { draft.identityFile ?? "" },
                        set: { draft.identityFile = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                } footer: {
                    Text("Alias should match the short hostname on the remote machine. Nerve will open an SSH reverse tunnel so remote jobs can reach this Mac at 127.0.0.1:\(draft.remoteIngestPort).")
                }

                Section {
                    Toggle("Enabled", isOn: $draft.enabled)
                    Toggle("Connect when Nerve starts", isOn: $draft.autoConnect)
                }
            }
            .formStyle(.grouped)
            .padding(.bottom, 12)
        }
        .frame(width: 440, height: 480)
    }
}

// MARK: - Shared settings chrome

private struct SettingsSidebarLabel: View {
    let item: PreferencesTab

    var body: some View {
        Label {
            Text(item.title)
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(item.tint.gradient)
                    .frame(width: 23, height: 23)

                Image(systemName: item.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsPage<Content: View>: View {
    let tab: PreferencesTab
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Text(tab.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 10)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PreferenceToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }
}

private struct NotificationToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
        }
        .toggleStyle(.switch)
    }
}

private struct AboutInfoRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    var monospacedDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))

                Text(detail)
                    .font(monospacedDetail ? .caption.monospaced() : .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - Settings scene fallback

struct SettingsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Nerve Settings", systemImage: "gearshape")
        } description: {
            Text("Open Settings from the menu-bar ribbon.")
        }
        .frame(width: 340, height: 180)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
