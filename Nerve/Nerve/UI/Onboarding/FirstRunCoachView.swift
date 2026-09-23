import AppKit
import SwiftUI

/// Short first-run coach. Can be skipped. Demo is optional at the end.
struct FirstRunCoachView: View {
    var onFinish: (_ loadDemo: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let pages: [(title: String, body: String, symbol: String)] = [
        (
            "All running signals, one place",
            "Nerve does not run your agents. It gathers status from tools that send events to it.",
            "waveform.path.ecg"
        ),
        (
            "The ribbon is the pulse",
            "Its length follows active work, while color reveals attention, failures, and healthy progress at a glance.",
            "capsule.fill"
        ),
        (
            "Status is one click away",
            "Open Attention, Active, and Recent work from the menu bar. Select any row for details, activity, and actions.",
            "list.bullet.rectangle.portrait.fill"
        ),
        (
            "Settings stay close by",
            "Right-click the ribbon to adjust status colors, notifications, and quiet hours, or to quit Nerve.",
            "gearshape.2.fill"
        ),
        (
            "Connect a local source",
            "Connect your agent, then start a conversation. Live status will appear automatically.",
            "point.3.connected.trianglepath.dotted"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)

                Text("Nerve")
                    .font(.headline)

                Spacer()

                Text("Welcome")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            ZStack {
                coachPage
                    .id(page)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if page == pages.count - 1 {
                AgentSetupGuide().padding(.horizontal, 20).padding(.bottom, 12)
            }
            pageIndicator
                .padding(.bottom, 18)

            Divider()

            controls
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
        }
        .frame(width: 480, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }

    private var coachPage: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.11))
                    .frame(width: 92, height: 92)

                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.14), lineWidth: 0.5)
                    .frame(width: 92, height: 92)

                Image(systemName: pages[page].symbol)
                    .font(.system(size: 39, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 8) {
                Text(pages[page].title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(pages[page].body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
            }
        }
        .padding(.horizontal, 28)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.22))
                    .frame(width: index == page ? 16 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page + 1) of \(pages.count)")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if page == 0 {
                Button("Skip") {
                    onFinish(false)
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderless)
            } else {
                Button("Back") {
                    changePage(to: page - 1)
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            if page < pages.count - 1 {
                Button("Continue") {
                    changePage(to: page + 1)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else {
                Button("Done") {
                    onFinish(false)
                }
                .buttonStyle(.bordered)

                Button("Try Demo") {
                    onFinish(true)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.regular)
    }

    private func changePage(to nextPage: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            page = min(max(0, nextPage), pages.count - 1)
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 590),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Nerve"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.appearance = nil
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

/// Uses the same installation commands as the product handbook.
struct AgentSetupGuide: View {
    @State private var agent = "Claude Code"
    @State private var copied = false

    private var commands: String {
        agent == "Claude Code"
            ? "/plugin marketplace add Roy-Kid/nerve\n/plugin install nerve@nerve"
            : "codex plugin marketplace add Roy-Kid/nerve\ncodex plugin add nerve@nerve"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Agent", selection: $agent) {
                Text("Claude Code").tag("Claude Code")
                Text("Codex").tag("Codex")
            }
            Text(agent == "Claude Code" ? "Run these commands in Claude Code:" : "Run these commands in your terminal:")
                .font(.caption)
            Text(commands).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Button(copied ? "Copied" : "Copy commands") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(commands, forType: .string)
                copied = true
            }
            Text("Restart your agent after installation, then send a prompt. The first conversation appears automatically.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 380)
        .onChange(of: agent) { _, _ in copied = false }
    }
}
