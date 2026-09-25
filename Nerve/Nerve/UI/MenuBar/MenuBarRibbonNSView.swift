import AppKit
import SwiftUI

// MARK: - AppKit menu-bar ribbon (reliable redraw; SwiftUI Image/TimelineView stalls)

/// Hosts a continuously redrawn ribbon inside `MenuBarExtra`’s label slot.
/// Pure SwiftUI `Image` + `TimelineView` does not animate reliably in the menu bar.
struct MenuBarRibbonNSViewRepresentable: NSViewRepresentable {
    var store: JobStore
    var settings: SettingsStore

    func makeNSView(context: Context) -> MenuBarRibbonNSView {
        let view = MenuBarRibbonNSView(frame: NSRect(x: 0, y: 0, width: 40, height: 22))
        view.store = store
        view.settings = settings
        view.start()
        return view
    }

    func updateNSView(_ nsView: MenuBarRibbonNSView, context: Context) {
        nsView.store = store
        nsView.settings = settings
        nsView.kick()
    }
}

@MainActor
final class MenuBarRibbonNSView: NSView {
    var store: JobStore?
    var settings: SettingsStore?

    private var tickTimer: Timer?
    private var lastSignature: String = ""
    private var displayedWidth: CGFloat = 40

    private var animStart: Date?
    private var animFromWidth: CGFloat = 0
    private var animToWidth: CGFloat = 0
    private var animFromImage: NSImage?
    private var animToImage: NSImage?
    private var pendingTargetWidth: CGFloat = 0
    private var pendingTargetImage: NSImage?
    private var pendingTargetSignature: String = ""
    private var lastShownImage: NSImage?
    private let animDuration: TimeInterval = 0.32

    private var ambientEpoch = Date()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    isolated deinit {
        tickTimer?.invalidate()
    }

    func start() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        tick()
    }

    func kick() {
        tick()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(1, displayedWidth), height: 22)
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = lastShownImage else {
            NSColor.clear.setFill()
            bounds.fill()
            return
        }
        image.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func tick() {
        guard let store, let settings else { return }

        let appearance = effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let animate = settings.effectiveAnimationsEnabled
        let motion = animate ? settings.ribbonMotionStyle : .transitionsOnly
        let ambient =
            animate
            && motion.usesAmbientMotion
            && store.activeCount > 0
            && RibbonRenderer.ambientRelevant(store: store, settings: settings)

        let appearanceSig =
            appearance.bestMatch(from: [.darkAqua, .aqua])?.rawValue ?? "system"
        let contentSignature = [
            store.ribbonSignature(mode: settings.panelGroupMode),
            "len=\(settings.ribbonLengthScale)",
            "th=\(settings.ribbonThickness)",
            "hide=\(settings.hideWhenIdle)",
            "motion=\(settings.ribbonMotionStyle.rawValue)",
            "anim=\(animate)",
            "dark=\(isDark)",
            colorMapSignature(settings.statusColors),
            appearanceSig,
        ].joined(separator: "|")

        let targetWidth = RibbonRenderer.preferredWidth(store: store, settings: settings)
        let time = Date().timeIntervalSince(ambientEpoch)
        let targetImage: NSImage? = {
            guard targetWidth >= 1 else { return nil }
            return RibbonRenderer.image(
                store: store,
                settings: settings,
                width: targetWidth,
                height: 22,
                appearance: appearance,
                time: ambient ? time : 0,
                motion: ambient ? motion : .transitionsOnly
            )
        }()

        let contentChanged = contentSignature != lastSignature
            || abs(targetWidth - pendingTargetWidth) >= 0.5

        if contentChanged {
            lastSignature = contentSignature
            pendingTargetSignature = contentSignature
            pendingTargetWidth = targetWidth
            pendingTargetImage = targetImage

            if !animate || lastShownImage == nil {
                stopTransition(applyFinal: false)
                applySettled(width: targetWidth, image: targetImage)
            } else if animStart != nil, contentSignature == pendingTargetSignature {
                // retarget mid-flight below
                retargetTransition(toWidth: targetWidth, toImage: targetImage)
            } else {
                retargetTransition(toWidth: targetWidth, toImage: targetImage)
            }
        } else if ambient, animStart == nil {
            // Continuous ambient frames while settled.
            applySettled(width: targetWidth, image: targetImage)
        }

        if animStart != nil {
            stepTransition()
        }
    }

    private func retargetTransition(toWidth: CGFloat, toImage: NSImage?) {
        let fromW = animStart != nil ? currentAnimWidth() : displayedWidth
        let fromImg = lastShownImage
        animFromWidth = fromW
        animToWidth = toWidth
        animFromImage = fromImg
        animToImage = toImage
        pendingTargetWidth = toWidth
        pendingTargetImage = toImage
        animStart = Date()
        stepTransition()
    }

    private func currentAnimWidth() -> CGFloat {
        guard let start = animStart else { return displayedWidth }
        let t = easeInOut(min(1, max(0, Date().timeIntervalSince(start) / animDuration)))
        return animFromWidth + (animToWidth - animFromWidth) * CGFloat(t)
    }

    private func stepTransition() {
        guard let start = animStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        let linear = min(1, max(0, elapsed / animDuration))
        let t = easeInOut(linear)
        let width = animFromWidth + (animToWidth - animFromWidth) * CGFloat(t)
        let image = blend(from: animFromImage, to: animToImage, t: CGFloat(t), width: max(width, 1))
        applyFrame(width: width, image: image)
        if linear >= 1 {
            stopTransition(applyFinal: true)
        }
    }

    private func stopTransition(applyFinal: Bool) {
        animStart = nil
        animFromImage = nil
        animToImage = nil
        guard applyFinal else { return }
        applySettled(width: pendingTargetWidth, image: pendingTargetImage)
    }

    private func applySettled(width: CGFloat, image: NSImage?) {
        applyFrame(width: width, image: image)
    }

    private func applyFrame(width: CGFloat, image: NSImage?) {
        let w = max(width, width < 1 ? 0 : width)
        if abs(displayedWidth - w) > 0.01 {
            displayedWidth = w
            invalidateIntrinsicContentSize()
            // MenuBarExtra reads the view’s frame; keep it in sync with intrinsic size.
            var f = frame
            f.size = NSSize(width: max(1, w), height: 22)
            frame = f
        }
        lastShownImage = image
        needsDisplay = true
    }

    private func blend(from: NSImage?, to: NSImage?, t: CGFloat, width: CGFloat) -> NSImage? {
        let height: CGFloat = 22
        let size = NSSize(width: max(1, width), height: height)
        if t <= 0.001 { return scaled(from, to: size) ?? faded(to, alpha: 0.02, size: size) }
        if t >= 0.999 { return scaled(to, to: size) ?? faded(from, alpha: 0.02, size: size) }
        if from == nil { return faded(to, alpha: t, size: size) }
        if to == nil { return faded(from, alpha: 1 - t, size: size) }

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high
        let rect = NSRect(origin: .zero, size: size)
        from?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1 - t)
        to?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: t)
        return image
    }

    private func scaled(_ source: NSImage?, to size: NSSize) -> NSImage? {
        guard let source else { return nil }
        if abs(source.size.width - size.width) < 0.5,
           abs(source.size.height - size.height) < 0.5
        {
            return source
        }
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        source.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        return image
    }

    private func faded(_ source: NSImage?, alpha: CGFloat, size: NSSize) -> NSImage? {
        guard let source, alpha > 0.01 else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: min(1, max(0, alpha))
        )
        return image
    }

    private func easeInOut(_ t: TimeInterval) -> TimeInterval {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
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
}
