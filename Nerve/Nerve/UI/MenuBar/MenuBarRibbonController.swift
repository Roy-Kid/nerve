import AppKit
import SwiftUI

/// Continuous ribbon lives in the system menu bar (status item), not as a floating window.
/// Left-click → status popover. Right-click → minimal menu (Preferences / Quit).
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
        button.toolTip = "Nerve — left-click status, right-click for Preferences"
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.wantsLayer = true
        button.isBordered = false

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

    /// Rebuild ribbon image/length when subject state changes.
    func refresh(force: Bool = false) {
        guard let item = statusItem, let button = item.button else { return }

        let signature = store.ribbonSignature()
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
            pop.animates = true
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
            title: "Preferences…",
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
            return settings.hideWhenIdle ? 0 : 26
        }
        let factor = store.ribbonLengthFactor()
        // Menu-bar band: clearer steps from ~34pt (1 task) to ~120pt (many)
        let minW: CGFloat = 34
        let maxW: CGFloat = 120
        return (minW + (maxW - minW) * factor).rounded()
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
        let barHeight: CGFloat = 8
        let barRect = NSRect(
            x: bounds.minX + 2,
            y: (bounds.height - barHeight) / 2,
            width: max(6, bounds.width - 4),
            height: barHeight
        )
        let radius = barHeight / 2
        let path = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
        let segments = store.ribbonSegments()
        let map = settings.statusColors

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        // Continuous horizontal gradient with short, soft blends between status colors
        // (not hard blocks, not long muddy mixes).
        if let body = smoothStatusGradient(segments: segments, isDark: isDark, map: map) {
            body.draw(in: barRect, angle: 0)
        } else {
            let idle = RibbonPalette.nsColor(for: .inactive, dark: isDark, map: map)
            idle.withAlphaComponent(0.55).setFill()
            barRect.fill()
        }

        // Internal luminosity (inside bar only)
        if let core = NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0.0), 0.0),
            (NSColor.white.withAlphaComponent(0.20), 0.30),
            (NSColor.white.withAlphaComponent(0.55), 0.50),
            (NSColor.white.withAlphaComponent(0.20), 0.70),
            (NSColor.white.withAlphaComponent(0.0), 1.0)
        ) {
            core.draw(in: barRect, angle: 90)
        }

        let spine = NSRect(
            x: barRect.minX + 2,
            y: barRect.midY - 0.65,
            width: max(2, barRect.width - 4),
            height: 1.3
        )
        NSColor.white.withAlphaComponent(isDark ? 0.50 : 0.40).setFill()
        NSBezierPath(roundedRect: spine, xRadius: 0.65, yRadius: 0.65).fill()

        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(isDark ? 0.18 : 0.28).setStroke()
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

        func lit(_ status: RibbonStatus) -> NSColor {
            let base = RibbonPalette.nsColor(for: status, dark: isDark, map: map)
            return base.blended(withFraction: isDark ? 0.16 : 0.08, of: .white) ?? base
        }

        if segments.count == 1 {
            let c = lit(segments[0].status)
            let hi = c.blended(withFraction: 0.22, of: .white) ?? c
            return NSGradient(colorsAndLocations: (c, 0.0), (hi, 0.5), (c, 1.0))
        }

        // Transition width as fraction of full bar — quick but not a hard edge.
        // ~10–14% of bar, capped so narrow segments keep a readable pure core.
        let baseBlend: CGFloat = 0.11

        var stops: [(NSColor, CGFloat)] = []
        var cursor: CGFloat = 0

        for (index, seg) in segments.enumerated() {
            let color = lit(seg.status)
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
                let nextColor = lit(segments[index + 1].status)
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
            let c = cleaned.first?.0 ?? lit(.inactive)
            return NSGradient(colors: [c, c])
        }

        let colors = cleaned.map(\.0)
        var locations = cleaned.map(\.1)
        return locations.withUnsafeMutableBufferPointer { buf in
            NSGradient(colors: colors, atLocations: buf.baseAddress!, colorSpace: .sRGB)
        }
    }
}
