//! The six-state display derivation, mirrored from Swift.
//!
//! The hub deliberately publishes no derived `status`
//! (`crates/nerve-hub/src/model/job.rs:4`) — it stores facets, surfaces paint
//! them — so this transcription of `Nerve/Nerve/Models/Subject.swift:38-100` is
//! the only path to a class, and `tests/status.rs` pins it line by line.
//!
//! Derivation reads structured facets only. No free text ever classifies
//! (CLAUDE.md invariant 3): a `current.summary` of "build failed!!" on a
//! healthy job is a running job with a dramatic summary.

use crate::frame::{AttentionLevel, Health, JobView, Lifecycle, Outcome};

/// `Subject.swift:46-47` — the job is blocked on something else.
///
/// `failure` is a *wait* reason: the job is blocked on a dependency that
/// failed. `outcome` is what says the job itself failed.
const WAIT_REASONS: [&str; 9] = [
    "resource",
    "dependency",
    "queue",
    "system",
    "lock",
    "throttle",
    "rate",
    "capacity",
    "failure",
];

/// `Subject.swift:58` — the job is blocked on a human.
const ASK_REASONS: [&str; 6] = [
    "input",
    "approval",
    "auth",
    "permission",
    "decision",
    "elicitation",
];

/// `Subject.swift:82` — the job is doing work of its own.
const BUSY_KINDS: [&str; 4] = ["subagent", "tool", "thinking", "info"];

/// `Subject.swift:92` — open, but no turn of its own under way.
const IDLE_KINDS: [&str; 3] = ["idle", "starting", "booting"];

/// Derived display status.
///
/// Variants are declared in priority order, so the derived `Ord` *is* the
/// priority (`CoreTypes.swift:244-267`):
/// problem > attention > waiting > running > success > inactive.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum StatusClass {
    Problem,
    Attention,
    Waiting,
    Running,
    Success,
    Inactive,
}

impl StatusClass {
    /// Every class, most urgent first.
    pub const ALL: [StatusClass; 6] = [
        Self::Problem,
        Self::Attention,
        Self::Waiting,
        Self::Running,
        Self::Success,
        Self::Inactive,
    ];

    /// Lower-case spelling, equal to Swift's `Status.rawValue`.
    pub fn label(self) -> &'static str {
        match self {
            Self::Problem => "problem",
            Self::Attention => "attention",
            Self::Waiting => "waiting",
            Self::Running => "running",
            Self::Success => "success",
            Self::Inactive => "inactive",
        }
    }

    /// The one derivation, ported line for line from `Subject.swift:38-100`.
    ///
    /// The `:NN` comments are that file's line numbers. The three helpers below
    /// are its three `switch`/branch groups — the same grouping `tests/status.rs`
    /// pins section by section — and each answers `None` for exactly the cases
    /// Swift falls through on.
    pub fn of(job: &JobView) -> Self {
        // :39 / :40
        if job.outcome == Some(Outcome::Failure) {
            return Self::Problem;
        }
        if job.health == Health::Unresponsive {
            return Self::Problem;
        }

        if let Some(class) = Self::from_attention(job) {
            return class;
        }
        if let Some(class) = Self::from_stage(job) {
            return class;
        }
        if let Some(class) = Self::from_activity(job) {
            return class;
        }

        // :98 / :99
        if job.lifecycle == Lifecycle::Active {
            Self::Running
        } else {
            Self::Inactive
        }
    }

    /// `Subject.swift:43-66` — what the job is asking of a human.
    fn from_attention(job: &JobView) -> Option<Self> {
        // :43 — elevated attention is attention or waiting, never running.
        if job.attention.level >= AttentionLevel::Suggested {
            let Some(reason) = Self::reason(job) else {
                return Some(Self::Attention); // :53
            };
            return Some(if names(reason, &WAIT_REASONS) {
                Self::Waiting // :46
            } else {
                Self::Attention // :49
            });
        }

        // :56 — informational needs a reason to say anything at all.
        if job.attention.level >= AttentionLevel::Informational {
            let reason = Self::reason(job)?;
            if names(reason, &ASK_REASONS) {
                return Some(Self::Attention); // :58
            }
            if names(reason, &WAIT_REASONS) {
                return Some(Self::Waiting); // :60
            }
        }
        // :64 — anything else falls through to the stage ladder.
        None
    }

    /// `Subject.swift:68-79` — the stage the job as a whole is in.
    fn from_stage(job: &JobView) -> Option<Self> {
        // :68
        if job.lifecycle == Lifecycle::Ended {
            return Some(
                if matches!(job.outcome, Some(Outcome::Success | Outcome::Partial)) {
                    Self::Success // :69
                } else {
                    Self::Inactive // :70
                },
            );
        }
        // :72 / :73 / :74
        if matches!(job.lifecycle, Lifecycle::Suspended | Lifecycle::Unknown) {
            return Some(Self::Inactive);
        }
        if matches!(job.lifecycle, Lifecycle::Pending | Lifecycle::Created) {
            return Some(Self::Waiting);
        }
        if job.health == Health::Degraded {
            return Some(Self::Waiting);
        }

        // :77 — open session, partial outcome: a monitor waiting for feedback.
        if job.lifecycle == Lifecycle::Active && job.outcome == Some(Outcome::Partial) {
            return Some(Self::Success);
        }
        None
    }

    /// `Subject.swift:81-96` — what the job is doing right now.
    ///
    /// `current.type` is producer vocabulary, not an enum: a spelling this
    /// table never heard of decides nothing (`:94`).
    fn from_activity(job: &JobView) -> Option<Self> {
        let kind = job.current.as_ref()?.kind.as_str();
        // :82 — shell / subagent still running is Running, never Attention.
        if names(kind, &BUSY_KINDS) {
            // :84
            return (job.lifecycle == Lifecycle::Active).then_some(Self::Running);
        }
        // :86 — phase complete, waiting on stream feedback.
        if names(kind, &["monitor"]) {
            return Some(Self::Success);
        }
        if names(kind, &["waiting"]) {
            return Some(Self::Waiting); // :88
        }
        // :92 — `starting` is Ready (open, no turn yet); never Running.
        if names(kind, &IDLE_KINDS) {
            return Some(Self::Inactive);
        }
        None
    }

    /// `Subject.swift:44` / `:56` — the reason, as the producer spelled it.
    ///
    /// Not lower-cased here: matching is case-insensitive
    /// ([`names`]), and this runs once per job per repaint — the sidebar
    /// derives a class for the filter bar, the section list and every row.
    fn reason(job: &JobView) -> Option<&str> {
        job.attention.reason.as_deref()
    }
}

/// Whether producer vocabulary `value` is one of `set`, ignoring case.
///
/// The tables are ASCII, so this is the whole of "lower-case it and compare"
/// without the allocation that phrasing implies.
fn names(value: &str, set: &[&str]) -> bool {
    let value = value.trim();
    set.iter().any(|known| known.eq_ignore_ascii_case(value))
}
