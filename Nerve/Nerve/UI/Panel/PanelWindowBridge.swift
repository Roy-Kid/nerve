import AppKit
import SwiftUI

// MARK: - MenuBarExtra resize anchor

/// Holds the hosting `NSWindow` and a screen-space top-left pin for the duration
/// of a corner-drag resize. MenuBarExtra re-centers under the status item whenever
/// content size changes; re-applying the pin after layout keeps growth down/right.
@MainActor
final class PanelResizeAnchor {
    weak var window: NSWindow?
    /// Screen coordinates: x = minX, y = maxY (top edge).
    private var pinnedTopLeft: CGPoint?
    private(set) var isResizing = false

    func beginResize() {
        guard let window else { return }
        isResizing = true
        let frame = window.frame
        pinnedTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
    }

    func endResize() {
        isResizing = false
        pinnedTopLeft = nil
    }

    /// Resize window content to `contentSize` while keeping the captured top-left fixed.
    func pinTopLeft(contentSize: CGSize) {
        guard let window, isResizing else { return }
        let pin = pinnedTopLeft ?? CGPoint(x: window.frame.minX, y: window.frame.maxY)
        pinnedTopLeft = pin

        let contentRect = NSRect(
            x: pin.x,
            y: pin.y - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
        // Convert content rect → full window frame (title bar / shadow chrome).
        let frame = window.frameRect(forContentRect: contentRect)
        // Keep top-left of the *window* aligned with the original content top-left
        // when chrome differs; prefer the explicit content placement above.
        var placed = frame
        // frameRect(forContentRect:) already places correctly in screen space for
        // borderless MenuBarExtra windows; still force top edge in case of drift.
        let contentAfter = window.contentRect(forFrameRect: placed)
        let dy = pin.y - contentAfter.maxY
        let dx = pin.x - contentAfter.minX
        if abs(dx) > 0.5 || abs(dy) > 0.5 {
            placed.origin.x += dx
            placed.origin.y += dy
        }
        if placed != window.frame {
            window.setFrame(placed, display: true, animate: false)
        }
    }

    /// Called from the bridge view after AppKit layout — re-apply pin if the system moved us.
    func reassertPinIfNeeded() {
        guard isResizing, let window, let pin = pinnedTopLeft else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let dx = pin.x - content.minX
        let dy = pin.y - content.maxY
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }
        var frame = window.frame
        frame.origin.x += dx
        frame.origin.y += dy
        window.setFrame(frame, display: true, animate: false)
    }
}

/// Invisible NSView that discovers the MenuBarExtra host window and re-pins it
/// after each layout pass while a resize is active.
struct PanelWindowBridge: NSViewRepresentable {
    let anchor: PanelResizeAnchor

    func makeNSView(context: Context) -> PanelResizeBridgeView {
        let view = PanelResizeBridgeView()
        view.anchor = anchor
        return view
    }

    func updateNSView(_ nsView: PanelResizeBridgeView, context: Context) {
        nsView.anchor = anchor
        if let window = nsView.window {
            anchor.window = window
        }
    }
}

final class PanelResizeBridgeView: NSView {
    var anchor: PanelResizeAnchor?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        anchor?.window = window
    }

    override func layout() {
        super.layout()
        if let window {
            anchor?.window = window
        }
        // After MenuBarExtra reflows content size it recenters; pull origin back.
        anchor?.reassertPinIfNeeded()
    }

    /// Window-discovery only — never intercept clicks meant for SwiftUI controls.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
