import SwiftUI
import AppKit

/// Resolves status → color. Defaults match product palette; live values come from `StatusColorMap`.
enum RibbonPalette {
    static func color(for status: RibbonStatus, scheme: ColorScheme, map: StatusColorMap = .default) -> Color {
        Color(nsColor: nsColor(for: status, dark: scheme == .dark, map: map))
    }

    static func nsColor(for status: RibbonStatus, dark: Bool, map: StatusColorMap = .default) -> NSColor {
        let base = map.color(for: status).nsColor
        // Slight lift on dark menu bars so custom colors still read as “lit glass”.
        guard dark else { return base }
        return base.blended(withFraction: 0.08, of: .white) ?? base
    }
}
