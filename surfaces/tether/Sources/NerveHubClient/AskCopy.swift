import Foundation

/// Calm copy for an Ask, matching `nerve_surface_core::ask::copy`.
public enum AskCopy {
  public static func of(_ job: NerveJob) -> (title: String, body: String) {
    let reason = (job.attentionReason ?? "input").trimmingCharacters(in: .whitespaces)
      .lowercased()
    let title: String
    if let given = job.attentionTitle?.trimmingCharacters(in: .whitespaces), !given.isEmpty {
      title = given
    } else {
      switch reason {
      case "approval", "permission", "auth":
        title = "Approval needed: \(job.name)"
      case "review":
        title = "A review is waiting: \(job.name)"
      default:
        title = "Your turn: \(job.name)"
      }
    }
    let body = job.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (title, (body?.isEmpty == false) ? body! : "Return to the agent to continue")
  }
}
