import AppKit
import SwiftUI

/// Continuous ribbon lives in the system menu bar (status item), not as a floating window.
/// Left-click → status panel. Right-click → minimal menu (Settings / Quit).
///
/// Rendering uses an `NSImage` on the status button (not a subview). Subviews on
/// `NSStatusBarButton` often fail to redraw when state changes.
///
/// Segment / length changes cross-fade and ease width instead of hard-swapping.
///
/// Status UI is a borderless `NSPanel` (not `NSPopover`) so corner-drag resize
/// keeps the top-left fixed and never re-anchors under the status item mid-drag.
@MainActor
final class MenuBarRibbonController: NSObject {
    private let store: JobStore
    private let settings: SettingsStore
    private let tunnels: MachineTunnelManager

    private var statusItem: NSStatusItem?
    private var statusPanel: NSPanel?
    private var panelRootView: NSView?
    private var resizeHandle: CornerResizeHandleView?
    private var dismissMonitor: Any?
    private var refreshTimer: Timer?
    private var contextMenu: NSMenu?
    private var hostingController: NSHostingController<StatusPanelRoot>?
    private var lastSignature: String = ""
    private var displayedWidth: CGFloat = 0

    // MARK: Transition animation

    private var animTimer: Timer?
    private var animStart: Date?
    private var animFromWidth: CGFloat = 0
    private var animToWidth: CGFloat = 0
    private var animFromImage: NSImage?
    private var animToImage: NSImage?
    private var pendingTargetImage: NSImage?
    private var pendingTargetWidth: CGFloat = 0
    private var pendingTargetSignature: String = ""
    /// Last image actually shown (mid-anim blend or settled target).
    private var lastShownImage: NSImage?

    private let animDuration: TimeInterval = 0.32

    init(store: JobStore, settings: SettingsStore, tunnels: MachineTunnelManager) {
        self.store = store
        self.settings = settings
        self.tunnels = tunnels
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
        stopAnimation(applyFinal: false)
        refreshTimer?.invalidate()
        refreshTimer = nil
        closeStatusPanel()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    /// Rebuild ribbon image/length when subject state or ribbon settings change.
    /// `force` is retained for callers; visual no-op still short-circuits so rapid
    /// job updates do not thrash the status item when segments are unchanged.
    func refresh(force _: Bool = false) {
        guard let item = statusItem, let button = item.button else { return }

        let appearanceSignature = button.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua])?
            .rawValue ?? "system"
        let sizeSignature =
            "len=\(settings.ribbonLengthScale)|th=\(settings.ribbonThickness)|hide=\(settings.hideWhenIdle)"
        let colorSignature = colorMapSignature(settings.statusColors)
        let signature =
            "\(store.ribbonSignature(mode: settings.panelGroupMode))|\(appearanceSignature)|\(sizeSignature)|\(colorSignature)"
        let width = RibbonRenderer.preferredWidth(store: store, settings: settings)

        // Even with force, skip if the *visual* ribbon is unchanged (avoids flicker
        // on every tool event when segments/length stay the same).
        if signature == lastSignature, abs(width - displayedWidth) < 0.5, animTimer == nil {
            return
        }
        // Mid-animation toward the same target → leave it alone.
        if animTimer != nil, signature == pendingTargetSignature {
            return
        }

        let appearance = button.effectiveAppearance
        let targetImage: NSImage? = {
            guard width >= 1 else { return nil }
            let image = RibbonRenderer.image(
                store: store,
                settings: settings,
                width: width,
                height: 22,
                appearance: appearance
            )
            image.isTemplate = false
            return image
        }()

        // First paint (empty signature) snaps; later visual changes ease.
        // Reduce Motion / animations off → always snap.
        let animate = settings.effectiveAnimationsEnabled && !lastSignature.isEmpty

        lastSignature = signature
        pendingTargetSignature = signature
        pendingTargetWidth = width
        pendingTargetImage = targetImage

        if !animate {
            stopAnimation(applyFinal: false)
            applySettled(width: width, image: targetImage, item: item, button: button)
            return
        }

        // Retarget: blend from whatever is on screen now toward the new target.
        let fromWidth = animTimer != nil ? currentAnimWidth() : displayedWidth
        let fromImage = snapshotCurrentFrame() ?? lastShownImage

        animFromWidth = fromWidth
        animToWidth = width
        animFromImage = fromImage
        animToImage = targetImage
        animStart = Date()

        if animTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tickAnimation()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            animTimer = timer
        }

        // First animated frame immediately so we never show a stale hard cut.
        tickAnimation()
    }

    private func colorMapSignature(_ map: StatusColorMap) -> String {
        func c(_ rgb: RGBColor) -> String {
            String(format: "%.3f,%.3f,%.3f", rgb.r, rgb.g, rgb.b)
        }
        return [
            c(map.problem), c(map.attention), c(map.waiting),
            c(map.running), c(map.monitor), c(map.success), c(map.inactive),
        ].joined(separator: "|")
    }

    private func currentAnimWidth() -> CGFloat {
        guard let start = animStart else { return displayedWidth }
        let t = easeInOut(min(1, max(0, Date().timeIntervalSince(start) / animDuration)))
        return animFromWidth + (animToWidth - animFromWidth) * CGFloat(t)
    }

    private func snapshotCurrentFrame() -> NSImage? {
        guard let button = statusItem?.button else { return lastShownImage }
        // Prefer the image we last applied (includes mid-blend frames).
        if let lastShownImage { return lastShownImage }
        return button.image
    }

    private func tickAnimation() {
        guard let item = statusItem, let button = item.button else {
            stopAnimation(applyFinal: false)
            return
        }
        guard let start = animStart else {
            stopAnimation(applyFinal: true)
            return
        }

        let elapsed = Date().timeIntervalSince(start)
        let linear = min(1, max(0, elapsed / animDuration))
        let t = easeInOut(linear)

        let width = animFromWidth + (animToWidth - animFromWidth) * CGFloat(t)
        let image = blendedRibbonImage(
            from: animFromImage,
            to: animToImage,
            t: CGFloat(t),
            width: max(width, 1)
        )

        applyFrame(width: width, image: image, item: item, button: button)

        if linear >= 1 {
            stopAnimation(applyFinal: true)
        }
    }

    private func stopAnimation(applyFinal: Bool) {
        animTimer?.invalidate()
        animTimer = nil
        animStart = nil
        animFromImage = nil
        animToImage = nil

        guard applyFinal, let item = statusItem, let button = item.button else { return }
        applySettled(
            width: pendingTargetWidth,
            image: pendingTargetImage,
            item: item,
            button: button
        )
    }

    private func applySettled(width: CGFloat, image: NSImage?, item: NSStatusItem, button: NSStatusBarButton) {
        displayedWidth = width
        if width < 1 || image == nil {
            item.isVisible = false
            button.image = nil
            lastShownImage = nil
            return
        }
        item.isVisible = true
        item.length = width
        button.image = image
        button.imageScaling = .scaleNone
        lastShownImage = image
    }

    private func applyFrame(width: CGFloat, image: NSImage?, item: NSStatusItem, button: NSStatusBarButton) {
        displayedWidth = width
        if width < 1 {
            // Fade through a vanishing pill, then hide at the end of the anim.
            if let image {
                item.isVisible = true
                item.length = max(width, 1)
                button.image = image
                button.imageScaling = .scaleNone
                lastShownImage = image
            } else {
                item.isVisible = false
                button.image = nil
                lastShownImage = nil
            }
            return
        }
        item.isVisible = true
        item.length = width
        if let image {
            button.image = image
            button.imageScaling = .scaleNone
            lastShownImage = image
        }
    }

    /// Cross-dissolve two ribbon images into the live width (scales each to the slot).
    private func blendedRibbonImage(
        from: NSImage?,
        to: NSImage?,
        t: CGFloat,
        width: CGFloat
    ) -> NSImage? {
        let height: CGFloat = 22
        let size = NSSize(width: max(1, width), height: height)

        if t <= 0.001 { return scaledImage(from, to: size) ?? fadedImage(to, alpha: 0.02, size: size) }
        if t >= 0.999 { return scaledImage(to, to: size) ?? fadedImage(from, alpha: 0.02, size: size) }
        if from == nil {
            // Appear from empty: fade the target in.
            return fadedImage(to, alpha: t, size: size)
        }
        if to == nil {
            // Morphing toward hidden: fade out the old ribbon.
            return fadedImage(from, alpha: 1 - t, size: size)
        }

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high

        let rect = NSRect(origin: .zero, size: size)
        from?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1 - t)
        to?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: t)
        image.isTemplate = false
        return image
    }

    private func scaledImage(_ source: NSImage?, to size: NSSize) -> NSImage? {
        guard let source else { return nil }
        if abs(source.size.width - size.width) < 0.5,
           abs(source.size.height - size.height) < 0.5
        {
            return source
        }
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.isTemplate = false
        return image
    }

    private func fadedImage(_ source: NSImage?, alpha: CGFloat, size: NSSize) -> NSImage? {
        guard let source, alpha > 0.01 else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: min(1, max(0, alpha))
        )
        image.isTemplate = false
        return image
    }

    /// Smoothstep ease — soft start/end without overshoot.
    private func easeInOut(_ t: TimeInterval) -> TimeInterval {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    func toggleStatusPopover() {
        if statusPanel?.isVisible == true {
            closeStatusPanel()
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

        let size = panelContentSize()
        let root = StatusPanelRoot(store: store, settings: settings)
        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController = hosting

        let panel = ensureStatusPanel()
        installHosting(hosting, in: panel)
        positionStatusPanel(panel, size: size, under: button)
        panel.orderFront(nil)
        // Keyboard ↑/↓ needs key window; accessory apps must activate briefly.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()

        store.panelOpen = true
        installDismissMonitor()
    }

    private func ensureStatusPanel() -> NSPanel {
        if let statusPanel { return statusPanel }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelContentSize()),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow
        panel.appearance = nil
        panel.acceptsMouseMovedEvents = true

        // Window plumbing only. SwiftUI draws the material, border, and resize icon.
        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true
        root.layer?.cornerCurve = .continuous

        panel.contentView = root
        panelRootView = root

        let handle = CornerResizeHandleView(frame: .zero)
        handle.onResize = { [weak self] size, ended in
            self?.applyPanelSize(size, persist: ended)
        }
        root.addSubview(handle)
        resizeHandle = handle

        statusPanel = panel
        return panel
    }

    private func installHosting(_ hosting: NSHostingController<StatusPanelRoot>, in panel: NSPanel) {
        guard let root = panelRootView ?? panel.contentView else { return }

        hostingController?.view.removeFromSuperview()

        let hostView = hosting.view
        hostView.translatesAutoresizingMaskIntoConstraints = false
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.clear.cgColor

        // Below the transparent AppKit resize hit target.
        if let handle = resizeHandle {
            root.addSubview(hostView, positioned: .below, relativeTo: handle)
        } else {
            root.addSubview(hostView)
        }

        NSLayoutConstraint.activate([
            hostView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            hostView.topAnchor.constraint(equalTo: root.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        layoutResizeHandle(in: root)
    }

    private func layoutResizeHandle(in root: NSView) {
        guard let handle = resizeHandle else { return }
        // Large enough hit target for easy grabbing.
        let side: CGFloat = 22
        handle.autoresizingMask = [.minXMargin, .maxYMargin]
        handle.frame = NSRect(
            x: max(0, root.bounds.width - side),
            y: 0,
            width: side,
            height: side
        )
        root.addSubview(handle) // keep on top after re-layout
        handle.needsDisplay = true
    }

    /// Place the panel under the status item; clamp to the screen.
    private func positionStatusPanel(_ panel: NSPanel, size: NSSize, under button: NSView) {
        guard let buttonWindow = button.window else {
            panel.setContentSize(size)
            return
        }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let gap: CGFloat = 5
        var origin = NSPoint(
            x: buttonRect.midX - size.width / 2,
            y: buttonRect.minY - size.height - gap
        )

        let screen = buttonWindow.screen ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 {
                origin.y = max(visible.minY + 8, origin.y)
            }
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if let root = panelRootView {
            layoutResizeHandle(in: root)
        }
    }

    /// Resize with **top-left fixed** so the panel grows down/right and never jumps.
    private func applyPanelSize(_ size: NSSize, persist: Bool) {
        guard let panel = statusPanel else { return }
        let w = SettingsStore.clampPanelWidth(Double(size.width))
        let h = SettingsStore.clampPanelHeight(Double(size.height))
        var frame = panel.frame
        let top = frame.maxY
        let left = frame.minX
        frame.size = NSSize(width: w, height: h)
        frame.origin.x = left
        frame.origin.y = top - frame.size.height
        panel.setFrame(frame, display: true, animate: false)
        if let root = panelRootView {
            layoutResizeHandle(in: root)
        }
        if persist {
            settings.panelWidth = w
            settings.panelHeight = h
        }
    }

    private func panelContentSize() -> NSSize {
        NSSize(
            width: SettingsStore.clampPanelWidth(settings.panelWidth),
            height: SettingsStore.clampPanelHeight(settings.panelHeight)
        )
    }

    private func closeStatusPanel() {
        removeDismissMonitor()
        statusPanel?.orderOut(nil)
        store.panelOpen = false
    }

    private func installDismissMonitor() {
        removeDismissMonitor()
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleOutsideMouseDown(event)
            }
        }
    }

    private func removeDismissMonitor() {
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
            self.dismissMonitor = nil
        }
    }

    private func handleOutsideMouseDown(_ event: NSEvent) {
        guard let panel = statusPanel, panel.isVisible else { return }
        let screenPoint = NSEvent.mouseLocation

        // Clicks on the status item toggle via the button action — don't double-close.
        if let button = statusItem?.button,
           let buttonWindow = button.window
        {
            let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonRect.contains(screenPoint) { return }
        }

        if !panel.frame.contains(screenPoint) {
            closeStatusPanel()
        }
    }

    func showContextMenu() {
        rebuildContextMenu()
        guard let button = statusItem?.button, let menu = contextMenu else { return }
        closeStatusPanel()

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
            tunnels: tunnels,
            onRibbonRefresh: { [weak self] in
                self?.refresh(force: true)
            }
        )
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
