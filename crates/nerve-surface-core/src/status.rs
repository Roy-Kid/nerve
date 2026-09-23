//! Shared structured display derivation. Completion, human attention and system waits
//! are distinct; prose never determines status. Mirrored by Swift and TypeScript.

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

/// `Subject.swift` — the job is blocked on a human (interruptible Ask channel).
const ASK_REASONS: [&str; 7] = [
    "input",
    "approval",
    "auth",
    "permission",
    "decision",
    "elicitation",
    "review",
];

/// `Subject.swift:82` — the job is doing work of its own.
const BUSY_KINDS: [&str; 4] = ["subagent", "tool", "thinking", "info"];

/// `Subject.swift:92` — open, but no turn of its own under way.
const IDLE_KINDS: [&str; 3] = ["idle", "starting", "booting"];

/// Derived display status.
///
/// Variants are declared in priority order, so the derived `Ord` *is* the
/// priority (`CoreTypes.swift:244-267`):
/// problem > attention > waiting > running > monitor > success > inactive.
///
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum StatusClass {
    Problem,
    Attention,
    Waiting,
    Running,
    Monitor,
    Success,
    Inactive,
}

impl StatusClass {
    /// Every class, most urgent first.
    pub const ALL: [StatusClass; 7] = [
        Self::Problem,
        Self::Attention,
        Self::Waiting,
        Self::Running,
        Self::Monitor,
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
            Self::Monitor => "monitor",
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

        if job.lifecycle == Lifecycle::Ended {
            return if matches!(job.outcome, Some(Outcome::Success | Outcome::Partial)) {
                Self::Success
            } else {
                Self::Inactive
            };
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
        if job.lifecycle == Lifecycle::Active
            && job
                .current
                .as_ref()
                .is_some_and(|c| names(&c.kind, &BUSY_KINDS))
        {
            return None;
        }
        if job.attention.level >= AttentionLevel::Informational {
            if Self::reason(job).is_some_and(|r| names(r, &WAIT_REASONS)) {
                return Some(Self::Waiting);
            }
            if Self::reason(job).is_some_and(|r| names(r, &ASK_REASONS))
                || job.attention.level >= AttentionLevel::Suggested
            {
                return Some(Self::Attention);
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
            return Some(Self::Problem);
        }

        // :77 — open session, partial outcome: a monitor holding the stream.
        if job.lifecycle == Lifecycle::Active && job.outcome == Some(Outcome::Partial) {
            return Some(Self::Monitor);
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
        // :86 — watching a background stream, not executing.
        if names(kind, &["monitor"]) {
            return Some(Self::Monitor);
        }
        if names(kind, &["completed"]) {
            return Some(Self::Success);
        }
        if names(kind, &["waiting"]) {
            return Some(Self::Waiting);
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

/// True when `attention.reason` is an Ask reason (case-insensitive).
pub fn is_ask_reason(reason: Option<&str>) -> bool {
    reason.map(|r| names(r, &ASK_REASONS)).unwrap_or(false)
}

/// Ask + elevated enough to interrupt (`level ≥ suggested`).
///
/// Used by `{ask}` tally / soft status-line reminders — not by paint colour
/// (Wait still shares Attention orange).
pub fn is_ask_elevated(job: &JobView) -> bool {
    is_ask_reason(job.attention.reason.as_deref())
        && job.attention.level >= AttentionLevel::Suggested
}
