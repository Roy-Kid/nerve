import AppKit
import SwiftUI

// MARK: - AppKit corner resize (reliable; SwiftUI gestures fail on nonactivating panels)

/// Bottom-trailing grip. Tracks mouse in screen space; grows window down/right.
final class CornerResizeHandleView: NSView {
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
