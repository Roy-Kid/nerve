//! What this surface may do about a job.
//!
//! Which is very little, on purpose. CLAUDE.md invariant 6: Nerve never
//! reverse-controls an agent. There is no approve, no cancel, no submit_input
//! — a job's `actions` list is something to *classify*, never to perform.
//! Attention means "return to the agent UI", not "type here".
//!
//! So the whole verb list is: take me to where this is happening, or put the
//! location on the clipboard so I can get there myself.

pub mod clipboard;
pub mod open;
pub mod shell;

use clipboard::Clipboard;
use nerve_surface_core::frame::JobView;
use open::{plan, OpenPlan};
use shell::ShellOpener;

/// What happened, in words the surface can show.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Outcome {
    pub message: String,
    pub succeeded: bool,
}

/// Carry out whatever [`plan`] decided.
///
/// The plan is chosen without touching the OS and executed without deciding
/// anything, so the interesting half stays testable and this half stays dumb.
pub fn perform(
    job: &JobView,
    local_alias: Option<&str>,
    opener: &dyn ShellOpener,
    clipboard: &mut dyn Clipboard,
) -> Outcome {
    match plan(job, local_alias) {
        OpenPlan::Shell(url) => outcome(opener.open_url(&url), "Opened", "Nothing opened it"),
        OpenPlan::Reveal(path) => outcome(
            opener.open_path(std::path::Path::new(&path)),
            "Opened",
            "Could not open that folder",
        ),
        OpenPlan::Copy { text, reason } => {
            let copied = clipboard.set_text(&text);
            Outcome {
                succeeded: copied,
                message: if copied {
                    format!("Copied — {reason}")
                } else {
                    "Could not reach the clipboard".to_string()
                },
            }
        }
        OpenPlan::None(reason) => Outcome {
            message: reason.to_string(),
            succeeded: false,
        },
    }
}

/// Copy `"{name} — {summary}"`, the panel's own Copy button.
pub fn copy(job: &JobView, clipboard: &mut dyn Clipboard) -> Outcome {
    let text = open::copy_text(job);
    outcome(
        clipboard.set_text(&text),
        "Copied",
        "Could not reach the clipboard",
    )
}

fn outcome(ok: bool, good: &str, bad: &str) -> Outcome {
    Outcome {
        message: if ok { good } else { bad }.to_string(),
        succeeded: ok,
    }
}
