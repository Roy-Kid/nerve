import AppKit
import SwiftUI

/// Continuous ribbon lives in the system menu bar (status item), not as a floating window.
/// Left-click → status popover. Right-click → minimal menu (Settings / Quit).
///
/// Rendering uses an `NSImage` on the status button (not a subview). Subviews on
/// `NSStatusBarButton` often fail to redraw when state changes.
@MainActor
final class MenuBarRibbonController: NSObject {
    private let store: SubjectStore
    private let settings: SettingsStore

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var refreshTimer: Timer?
    private var contextMenu: NSMenu?
    private var hostingController: NSHostingController<StatusPanelRoot>?
    private var lastSignature: String = ""
    private var displayedWidth: CGFloat = 0

    init(store: SubjectStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        super.init()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true

        guard let button = item.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.toolTip = "Nerve — left-click for status, right-click for Settings"
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.wantsLayer = true
        button.isBordered = false
        button.appearance = nil

        self.statusItem = item
        rebuildContextMenu()
        refresh(force: true)

        // Safety net: catch anything that missed the invalidation sink
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(force: false)
            }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        popover?.performClose(nil)
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    /// Rebuild ribbon image/length when subject state or ribbon settings change.
    func refresh(force: Bool = false) {
        guard let item = statusItem, let button = item.button else { return }

        let appearanceSignature = button.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua])?
            .rawValue ?? "system"
        let sizeSignature =
            "len=\(settings.ribbonLengthScale)|th=\(settings.ribbonThickness)|hide=\(settings.hideWhenIdle)"
        let signature = "\(store.ribbonSignature(mode: settings.panelGroupMode))|\(appearanceSignature)|\(sizeSignature)"
        let width = RibbonRenderer.preferredWidth(store: store, settings: settings)
        if !force, signature == lastSignature, abs(width - displayedWidth) < 0.5 {
            return
        }
        lastSignature = signature
        displayedWidth = width

        if width < 1 {
            item.isVisible = false
            button.image = nil
            return
        }
        item.isVisible = true
        item.length = width

        let image = RibbonRenderer.image(
            store: store,
            settings: settings,
            width: width,
            height: 22,
            appearance: button.effectiveAppearance
        )
        image.isTemplate = false
        button.image = image
        button.imageScaling = .scaleNone
    }

    func toggleStatusPopover() {
        if let popover, popover.isShown {
            closePopover()
        } else {
            showStatusPopover()
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleStatusPopover()
            return
        }
        switch event.type {
        case .rightMouseUp:
            showContextMenu()
        default:
            if event.modifierFlags.contains(.control) {
                showContextMenu()
            } else {
                toggleStatusPopover()
            }
        }
    }

    func showStatusPopover() {
        guard let button = statusItem?.button else { return }

        if popover == nil {
            let pop = NSPopover()
            pop.behavior = .transient
            pop.animates = settings.effectiveAnimationsEnabled
            pop.appearance = nil
            pop.delegate = self
            self.popover = pop
        }

        let root = StatusPanelRoot(store: store, settings: settings)
        let hosting = NSHostingController(rootView: root)
        hostingController = hosting
        popover?.contentViewController = hosting
        popover?.contentSize = NSSize(width: 340, height: 360)

        store.panelOpen = true
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        DispatchQueue.main.async { [weak self] in
            guard let self, let view = self.hostingController?.view else { return }
            let fitting = view.fittingSize
            let height = min(480, max(180, fitting.height))
            self.popover?.contentSize = NSSize(width: 340, height: height)
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        store.panelOpen = false
    }

    func showContextMenu() {
        rebuildContextMenu()
        guard let button = statusItem?.button, let menu = contextMenu else { return }
        closePopover()

        statusItem?.menu = menu
        button.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
            self?.statusItem?.button?.target = self
            self?.statusItem?.button?.action = #selector(self?.statusItemClicked(_:))
            self?.statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func rebuildContextMenu() {
        let menu = NSMenu()

        let prefs = NSMenuItem(
            title: "Settings…",
            action: #selector(openPreferences(_:)),
            keyEquivalent: ","
        )
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Nerve", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        contextMenu = menu
    }

    @objc private func openPreferences(_ sender: Any?) {
        PreferencesWindowController.show(
            store: store,
            settings: settings,
            onRibbonRefresh: { [weak self] in
                self?.refresh(force: true)
            }
        )
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

extension MenuBarRibbonController: NSPopoverDelegate {
    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            store.panelOpen = false
        }
    }
}

struct StatusPanelRoot: View {
    @Bindable var store: SubjectStore
    @Bindable var settings: SettingsStore

    var body: some View {
        StatusPanelView()
            .environment(store)
            .environment(settings)
    }
}

// MARK: - Ribbon renderer (NSImage for status item)

enum RibbonRenderer {
    static func preferredWidth(store: SubjectStore, settings: SettingsStore) -> CGFloat {
        let n = store.activeCount
        if n == 0 {
            // Idle pill still respects length scale so size settings stay visible.
            let idle: CGFloat = (22 * settings.ribbonLengthScale).rounded()
            return settings.hideWhenIdle ? 0 : max(14, idle)
        }
        let factor = store.ribbonLengthFactor()
        // Keep the signal compact enough to sit naturally beside system status items.
        let minW: CGFloat = 28
        let maxW: CGFloat = 100
        let base = minW + (maxW - minW) * factor
        let scaled = base * CGFloat(settings.ribbonLengthScale)
        // Hard caps so extreme scales still fit the menu bar.
        return min(220, max(16, scaled)).rounded()
    }

    static func image(
        store: SubjectStore,
        settings: SettingsStore,
        width: CGFloat,
        height: CGFloat,
        appearance: NSAppearance
    ) -> NSImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        appearance.performAsCurrentDrawingAppearance {
            draw(
                store: store,
                settings: settings,
                in: NSRect(origin: .zero, size: size),
                isDark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            )
        }
        return image
    }

    private static func draw(
        store: SubjectStore,
        settings: SettingsStore,
        in bounds: NSRect,
        isDark: Bool
    ) {
        // Thickness is user-adjustable; leave a little vertical padding inside the 22pt slot.
        let barHeight = min(bounds.height - 4, max(2, CGFloat(settings.ribbonThickness)))
        let barRect = NSRect(
            x: bounds.minX + 2,
            y: (bounds.height - barHeight) / 2,
            width: max(6, bounds.width - 4),
            height: barHeight
        )
        let radius = barHeight / 2
        let path = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
        let segments = store.ribbonSegments(mode: settings.panelGroupMode)
        let map = settings.statusColors

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        // A flat continuous band; the system menu bar supplies the surrounding depth.
        if let body = smoothStatusGradient(segments: segments, isDark: isDark, map: map) {
            body.draw(in: barRect, angle: 0)
        } else {
            let idle = RibbonPalette.nsColor(for: .inactive, dark: isDark, map: map)
            idle.withAlphaComponent(0.55).setFill()
            barRect.fill()
        }

        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.withAlphaComponent(isDark ? 0.45 : 0.30).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    /// Builds a multi-stop gradient: pure color plateaus + short smooth ramps between statuses.
    private static func smoothStatusGradient(
        segments: [SubjectStore.RibbonSegment],
        isDark: Bool,
        map: StatusColorMap
    ) -> NSGradient? {
        guard !segments.isEmpty else { return nil }

        func resolved(_ status: RibbonStatus) -> NSColor {
            let base = RibbonPalette.nsColor(for: status, dark: isDark, map: map)
            return base.blended(withFraction: isDark ? 0.04 : 0, of: .white) ?? base
        }

        if segments.count == 1 {
            let color = resolved(segments[0].status)
            return NSGradient(colors: [color, color])
        }

        // Transition width as fraction of full bar — quick but not a hard edge.
        // ~10–14% of bar, capped so narrow segments keep a readable pure core.
        let baseBlend: CGFloat = 0.11

        var stops: [(NSColor, CGFloat)] = []
        var cursor: CGFloat = 0

        for (index, seg) in segments.enumerated() {
            let color = resolved(seg.status)
            let start = cursor
            let end = cursor + max(0.0001, seg.weight)

            let prevBlend: CGFloat
            if index == 0 {
                prevBlend = 0
            } else {
                let neighbor = min(seg.weight, segments[index - 1].weight)
                prevBlend = min(baseBlend, neighbor * 0.45)
            }
            let nextBlend: CGFloat
            if index == segments.count - 1 {
                nextBlend = 0
            } else {
                let neighbor = min(seg.weight, segments[index + 1].weight)
                nextBlend = min(baseBlend, neighbor * 0.45)
            }

            // Enter pure color after incoming ramp
            let pureStart = min(end, start + prevBlend * 0.5)
            // Leave pure color before outgoing ramp
            let pureEnd = max(pureStart, end - nextBlend * 0.5)

            if index == 0 {
                stops.append((color, 0))
            }
            // Hold pure color across the plateau
            stops.append((color, pureStart))
            stops.append((color, pureEnd))

            // Quick ramp into next status color (half of blend zone owned by each side)
            if index < segments.count - 1 {
                let nextColor = resolved(segments[index + 1].status)
                let mid = end
                // end of this color just before midpoint, start of next just after
                stops.append((color, max(pureEnd, mid - nextBlend * 0.5)))
                stops.append((nextColor, min(1, mid + nextBlend * 0.5)))
            } else {
                stops.append((color, 1))
            }

            cursor = end
        }

        // Sort & collapse near-duplicate locations so NSGradient stays stable
        var cleaned: [(NSColor, CGFloat)] = []
        for stop in stops.sorted(by: { $0.1 < $1.1 }) {
            let loc = min(1, max(0, stop.1))
            if let last = cleaned.last, abs(last.1 - loc) < 0.004 {
                cleaned[cleaned.count - 1] = (stop.0, loc)
            } else {
                cleaned.append((stop.0, loc))
            }
        }
        if cleaned.count < 2 {
            let c = cleaned.first?.0 ?? resolved(.inactive)
            return NSGradient(colors: [c, c])
        }

        let colors = cleaned.map(\.0)
        var locations = cleaned.map(\.1)
        return locations.withUnsafeMutableBufferPointer { buf in
            NSGradient(colors: colors, atLocations: buf.baseAddress!, colorSpace: .sRGB)
        }
    }
}
