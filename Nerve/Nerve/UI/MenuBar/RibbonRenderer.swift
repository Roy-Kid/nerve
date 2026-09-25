import AppKit
import NerveRibbonUI

// MARK: - Nerve job state → the shared continuous ribbon renderer

@MainActor
enum RibbonRenderer {
    static func preferredWidth(store: JobStore, settings: SettingsStore) -> CGFloat {
        let n = store.activeCount
        if n == 0 {
            let idle: CGFloat = (22 * settings.ribbonLengthScale).rounded()
            return settings.hideWhenIdle ? 0 : max(14, idle)
        }
        let factor = store.ribbonLengthFactor()
        let base: CGFloat = 28 + (100 - 28) * factor
        return min(120, max(16, base * CGFloat(settings.ribbonLengthScale))).rounded()
    }

    static func ambientRelevant(store: JobStore, settings: SettingsStore) -> Bool {
        let segments = store.ribbonSegments(mode: settings.panelGroupMode)
        guard !segments.isEmpty else { return false }
        switch settings.ribbonMotionStyle {
        case .transitionsOnly: return false
        case .breathe:
            return segments.contains { $0.status == .running || $0.status == .waiting || $0.status == .monitor }
        case .shimmer: return true
        case .statusPulse, .full:
            return segments.contains {
                switch $0.status {
                case .problem, .attention, .running, .waiting, .monitor: return true
                default: return false
                }
            }
        }
    }

    static func image(
        store: JobStore,
        settings: SettingsStore,
        width: CGFloat,
        height: CGFloat,
        appearance: NSAppearance,
        time: TimeInterval = 0,
        motion: RibbonMotionStyle = .transitionsOnly
    ) -> NSImage {
        NerveRibbonRenderer.image(
            segments: sharedSegments(store: store, settings: settings, time: time, motion: motion),
            width: width,
            height: height,
            thickness: CGFloat(settings.ribbonThickness),
            idleColor: hex(settings.statusColors.color(for: .inactive)),
            appearance: appearance,
            time: time,
            shimmer: motion == .shimmer || motion == .full)
    }

    static func draw(
        store: JobStore,
        settings: SettingsStore,
        in bounds: NSRect,
        isDark: Bool,
        time: TimeInterval = 0,
        motion: RibbonMotionStyle = .transitionsOnly
    ) {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua) ?? NSAppearance(named: .aqua)!
        image(
            store: store,
            settings: settings,
            width: bounds.width,
            height: bounds.height,
            appearance: appearance,
            time: time,
            motion: motion).draw(in: bounds)
    }

    private static func sharedSegments(
        store: JobStore,
        settings: SettingsStore,
        time: TimeInterval,
        motion: RibbonMotionStyle
    ) -> [NerveRibbonSegment] {
        store.ribbonSegments(mode: settings.panelGroupMode).map { segment in
            let rgb = settings.statusColors.color(for: segment.status)
            return NerveRibbonSegment(
                color: hex(rgb),
                weight: segment.weight,
                lift: pulseAmount(for: segment.status, motion: motion, time: time))
        }
    }

    private static func hex(_ color: RGBColor) -> UInt32 {
        let red = UInt32((color.r * 255).rounded())
        let green = UInt32((color.g * 255).rounded())
        let blue = UInt32((color.b * 255).rounded())
        return (red << 16) | (green << 8) | blue
    }

    private static func pulseAmount(
        for status: Status,
        motion: RibbonMotionStyle,
        time: TimeInterval
    ) -> CGFloat {
        func wave(period: TimeInterval, amplitude: CGFloat) -> CGFloat {
            guard period > 0 else { return 0 }
            let phase = (time.truncatingRemainder(dividingBy: period)) / period
            return amplitude * CGFloat((sin(phase * 2 * Double.pi - Double.pi / 2) + 1) / 2)
        }
        switch motion {
        case .transitionsOnly, .shimmer: return 0
        case .breathe:
            switch status {
            case .running, .waiting: return wave(period: 2.2, amplitude: 0.14)
            case .monitor: return wave(period: 2.8, amplitude: 0.10)
            default: return 0
            }
        case .statusPulse, .full:
            switch status {
            case .running, .waiting: return wave(period: 2.2, amplitude: 0.12)
            case .monitor: return wave(period: 2.8, amplitude: 0.10)
            case .attention: return wave(period: 1.4, amplitude: 0.16)
            case .problem: return wave(period: 0.9, amplitude: 0.18)
            default: return 0
            }
        }
    }
}
