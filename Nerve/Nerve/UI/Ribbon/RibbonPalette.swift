import SwiftUI
import AppKit

/// Resolves status → color. Defaults match product palette; live values come from `StatusColorMap`.
enum RibbonPalette {
    static func color(for status: Status, scheme: ColorScheme, map: StatusColorMap = .default) -> Color {
        Color(nsColor: nsColor(for: status, dark: scheme == .dark, map: map))
    }

    static func nsColor(for status: Status, dark: Bool, map: StatusColorMap = .default) -> NSColor {
        let base = map.color(for: status).nsColor
        // A small lift keeps custom colors legible against dark menu bars.
        guard dark else { return base }
        return base.blended(withFraction: 0.04, of: .white) ?? base
    }
}
