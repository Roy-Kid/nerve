//! `status.rs` — the six-state derivation, mirrored from Swift (spec T2 ·
//! acceptance A1).
//!
//! ─────────────────────────────────────────────────────────────────────────
//! API CONTRACT — the implementer fills `src/status.rs` to satisfy this file.
//! Tests are never edited to fit an implementation.
//! ─────────────────────────────────────────────────────────────────────────
//!
//! ```ignore
//! // nerve_tmux_surface::status
//!
//! /// Derived display status. Variants are declared in priority order, so the
//! /// derived `Ord` *is* the priority (`CoreTypes.swift:244-267`):
//! /// problem > attention > waiting > running > success > inactive.
//! #[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
//! pub enum StatusClass { Problem, Attention, Waiting, Running, Success, Inactive }
//!
//! impl StatusClass {
//!     /// Every class, most urgent first.
//!     pub const ALL: [StatusClass; 6];
//!     /// The one derivation, ported line for line from `Subject.swift:38-100`.
//!     pub fn of(job: &frame::JobView) -> StatusClass;
//!     /// Lower-case spelling, equal to Swift's `Status.rawValue`.
//!     pub fn label(self) -> &'static str;
//! }
//! ```
//!
//! ─────────────────────────────────────────────────────────────────────────
//! THE TRUTH TABLE — transcribed from `Nerve/Nerve/Models/Subject.swift:38`
//! ─────────────────────────────────────────────────────────────────────────
//!
//! The hub deliberately does not publish a derived `status`
//! (`crates/nerve-hub/src/model/job.rs:4`), so this transcription is the only
//! path and every line below is pinned by its own test. Line numbers are
//! `Subject.swift`'s.
//!
//! ```text
//! :39  outcome == failure                       -> problem
//! :40  health  == unresponsive                  -> problem
//! :43  attention.level >= suggested
//! :46      reason in WAIT_REASONS               -> waiting
//! :49      reason otherwise                     -> attention
//! :53      no reason                            -> attention
//! :56  attention.level >= informational, reason
//! :58      reason in ASK_REASONS                -> attention
//! :60      reason in WAIT_REASONS               -> waiting
//! :64      otherwise                            -> (fall through)
//! :68  lifecycle == ended
//! :69      outcome in {success, partial}        -> success
//! :70      otherwise                            -> inactive
//! :72  lifecycle in {suspended, unknown}        -> inactive
//! :73  lifecycle in {pending, created}          -> waiting
//! :74  health == degraded                       -> waiting
//! :77  lifecycle == active && outcome == partial -> success
//! :81  current.type (lower-cased)
//! :82      subagent | tool | thinking | info
//! :84          && lifecycle == active           -> running
//! :86      monitor                              -> success
//! :88      waiting                              -> waiting
//! :92      idle | starting | booting            -> inactive
//! :94      otherwise                            -> (fall through)
//! :98  lifecycle == active                      -> running
//! :99  otherwise                                -> inactive
//!
//! WAIT_REASONS = resource dependency queue system lock throttle rate capacity failure
//! ASK_REASONS  = input approval auth permission decision elicitation
//! ```
//!
//! Both reason sets are matched on the *lower-cased* reason (`:44`, `:56`), and
//! `attention.reason = "failure"` is a WAIT reason — a job blocked on a failed
//! dependency waits, it is not itself a problem. That asymmetry is Swift's, and
//! is pinned below rather than smoothed over.
//!
//! `:99` is unreachable: `:68`–`:73` already consume every lifecycle except
//! `active`, which `:98` answers. It is transcribed for fidelity, untested.
//!
//! Determinism: literal jobs, no clock, no socket, no filesystem, no hub.

mod common;

use serde_json::{json, Value};

use nerve_tmux_surface::status::StatusClass;

use common::{frame, job, SIX_STATE_FRAME};

/// The class of one literal job.
fn class(value: Value) -> StatusClass {
    StatusClass::of(&job(value))
}

// ── The enum itself ─────────────────────────────────────────────────────────

#[test]
fn test_classes_are_ordered_most_urgent_first() {
    assert_eq!(
        StatusClass::ALL,
        [
            StatusClass::Problem,
            StatusClass::Attention,
            StatusClass::Waiting,
            StatusClass::Running,
            StatusClass::Success,
            StatusClass::Inactive,
        ]
    );
    assert!(StatusClass::Problem < StatusClass::Attention);
    assert!(StatusClass::Running < StatusClass::Success);
    assert!(StatusClass::Success < StatusClass::Inactive);
}

#[test]
fn test_labels_match_the_swift_raw_values() {
    let labels: Vec<&str> = StatusClass::ALL.iter().map(|c| c.label()).collect();

    assert_eq!(
        labels,
        vec![
            "problem",
            "attention",
            "waiting",
            "running",
            "success",
            "inactive"
        ]
    );
}

// ── :39 / :40 — problem ─────────────────────────────────────────────────────

#[test]
fn test_line_39_a_failed_outcome_is_a_problem() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "active", "outcome": "failure" })),
        StatusClass::Problem
    );
}

/// `:39` runs before the lifecycle branches, so an ended failure is a problem
/// rather than an inactive row.
#[test]
fn test_line_39_beats_the_ended_lifecycle_branch() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "ended", "outcome": "failure" })),
        StatusClass::Problem
    );
}

#[test]
fn test_line_40_an_unresponsive_job_is_a_problem() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "active", "health": "unresponsive" })),
        StatusClass::Problem
    );
}

/// `:40` runs before `:68`, so an ended-but-successful row that stopped
/// answering is still a problem.
#[test]
fn test_line_40_beats_an_ended_success() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "ended",
            "outcome": "success",
            "health": "unresponsive"
        })),
        StatusClass::Problem
    );
}

// ── :43-:53 — elevated attention (>= suggested) ─────────────────────────────

#[test]
fn test_line_49_required_attention_asking_for_input_is_attention() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "attention": { "level": "required", "reason": "input" }
        })),
        StatusClass::Attention
    );
}

#[test]
fn test_line_53_elevated_attention_without_a_reason_is_attention() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "attention": { "level": "suggested" }
        })),
        StatusClass::Attention
    );
}

#[test]
fn test_line_49_an_unrecognised_reason_at_suggested_is_attention() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "attention": { "level": "urgent", "reason": "review" }
        })),
        StatusClass::Attention
    );
}

#[test]
fn test_line_46_every_wait_reason_at_required_is_waiting() {
    for reason in [
        "resource",
        "dependency",
        "queue",
        "system",
        "lock",
        "throttle",
        "rate",
        "capacity",
        "failure",
    ] {
        assert_eq!(
            class(json!({
                "id": "a",
                "lifecycle": "active",
                "attention": { "level": "required", "reason": reason }
            })),
            StatusClass::Waiting,
            "attention.reason `{reason}` at required must wait"
        );
    }
}

/// `Subject.swift:44` lower-cases the reason before matching, so a producer
/// shouting does not change the class.
#[test]
fn test_line_44_reason_matching_ignores_case() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "attention": { "level": "required", "reason": "Dependency" }
        })),
        StatusClass::Waiting
    );
}

/// `attention.reason = "failure"` is a WAIT reason (`:47`), not a problem: the
/// job is blocked on something that failed, `outcome` is what says the job
/// itself failed.
#[test]
fn test_line_47_an_attention_reason_of_failure_waits_rather_than_alarms() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "attention": { "level": "urgent", "reason": "failure" }
        })),
        StatusClass::Waiting
    );
}

// ── :56-:66 — informational attention ───────────────────────────────────────

#[test]
fn test_line_58_every_ask_reason_at_informational_is_attention() {
    for reason in [
        "input",
        "approval",
        "auth",
        "permission",
        "decision",
        "elicitation",
    ] {
        assert_eq!(
            class(json!({
                "id": "a",
                "lifecycle": "active",
                "attention": { "level": "informational", "reason": reason }
            })),
            StatusClass::Attention,
            "attention.reason `{reason}` at informational must ask"
        );
    }
}

#[test]
fn test_line_60_a_wait_reason_at_informational_is_waiting() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "attention": { "level": "informational", "reason": "queue" }
        })),
        StatusClass::Waiting
    );
}

/// `:64` breaks out of the switch instead of returning, so an informational
/// note nobody classified leaves the job exactly as busy as it was.
#[test]
fn test_line_64_an_unrecognised_informational_reason_falls_through_to_running() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "attention": { "level": "informational", "reason": "chatter" }
        })),
        StatusClass::Running
    );
}

/// `:56` requires a reason: informational alone never colours a row.
#[test]
fn test_line_56_informational_without_a_reason_falls_through_to_running() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "attention": { "level": "informational" }
        })),
        StatusClass::Running
    );
}

// ── :68-:74 — lifecycle ─────────────────────────────────────────────────────

#[test]
fn test_line_69_an_ended_success_is_success() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "ended", "outcome": "success" })),
        StatusClass::Success
    );
}

#[test]
fn test_line_69_an_ended_partial_is_success() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "ended", "outcome": "partial" })),
        StatusClass::Success
    );
}

#[test]
fn test_line_70_an_ended_job_without_an_outcome_is_inactive() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "ended" })),
        StatusClass::Inactive
    );
}

#[test]
fn test_line_70_an_ended_cancellation_is_inactive() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "ended", "outcome": "cancelled" })),
        StatusClass::Inactive
    );
}

#[test]
fn test_line_72_a_suspended_job_is_inactive() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "suspended" })),
        StatusClass::Inactive
    );
}

#[test]
fn test_line_72_an_unknown_lifecycle_is_inactive() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "unknown" })),
        StatusClass::Inactive
    );
}

#[test]
fn test_line_73_a_pending_job_is_waiting() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "pending" })),
        StatusClass::Waiting
    );
}

#[test]
fn test_line_73_a_created_job_is_waiting() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "created" })),
        StatusClass::Waiting
    );
}

#[test]
fn test_line_74_a_degraded_job_is_waiting() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "active", "health": "degraded" })),
        StatusClass::Waiting
    );
}

/// An open session reporting a partial outcome is a monitor waiting for
/// feedback: green, not blue (`.claude/notes/notes.md` 2026-07-22).
#[test]
fn test_line_77_an_open_job_with_a_partial_outcome_is_success() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "active", "outcome": "partial" })),
        StatusClass::Success
    );
}

// ── :81-:96 — current activity ──────────────────────────────────────────────

#[test]
fn test_line_84_shell_and_agent_activity_is_running() {
    for kind in ["subagent", "tool", "thinking", "info"] {
        assert_eq!(
            class(json!({
                "id": "a",
                "lifecycle": "active",
                "current": { "type": kind }
            })),
            StatusClass::Running,
            "current.type `{kind}` must run"
        );
    }
}

#[test]
fn test_line_81_current_type_matching_ignores_case() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "current": { "type": "Thinking" }
        })),
        StatusClass::Running
    );
}

#[test]
fn test_line_86_an_open_monitor_is_success() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "current": { "type": "monitor" }
        })),
        StatusClass::Success
    );
}

#[test]
fn test_line_88_a_waiting_activity_is_waiting() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "current": { "type": "waiting" }
        })),
        StatusClass::Waiting
    );
}

/// A session that is open but has not taken a turn yet is Ready, never Running
/// (`.claude/notes/notes.md` 2026-07-22 "SessionStart is starting/Ready").
#[test]
fn test_line_92_idle_starting_and_booting_are_inactive() {
    for kind in ["idle", "starting", "booting"] {
        assert_eq!(
            class(json!({
                "id": "a",
                "lifecycle": "active",
                "current": { "type": kind }
            })),
            StatusClass::Inactive,
            "current.type `{kind}` must stay inactive"
        );
    }
}

/// `current.type` is producer vocabulary, not an enum: a spelling this table
/// never heard of leaves an open job running (`:94` breaks, `:98` answers).
#[test]
fn test_line_94_an_unmodelled_current_type_leaves_an_open_job_running() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "current": { "type": "editing" }
        })),
        StatusClass::Running
    );
}

#[test]
fn test_line_98_an_open_job_with_no_current_activity_is_running() {
    assert_eq!(
        class(json!({ "id": "a", "lifecycle": "active" })),
        StatusClass::Running
    );
}

// ── Free text never classifies (CLAUDE.md invariant 3) ──────────────────────

#[test]
fn test_a_current_summary_saying_build_failed_stays_running() {
    assert_eq!(
        class(json!({
            "id": "a",
            "lifecycle": "active",
            "health": "ok",
            "current": { "type": "thinking", "summary": "build failed!!" }
        })),
        StatusClass::Running
    );
}

#[test]
fn test_no_free_text_field_can_move_a_running_job() {
    let poison = "FAILED — needs approval — error — waiting on you!!";

    assert_eq!(
        class(json!({
            "id": "a",
            "name": poison,
            "lifecycle": "active",
            "health": "ok",
            "current": {
                "type": "thinking",
                "name": poison,
                "summary": poison,
                "detail": poison
            },
            "attention": { "level": "none", "title": poison, "summary": poison }
        })),
        StatusClass::Running
    );
}

/// The mirror image: structured facets classify even when the prose is calm.
#[test]
fn test_calm_prose_does_not_hide_a_structured_problem() {
    assert_eq!(
        class(json!({
            "id": "a",
            "name": "all good",
            "lifecycle": "active",
            "outcome": "failure",
            "current": { "type": "thinking", "summary": "everything is fine" }
        })),
        StatusClass::Problem
    );
}

// ── The published frame, class by class ─────────────────────────────────────

/// Each row of `common::SIX_STATE_FRAME` lands on the class its id promises.
#[test]
fn test_the_six_state_frame_lands_one_job_on_each_class() {
    let decoded = frame(SIX_STATE_FRAME);

    let classes: Vec<(&str, StatusClass)> = decoded
        .jobs
        .iter()
        .map(|job| (job.id.as_str(), StatusClass::of(job)))
        .collect();

    assert_eq!(
        classes,
        vec![
            ("claude-code:problem", StatusClass::Problem),
            ("claude-code:attention", StatusClass::Attention),
            ("claude-code:waiting", StatusClass::Waiting),
            ("claude-code:running", StatusClass::Running),
            ("claude-code:success", StatusClass::Success),
            ("claude-code:inactive", StatusClass::Inactive),
        ]
    );
}

/// Both demo rows are plain open work: `editing` and `building` are producer
/// vocabulary this table does not model, so both run (`:94` → `:98`).
#[test]
fn test_the_demo_fixture_rows_are_both_running() {
    for job in common::demo_jobs() {
        assert_eq!(
            StatusClass::of(&job),
            StatusClass::Running,
            "job {}",
            job.id
        );
    }
}
