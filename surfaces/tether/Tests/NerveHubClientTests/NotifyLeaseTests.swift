import Foundation
import Testing

@testable import NerveHubClient

@Test
func missingNotifyMeansEveryoneMayFire() throws {
  let frame = try JSONDecoder().decode(
    NerveFrame.self, from: Data(#"{"jobs":[]}"#.utf8))
  #expect(frame.notify == .legacy)
  #expect(frame.notify.mayInterrupt(surface: "tether"))
  #expect(frame.notify.mayInterrupt(surface: "macos"))
}

@Test
func singleOwnerGatesTether() throws {
  let raw = """
    {"jobs":[],"notify":{"policy":"single","owner":"macos","surfaces":["macos","tether"],"watchers":2}}
    """
  let frame = try JSONDecoder().decode(NerveFrame.self, from: Data(raw.utf8))
  #expect(frame.notify.mayInterrupt(surface: "macos"))
  #expect(!frame.notify.mayInterrupt(surface: "tether"))
}

@Test
func hubSearchPrefersNerveAppBundle() {
  let paths = HubProcess.searchDirectories().map(\.path)
  #expect(paths.first == "/Applications/Nerve.app/Contents/MacOS")
}

@Test
func hubSearchIncludesCompileTimeCheckout() {
  let paths = HubProcess.compileTimeCheckoutDirectories().map(\.path)
  #expect(paths.contains { $0.hasSuffix("/target/release") })
  #expect(paths.contains { $0.hasSuffix("/target/debug") })
}

@Test
func jobAskUsesStructuredReason() throws {
  let raw = """
    {"id":"a","name":"nerve","alias":"lab","lifecycle":"active",
     "attention":{"level":"required","reason":"input"}}
    """
  let job = try JSONDecoder().decode(NerveJob.self, from: Data(raw.utf8))
  #expect(job.isAsk)
}

@Test
func jobProgressReadsCurrentSummary() throws {
  let raw = """
    {"id":"grok:1","name":"nerve","alias":"lab","lifecycle":"active",
     "current":{"type":"tool","name":"Bash","summary":"Using Bash"}}
    """
  let job = try JSONDecoder().decode(NerveJob.self, from: Data(raw.utf8))
  #expect(job.currentType == "tool")
  #expect(job.currentName == "Bash")
  #expect(job.progress == "Using Bash")
}

@Test
func jobsListIsABareArray() throws {
  let jobs = try JSONDecoder().decode(
    [NerveJob].self, from: Data(#"[{"id":"a","current":{"type":"thinking","summary":"New prompt"}}]"#.utf8))
  #expect(jobs.count == 1)
  #expect(jobs[0].progress == "New prompt")
}
