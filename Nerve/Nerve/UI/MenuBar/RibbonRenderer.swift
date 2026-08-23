import AppKit
import SwiftUI

// MARK: - Ribbon renderer (NSImage / direct draw for status item)

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
        // Cap matches ~100pt base × 4.0 scale (Appearance max 400%).
        return min(400, max(16, scaled)).rounded()
    }

    /// Whether ambient motion has anything to paint for the current segments.
    static func ambientRelevant(store: JobStore, settings: SettingsStore) -> Bool {
        let segments = store.ribbonSegments(mode: settings.panelGroupMode)
        guard !segments.isEmpty else { return false }
        switch settings.ribbonMotionStyle {
        case .transitionsOnly:
            return false
        case .breathe:
            return segments.contains { $0.status == .running || $0.status == .waiting }
        case .shimmer:
            return true
        case .statusPulse, .full:
            return segments.contains {
                switch $0.status {
                case .problem, .attention, .running, .waiting: return true
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
                isDark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
                time: time,
                motion: motion
            )
        }
        return image
    }

    static func draw(
        store: JobStore,
        settings: SettingsStore,
        in bounds: NSRect,
        isDark: Bool,
        time: TimeInterval = 0,
        motion: RibbonMotionStyle = .transitionsOnly
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
        if let body = smoothStatusGradient(
            segments: segments,
            isDark: isDark,
            map: map,
            time: time,
            motion: motion
        ) {
            body.draw(in: barRect, angle: 0)
        } else {
            let idle = RibbonPalette.nsColor(for: .inactive, dark: isDark, map: map)
            idle.withAlphaComponent(0.55).setFill()
            barRect.fill()
        }

        if motion == .shimmer || motion == .full {
            drawShimmer(in: barRect, time: time, isDark: isDark)
        }

        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.withAlphaComponent(isDark ? 0.45 : 0.30).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private static func drawShimmer(in barRect: NSRect, time: TimeInterval, isDark: Bool) {
        let period: TimeInterval = 1.8
        let cycle = (time.truncatingRemainder(dividingBy: period)) / period
        // Highlight center walks fully across and off either end.
        let travel = barRect.width + barRect.width * 0.6
        let centerX = barRect.minX - barRect.width * 0.3 + CGFloat(cycle) * travel
        // Original wider glint (~48% of bar), soft veil over color.
        let half = max(10, barRect.width * 0.24)
        let peakAlpha: CGFloat = isDark ? 0.20 : 0.14
        let peak = NSColor.white.withAlphaComponent(peakAlpha)
        let mid = NSColor.white.withAlphaComponent(peakAlpha * 0.4)
        let clear = NSColor.white.withAlphaComponent(0)
        guard let gradient = NSGradient(colorsAndLocations:
            (clear, 0),
            (mid, 0.32),
            (peak, 0.5),
            (mid, 0.68),
            (clear, 1)
        ) else { return }
        let shine = NSRect(
            x: centerX - half,
            y: barRect.minY,
            width: half * 2,
            height: barRect.height
        )
        gradient.draw(in: shine, angle: 0)
    }

    /// Builds a multi-stop gradient: pure color plateaus + short smooth ramps between statuses.
    private static func smoothStatusGradient(
        segments: [JobStore.RibbonSegment],
        isDark: Bool,
        map: StatusColorMap,
        time: TimeInterval,
        motion: RibbonMotionStyle
    ) -> NSGradient? {
        guard !segments.isEmpty else { return nil }

        func resolved(_ status: Status) -> NSColor {
            let base = RibbonPalette.nsColor(for: status, dark: isDark, map: map)
            let lifted = base.blended(withFraction: isDark ? 0.04 : 0, of: .white) ?? base
            let pulse = pulseAmount(for: status, motion: motion, time: time)
            guard pulse > 0.001 else { return lifted }
            // Cap white mix so breathe/pulse never bleach the whole segment.
            return lifted.blended(withFraction: min(0.16, pulse), of: .white) ?? lifted
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

    /// 0…1 brightness lift toward white. Keep amplitudes low — high values bleach the bar.
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
        case .transitionsOnly, .shimmer:
            return 0
        case .breathe:
            switch status {
            case .running, .waiting:
                return wave(period: 2.2, amplitude: 0.14)
            default:
                return 0
            }
        case .statusPulse, .full:
            switch status {
            case .running, .waiting:
                return wave(period: 2.2, amplitude: 0.12)
            case .attention:
                return wave(period: 1.4, amplitude: 0.16)
            case .problem:
                return wave(period: 0.9, amplitude: 0.18)
            default:
                return 0
            }
        }
    }
}
