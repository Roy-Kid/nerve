import Foundation
import CoreGraphics
import AppKit
import SwiftUI

// MARK: - Status colors

/// sRGB triple 0…1, persisted with preferences (not subject data).
struct RGBColor: Codable, Equatable, Sendable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }

    init(r: Double, g: Double, b: Double) {
        self.r = min(1, max(0, r))
        self.g = min(1, max(0, g))
        self.b = min(1, max(0, b))
    }

    init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        c.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        self.init(r: Double(rr), g: Double(gg), b: Double(bb))
    }

    init(_ color: Color) {
        self.init(NSColor(color))
    }
}

/// User-customizable mapping from ribbon status → color. Defaults follow macOS system colors.
struct StatusColorMap: Codable, Equatable, Sendable {
    var problem: RGBColor
    var attention: RGBColor
    var waiting: RGBColor
    var running: RGBColor
    var success: RGBColor
    var inactive: RGBColor

    static let `default` = StatusColorMap(
        problem: RGBColor(r: 1.000, g: 0.231, b: 0.188),
        attention: RGBColor(r: 1.000, g: 0.584, b: 0.000),
        waiting: RGBColor(r: 0.686, g: 0.321, b: 0.871),
        running: RGBColor(r: 0.000, g: 0.478, b: 1.000),
        success: RGBColor(r: 0.204, g: 0.780, b: 0.349),
        inactive: RGBColor(r: 0.557, g: 0.557, b: 0.576)
    )

    /// The first-release palette, retained only to migrate untouched defaults.
    static let legacyDefault = StatusColorMap(
        problem: RGBColor(r: 0.95, g: 0.14, b: 0.18),
        attention: RGBColor(r: 1.00, g: 0.52, b: 0.10),
        waiting: RGBColor(r: 0.55, g: 0.28, b: 0.92),
        running: RGBColor(r: 0.14, g: 0.52, b: 0.98),
        success: RGBColor(r: 0.08, g: 0.80, b: 0.34),
        inactive: RGBColor(r: 0.48, g: 0.52, b: 0.58)
    )

    func color(for status: RibbonStatus) -> RGBColor {
        switch status {
        case .problem: return problem
        case .attention: return attention
        case .waiting: return waiting
        case .running: return running
        case .success: return success
        case .inactive: return inactive
        }
    }

    mutating func set(_ color: RGBColor, for status: RibbonStatus) {
        switch status {
        case .problem: problem = color
        case .attention: attention = color
        case .waiting: waiting = color
        case .running: running = color
        case .success: success = color
        case .inactive: inactive = color
        }
    }

    var isDefault: Bool { self == .default }
}

// MARK: - Settings

@Observable
final class SettingsStore {
    /// Fired after any preference that affects the menu-bar ribbon image/length.
    /// Set by AppModel so grouping / size / color changes redraw immediately
    /// without depending on a particular SwiftUI view still being alive.
    var ribbonAppearanceSink: (() -> Void)?

    var hideWhenIdle: Bool {
        didSet {
            persist()
            notifyRibbonAppearance()
        }
    }
    var reduceMotion: Bool { didSet { persist() } }
    var animationsEnabled: Bool { didSet { persist() } }
    var ingestPort: UInt16 { didSet { persist() } }

    /// Per-status ribbon / panel colors.
    var statusColors: StatusColorMap {
        didSet {
            persist()
            notifyRibbonAppearance()
        }
    }

    var notificationsPaused: Bool { didSet { persist() } }
    var notifyRequired: Bool { didSet { persist() } }
    var notifyUrgent: Bool { didSet { persist() } }
    var notifyFailure: Bool { didSet { persist() } }
    var notifyUnresponsive: Bool { didSet { persist() } }
    var notifyLongSuccess: Bool { didSet { persist() } }
    var notificationSoundEnabled: Bool { didSet { persist() } }
    var longTaskSuccessThresholdSeconds: TimeInterval { didSet { persist() } }
    var mutedSourceIds: Set<String> { didSet { persist() } }
    var mutedProjectIds: Set<String> { didSet { persist() } }

    /// Do-not-disturb schedule (local calendar minutes from midnight).
    var dndEnabled: Bool { didSet { persist() } }
    var dndStartMinutes: Int { didSet { persist() } }
    var dndEndMinutes: Int { didSet { persist() } }

    var hasCompletedFirstRun: Bool { didSet { persist() } }
    var hasSeenCoachMarks: Bool { didSet { persist() } }
    /// Status panel section grouping (priority / status / source).
    /// Also drives how the menu-bar ribbon is segmented and ordered.
    var panelGroupMode: PanelGroupMode {
        didSet {
            persist()
            notifyRibbonAppearance()
        }
    }

    /// Horizontal length scale for the menu-bar ribbon (0.5…2.0, default 1.0).
    var ribbonLengthScale: Double {
        didSet {
            let clamped = Self.clampRibbonLengthScale(ribbonLengthScale)
            if ribbonLengthScale != clamped {
                ribbonLengthScale = clamped
                return
            }
            persist()
            notifyRibbonAppearance()
        }
    }
    /// Vertical thickness of the ribbon bar in points (3…12, default 6).
    var ribbonThickness: Double {
        didSet {
            let clamped = Self.clampRibbonThickness(ribbonThickness)
            if ribbonThickness != clamped {
                ribbonThickness = clamped
                return
            }
            persist()
            notifyRibbonAppearance()
        }
    }

    private let defaults = UserDefaults.standard
    private let key = "nerve.settings.v4"
    private var isLoading = true

    private func notifyRibbonAppearance() {
        guard !isLoading else { return }
        if Thread.isMainThread {
            ribbonAppearanceSink?()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.ribbonAppearanceSink?()
            }
        }
    }

    static let defaultRibbonLengthScale: Double = 1.0
    static let defaultRibbonThickness: Double = 6.0
    static let ribbonLengthScaleRange: ClosedRange<Double> = 0.5...2.0
    static let ribbonThicknessRange: ClosedRange<Double> = 3...12

    static func clampRibbonLengthScale(_ v: Double) -> Double {
        min(ribbonLengthScaleRange.upperBound, max(ribbonLengthScaleRange.lowerBound, v))
    }

    static func clampRibbonThickness(_ v: Double) -> Double {
        min(ribbonThicknessRange.upperBound, max(ribbonThicknessRange.lowerBound, v))
    }

    init() {
        hideWhenIdle = false
        reduceMotion = false
        animationsEnabled = true
        ingestPort = 17890
        statusColors = .default
        notificationsPaused = false
        notifyRequired = true
        notifyUrgent = true
        notifyFailure = true
        notifyUnresponsive = true
        notifyLongSuccess = true
        notificationSoundEnabled = true
        longTaskSuccessThresholdSeconds = 300
        mutedSourceIds = []
        mutedProjectIds = []
        dndEnabled = false
        dndStartMinutes = 22 * 60
        dndEndMinutes = 8 * 60
        hasCompletedFirstRun = false
        hasSeenCoachMarks = false
        panelGroupMode = .priority
        ribbonLengthScale = Self.defaultRibbonLengthScale
        ribbonThickness = Self.defaultRibbonThickness

        if let data = UserDefaults.standard.data(forKey: key),
           let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            apply(p)
        } else if let data = UserDefaults.standard.data(forKey: "nerve.settings.v3"),
                  let p = try? JSONDecoder().decode(PersistedV3.self, from: data) {
            applyV3(p)
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            reduceMotion = true
        }

        isLoading = false
        persist()
    }

    private func apply(_ p: Persisted) {
        hideWhenIdle = p.hideWhenIdle
        reduceMotion = p.reduceMotion
        animationsEnabled = p.animationsEnabled
        ingestPort = p.ingestPort
        let savedColors = p.statusColors ?? .default
        statusColors = savedColors == .legacyDefault ? .default : savedColors
        notificationsPaused = p.notificationsPaused
        notifyRequired = p.notifyRequired
        notifyUrgent = p.notifyUrgent
        notifyFailure = p.notifyFailure
        notifyUnresponsive = p.notifyUnresponsive
        notifyLongSuccess = p.notifyLongSuccess
        notificationSoundEnabled = p.notificationSoundEnabled
        longTaskSuccessThresholdSeconds = p.longTaskSuccessThresholdSeconds
        mutedSourceIds = Set(p.mutedSourceIds)
        mutedProjectIds = Set(p.mutedProjectIds)
        dndEnabled = p.dndEnabled
        dndStartMinutes = p.dndStartMinutes
        dndEndMinutes = p.dndEndMinutes
        hasCompletedFirstRun = p.hasCompletedFirstRun
        hasSeenCoachMarks = p.hasSeenCoachMarks
        panelGroupMode = p.panelGroupMode ?? .priority
        ribbonLengthScale = Self.clampRibbonLengthScale(p.ribbonLengthScale ?? Self.defaultRibbonLengthScale)
        ribbonThickness = Self.clampRibbonThickness(p.ribbonThickness ?? Self.defaultRibbonThickness)
    }

    private func applyV3(_ p: PersistedV3) {
        hideWhenIdle = p.hideWhenIdle
        reduceMotion = p.reduceMotion
        animationsEnabled = p.animationsEnabled
        ingestPort = p.ingestPort
        notificationsPaused = p.notificationsPaused
        notifyRequired = p.notifyRequired
        notifyUrgent = p.notifyUrgent
        notifyFailure = p.notifyFailure
        notifyUnresponsive = p.notifyUnresponsive
        notifyLongSuccess = p.notifyLongSuccess
        notificationSoundEnabled = p.notificationSoundEnabled
        longTaskSuccessThresholdSeconds = p.longTaskSuccessThresholdSeconds
        mutedSourceIds = Set(p.mutedSourceIds)
        mutedProjectIds = Set(p.mutedProjectIds)
        dndEnabled = p.dndEnabled
        dndStartMinutes = p.dndStartMinutes
        dndEndMinutes = p.dndEndMinutes
        hasCompletedFirstRun = p.hasCompletedFirstRun
        hasSeenCoachMarks = p.hasSeenCoachMarks
        panelGroupMode = p.panelGroupMode ?? .priority
        ribbonLengthScale = Self.defaultRibbonLengthScale
        ribbonThickness = Self.defaultRibbonThickness
        // Privacy/storage flags intentionally dropped — subjects are memory-only.
    }

    func resetStatusColors() {
        statusColors = .default
    }

    /// True when notifications are allowed right now.
    func shouldDeliverNotifications(at date: Date = Date()) -> Bool {
        if notificationsPaused { return false }
        if !dndEnabled { return true }
        return !isInDND(at: date)
    }

    func isInDND(at date: Date = Date()) -> Bool {
        guard dndEnabled else { return false }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let mins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = dndStartMinutes
        let end = dndEndMinutes
        if start == end { return true }
        if start < end {
            return mins >= start && mins < end
        }
        return mins >= start || mins < end
    }

    var dndStartLabel: String { Self.formatMinutes(dndStartMinutes) }
    var dndEndLabel: String { Self.formatMinutes(dndEndMinutes) }

    static func formatMinutes(_ m: Int) -> String {
        let clamped = ((m % (24 * 60)) + (24 * 60)) % (24 * 60)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    func cycleDNDStart() {
        let options = [21 * 60, 22 * 60, 23 * 60, 0]
        if let idx = options.firstIndex(of: dndStartMinutes) {
            dndStartMinutes = options[(idx + 1) % options.count]
        } else {
            dndStartMinutes = 22 * 60
        }
    }

    func cycleDNDEnd() {
        let options = [6 * 60, 7 * 60, 8 * 60, 9 * 60]
        if let idx = options.firstIndex(of: dndEndMinutes) {
            dndEndMinutes = options[(idx + 1) % options.count]
        } else {
            dndEndMinutes = 8 * 60
        }
    }

    func toggleMute(sourceId: String) {
        if mutedSourceIds.contains(sourceId) { mutedSourceIds.remove(sourceId) }
        else { mutedSourceIds.insert(sourceId) }
    }

    func toggleMuteProject(_ project: String) {
        if mutedProjectIds.contains(project) { mutedProjectIds.remove(project) }
        else { mutedProjectIds.insert(project) }
    }

    var effectiveAnimationsEnabled: Bool {
        animationsEnabled && !reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func persist() {
        guard !isLoading else { return }
        let value = Persisted(
            hideWhenIdle: hideWhenIdle,
            reduceMotion: reduceMotion,
            animationsEnabled: animationsEnabled,
            ingestPort: ingestPort,
            statusColors: statusColors,
            notificationsPaused: notificationsPaused,
            notifyRequired: notifyRequired,
            notifyUrgent: notifyUrgent,
            notifyFailure: notifyFailure,
            notifyUnresponsive: notifyUnresponsive,
            notifyLongSuccess: notifyLongSuccess,
            notificationSoundEnabled: notificationSoundEnabled,
            longTaskSuccessThresholdSeconds: longTaskSuccessThresholdSeconds,
            mutedSourceIds: Array(mutedSourceIds).sorted(),
            mutedProjectIds: Array(mutedProjectIds).sorted(),
            dndEnabled: dndEnabled,
            dndStartMinutes: dndStartMinutes,
            dndEndMinutes: dndEndMinutes,
            hasCompletedFirstRun: hasCompletedFirstRun,
            hasSeenCoachMarks: hasSeenCoachMarks,
            panelGroupMode: panelGroupMode,
            ribbonLengthScale: ribbonLengthScale,
            ribbonThickness: ribbonThickness
        )
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private struct Persisted: Codable {
        var hideWhenIdle: Bool
        var reduceMotion: Bool
        var animationsEnabled: Bool
        var ingestPort: UInt16
        var statusColors: StatusColorMap?
        var notificationsPaused: Bool
        var notifyRequired: Bool
        var notifyUrgent: Bool
        var notifyFailure: Bool
        var notifyUnresponsive: Bool
        var notifyLongSuccess: Bool
        var notificationSoundEnabled: Bool
        var longTaskSuccessThresholdSeconds: TimeInterval
        var mutedSourceIds: [String]
        var mutedProjectIds: [String]
        var dndEnabled: Bool
        var dndStartMinutes: Int
        var dndEndMinutes: Int
        var hasCompletedFirstRun: Bool
        var hasSeenCoachMarks: Bool
        var panelGroupMode: PanelGroupMode?
        var ribbonLengthScale: Double?
        var ribbonThickness: Double?
    }

    /// Subset of v3 prefs we still care about (storage/privacy fields ignored).
    private struct PersistedV3: Codable {
        var hideWhenIdle: Bool
        var reduceMotion: Bool
        var animationsEnabled: Bool
        var ingestPort: UInt16
        var notificationsPaused: Bool
        var notifyRequired: Bool
        var notifyUrgent: Bool
        var notifyFailure: Bool
        var notifyUnresponsive: Bool
        var notifyLongSuccess: Bool
        var notificationSoundEnabled: Bool
        var longTaskSuccessThresholdSeconds: TimeInterval
        var mutedSourceIds: [String]
        var mutedProjectIds: [String]
        var dndEnabled: Bool
        var dndStartMinutes: Int
        var dndEndMinutes: Int
        var hasCompletedFirstRun: Bool
        var hasSeenCoachMarks: Bool
        var panelGroupMode: PanelGroupMode?
    }
}
