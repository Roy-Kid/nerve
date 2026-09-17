//! The interrupt channel.
//!
//! Attention and Ask are not the same thing, and conflating them is how a
//! status surface becomes a thing people mute. A job blocked on a lock, a
//! queue or a dependency paints orange because it needs a look — but nothing a
//! person does right now will move it, so it must never interrupt. A job
//! blocked on *a human* is the one that may.
//!
//! So: paint reads [`crate::status::StatusClass`]; interrupting reads this.
//!
//! Every surface dedupes locally on the same rule (CLAUDE.md invariant 7),
//! which is why the rule lives here and not in any one of them.

use crate::frame::{AttentionLevel, JobView};
use crate::status::is_ask_elevated;

/// Whether `next` has newly become worth interrupting for.
///
/// True on first sight of an elevated Ask, and on a level upgrade — so a job
/// that goes suggested → required says so again, while one that simply keeps
/// asking does not.
pub fn should_notify(previous: Option<&JobView>, next: &JobView) -> bool {
    if !is_ask_elevated(next) {
        return false;
    }
    let Some(previous) = previous else {
        return true;
    };
    if !is_ask_elevated(previous) {
        return true;
    }
    next.attention.level > previous.attention.level
}

/// What a notification says.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AskCopy {
    pub title: String,
    pub body: String,
}

/// Calm copy for an Ask.
///
/// The producer's own words win when it has any; the fallbacks are written to
/// be read at a glance and to say where to go, never to shout. "Your turn"
/// rather than "CRITICAL", because a surface that escalates everything teaches
/// people to ignore it.
pub fn copy(job: &JobView) -> AskCopy {
    let reason = job
        .attention
        .reason
        .as_deref()
        .unwrap_or("input")
        .trim()
        .to_ascii_lowercase();

    let fallback_title = match reason.as_str() {
        "approval" | "permission" | "auth" => format!("Approval needed: {}", job.name.trim()),
        "review" => format!("A review is waiting: {}", job.name.trim()),
        _ => format!("Your turn: {}", job.name.trim()),
    };

    let fallback_body = if job.attention.level >= AttentionLevel::Urgent {
        "Please return when you can — continue in the agent".to_string()
    } else {
        match reason.as_str() {
            "approval" | "permission" | "auth" => "Return to the agent to approve".to_string(),
            "review" => "Return to the agent when you are ready".to_string(),
            _ => "Ready when you are — return to the agent to continue".to_string(),
        }
    };

    let title = job
        .attention
        .title
        .as_deref()
        .map(str::trim)
        .filter(|t| !t.is_empty());
    let summary = job
        .attention
        .summary
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let current = job
        .current
        .as_ref()
        .and_then(|current| current.summary.as_deref())
        .map(str::trim)
        .filter(|s| !s.is_empty());

    AskCopy {
        title: title.map(str::to_string).unwrap_or(fallback_title),
        body: summary
            .or(current)
            .map(str::to_string)
            .unwrap_or(fallback_body),
    }
}
