import SwiftUI
import AppKit

/// Short first-run coach. Can be skipped. Demo is optional at the end.
struct FirstRunCoachView: View {
    var onFinish: (_ loadDemo: Bool) -> Void

    @State private var page = 0

    private let pages: [(title: String, body: String)] = [
        (
            "All running signals, one place",
            "Nerve does not run your agents. It gathers status from tools that send events to it."
        ),
        (
            "The ribbon is the pulse",
            "Length follows how many subjects are active. Colors show attention, failure, and healthy work together."
        ),
        (
            "Left click for status",
            "Open Attention, Active, and Recent. Click a row to expand detail and actions."
        ),
        (
            "Right click for Preferences",
            "Customize status colors, notifications, quiet hours — then Quit. Nothing about subjects is written to disk."
        ),
        (
            "Connect a source",
            "POST snapshots and events to http://127.0.0.1:17890 — or POST /v1/demo to explore. State is memory-only."
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nerve")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Text(pages[page].title)
                .font(.system(size: 18, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(pages[page].body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(page + 1) of \(pages.count)")

            HStack {
                Button("Skip") {
                    onFinish(false)
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                if page < pages.count - 1 {
                    Button("Next") {
                        withAnimation(.easeInOut(duration: 0.15)) { page += 1 }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    Button("Start empty") {
                        onFinish(false)
                    }
                    .buttonStyle(.bordered)
                    Button("Load demo") {
                        onFinish(true)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(22)
        .frame(width: 380, height: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }
}

@MainActor
final class FirstRunCoachController {
    private var window: NSWindow?

    func show(onFinish: @escaping (_ loadDemo: Bool) -> Void) {
        let root = FirstRunCoachView { [weak self] loadDemo in
            self?.window?.close()
            self?.window = nil
            onFinish(loadDemo)
        }
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Nerve"
        window.titlebarAppearsTransparent = true
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
