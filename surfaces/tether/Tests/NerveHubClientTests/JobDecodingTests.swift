import Foundation
import Testing

@testable import NerveHubClient

private func decode(_ jobJSON: String) throws -> NerveJob {
  // The helper takes one bare job object; NerveFrame wants `{"jobs":[...]}`.
  let frameJSON = "{\"jobs\":[\(jobJSON)]}"
  let frame = try JSONDecoder().decode(NerveFrame.self, from: Data(frameJSON.utf8))
  return try #require(frame.jobs.first)
}

// ── (a) status words match the macOS ladder ─────────────────────────────────

@Test
func askReasonsGetTheMacOSSpecificWords() throws {
  for (reason, word) in [
    ("approval", "Approval needed"),
    ("permission", "Approval needed"),
    ("auth", "Approval needed"),
    ("input", "Input needed"),
    ("elicitation", "Input needed"),
    ("review", "Review needed"),
    ("decision", "Decision needed"),
  ] {
    let job = try decode(
      """
      {"id":"p:1","name":"proj","alias":"box","lifecycle":"active","health":"ok",
       "attention":{"level":"required","reason":"\(reason)","title":"x"},
       "current":{"type":"idle"}}
      """)
    #expect(job.status == .attention, "\(reason)")
    #expect(job.statusLabel == word, "\(reason) -> \(job.statusLabel)")
  }
}

@Test
func activeSuccessSaysTurnCompleteNotCompleted() throws {
  let job = try decode(
    """
    {"id":"p:1","name":"proj","alias":"box","lifecycle":"active","health":"ok",
     "attention":{"level":"none"},
     "current":{"type":"completed","summary":"Turn complete"}}
    """)
  #expect(job.status == .success)
  #expect(job.statusLabel == "Turn complete")
}

@Test
func endedSuccessSaysCompleted() throws {
  let job = try decode(
    """
    {"id":"p:1","name":"proj","alias":"box","lifecycle":"ended","health":"ok","outcome":"success",
     "attention":{"level":"none"},"current":{"type":"idle"}}
    """)
  #expect(job.status == .success)
  #expect(job.statusLabel == "Completed")
}

@Test
func idleStartingAndWaitingShareTheInactiveWords() throws {
  for (kind, status, word) in [
    ("starting", NerveStatus.inactive, "Ready / idle"),
    ("idle", NerveStatus.inactive, "Ready / idle"),
    ("waiting", NerveStatus.waiting, "Waiting"),
  ] {
    let job = try decode(
      """
      {"id":"p:1","name":"proj","alias":"box","lifecycle":"active","health":"ok",
       "attention":{"level":"none"},"current":{"type":"\(kind)"}}
      """)
    #expect(job.status == status, "\(kind)")
    #expect(job.statusLabel == word, "\(kind) -> \(job.statusLabel)")
  }
}

// ── (b) palette hexes match palette.rs ──────────────────────────────────────

@Test
func paletteHexesMatchTheRustSourceOfTruth() {
  // Pinned against `crates/nerve-surface-core/src/palette.rs:48-59`.
  #expect(NervePalette.problem == 0xFF3B30)
  #expect(NervePalette.attention == 0xFF9F0A)
  #expect(NervePalette.running == 0x0A84FF)
  #expect(NervePalette.monitor == 0xBF5AF2)
  #expect(NervePalette.success == 0x30D158)
  #expect(NervePalette.inactive == 0x8E8E93)
  // Waiting shares the chrome gray (`palette.rs:66-67`).
  #expect(NervePalette.waiting == NervePalette.inactive)

  #expect(NervePalette.hex(for: .problem) == NervePalette.problem)
  #expect(NervePalette.hex(for: .attention) == NervePalette.attention)
  #expect(NervePalette.hex(for: .waiting) == NervePalette.waiting)
  #expect(NervePalette.hex(for: .running) == NervePalette.running)
  #expect(NervePalette.hex(for: .monitor) == NervePalette.monitor)
  #expect(NervePalette.hex(for: .success) == NervePalette.success)
  #expect(NervePalette.hex(for: .inactive) == NervePalette.inactive)
}

// ── (c) Prompt block from extensions.lastPrompt ─────────────────────────────

@Test
func lastPromptIsDecodedAndNeverFallsBackToSummary() throws {
  let job = try decode(
    """
    {"id":"p:1","name":"proj","alias":"box","lifecycle":"active","health":"ok",
     "attention":{"level":"none"},
     "current":{"type":"thinking","summary":"fix the bug"},
     "extensions":{"lastPrompt":"what should I build?"}}
    """)
  #expect(job.lastPrompt == "what should I build?")
  #expect(job.summary == "fix the bug")
}

@Test
func missingLastPromptIsNil() throws {
  let job = try decode(
    """
    {"id":"p:1","name":"proj","alias":"box","lifecycle":"active","health":"ok",
     "attention":{"level":"none"},"current":{"type":"thinking"}}
    """)
  #expect(job.lastPrompt == nil)
}

// ── (d) model / agentType ride in as metadata ───────────────────────────────

@Test
func modelAndAgentTypeAreDecoded() throws {
  let job = try decode(
    """
    {"id":"p:1","name":"proj","alias":"box","lifecycle":"active","health":"ok",
     "attention":{"level":"none"},"current":{"type":"thinking"},
     "extensions":{"model":"claude-fable-5-1","agentType":"Explore"}}
    """)
  #expect(job.model == "claude-fable-5-1")
  #expect(job.agentType == "Explore")
  #expect(job.metadataCaption == "box · claude-fable-5-1")
}

@Test
func agentTypeIsTheFallbackWhenNoModel() throws {
  let job = try decode(
    """
    {"id":"p:1","name":"proj","alias":"box","lifecycle":"active","health":"ok",
     "attention":{"level":"none"},"current":{"type":"subagent"},
     "extensions":{"agentType":"Explore"}}
    """)
  #expect(job.metadataCaption == "box · Explore")
}

// ── (e) Open/Focus location fields ──────────────────────────────────────────

@Test
func openURLAndFocusHintAreDecoded() throws {
  let job = try decode(
    """
    {"id":"p:1","name":"proj","alias":"box","lifecycle":"active","health":"ok",
     "attention":{"level":"none"},"current":{"type":"thinking"},
     "location":{"openURL":"file:///tmp/p","focusHint":"Claude Code · proj · tmux"}}
    """)
  #expect(job.openURL == "file:///tmp/p")
  #expect(job.focusHint == "Claude Code · proj · tmux")
}

@Test
func locationIsOptional() throws {
  let job = try decode(
    """
    {"id":"p:1","name":"proj","alias":"box","lifecycle":"active","health":"ok",
     "attention":{"level":"none"},"current":{"type":"thinking"}}
    """)
  #expect(job.openURL == nil)
  #expect(job.focusHint == nil)
}

// ── busy-kind skip: a running tool never paints Attention ───────────────────

@Test
func runningToolDoesNotPaintAttention() throws {
  let job = try decode(
    """
    {"id":"p:1","name":"proj","alias":"box","lifecycle":"active","health":"ok",
     "attention":{"level":"suggested","reason":"input"},
     "current":{"type":"tool","name":"Bash","summary":"Using Bash"}}
    """)
  #expect(job.status == .running)
  #expect(job.isAsk == false)
}
