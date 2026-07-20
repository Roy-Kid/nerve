import AppKit
import SwiftUI

// MARK: - MenuBarExtra right-click (Settings / Quit)

/// SwiftUI `MenuBarExtra` + `.window` style does **not** reliably deliver
/// `.contextMenu` on the label. Secondary-click is intercepted here with AppKit
/// so the ribbon still offers Settings… and Quit.
@MainActor
final class MenuBarExtraContextMenuBridge: NSObject {
    private let openSettings: () -> Void
    private var monitor: Any?
    private var menu: NSMenu?

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()
        rebuildMenu()
    }

    func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .leftMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.isRibbonStatusItemEvent(event) else { return event }

            let secondary =
                event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard secondary else { return event }

            self.popupMenu()
            // Swallow so MenuBarExtra does not open/toggle the status panel.
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsAction(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Nerve",
            action: #selector(quitAction(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
    }

    private func popupMenu() {
        guard let menu else { return }
        // Screen coordinates when `in:` is nil — sits under the cursor on the ribbon.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// MenuBarExtra’s status item lives in a private status-bar window owned by this process.
    private func isRibbonStatusItemEvent(_ event: NSEvent) -> Bool {
        if let window = event.window {
            let name = NSStringFromClass(type(of: window))
            if name.contains("StatusBar") || name.contains("StatusItem") {
                return true
            }
        }

        // Fallback: hit-test any of our short, menu-bar-level windows (the ribbon).
        let point = NSEvent.mouseLocation
        for window in NSApp.windows {
            let name = NSStringFromClass(type(of: window))
            let isStatusChrome =
                name.contains("StatusBar")
                || name.contains("StatusItem")
                || (window.level.rawValue >= NSWindow.Level.statusBar.rawValue
                    && window.frame.height <= 32
                    && window.frame.width <= 320
                    && window.isVisible)
            guard isStatusChrome, window.frame.contains(point) else { continue }
            return true
        }
        return false
    }

    @objc private func openSettingsAction(_ sender: Any?) {
        openSettings()
    }

    @objc private func quitAction(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

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
            c(map.running), c(map.success), c(map.inactive),
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

// MARK: - AppKit corner resize (reliable; SwiftUI gestures fail on nonactivating panels)

/// Bottom-trailing grip. Tracks mouse in screen space; grows window down/right.
private final class CornerResizeHandleView: NSView {
    /// `ended` is true on mouse-up so the host can persist size.
    var onResize: ((_ size: NSSize, _ ended: Bool) -> Void)?

    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        if #available(macOS 15.0, *) {
            addCursorRect(bounds, cursor: NSCursor.frameResize(position: .bottomRight, directions: .all))
        } else {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if #available(macOS 15.0, *) {
            NSCursor.frameResize(position: .bottomRight, directions: .all).set()
        } else {
            NSCursor.resizeLeftRight.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation

        // Classic AppKit tracking loop — works on nonactivating panels.
        while true {
            guard let tracked = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp]
            ) else { break }

            let now = NSEvent.mouseLocation
            // Screen coords: y increases upward. Drag down → grow height.
            let dx = now.x - startMouse.x
            let dy = startMouse.y - now.y
            let next = NSSize(
                width: SettingsStore.clampPanelWidth(Double(startFrame.width + dx)),
                height: SettingsStore.clampPanelHeight(Double(startFrame.height + dy))
            )
            let ended = tracked.type == .leftMouseUp
            onResize?(next, ended)
            if ended { break }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Ribbon renderer (NSImage for status item)

enum RibbonRenderer {
    static func preferredWidth(store: JobStore, settings: SettingsStore) -> CGFloat {
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
        store: JobStore,
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
        store: JobStore,
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
        segments: [JobStore.RibbonSegment],
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
