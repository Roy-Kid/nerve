//! When a toast is raised, and when it is swallowed.

use std::time::{Duration, Instant};

use nerve_surface_core::frame::{AttentionLevel, JobView};
use nerve_windows_surface::notify::policy::{AskPolicy, Settings, DEDUPE};
use serde_json::json;

fn job(id: &str, level: &str, reason: &str) -> JobView {
    serde_json::from_value(json!({
        "id": id, "name": id,
        "attention": { "level": level, "reason": reason }
    }))
    .expect("job fixture")
}

fn quiet(id: &str) -> JobView {
    serde_json::from_value(json!({
        "id": id, "name": id, "attention": { "level": "none" }
    }))
    .expect("job fixture")
}

fn on() -> Settings {
    Settings {
        enabled: true,
        ..Settings::default()
    }
}

#[test]
fn notifications_are_off_until_the_user_says_otherwise() {
    // Two surfaces on one machine would otherwise both toast the same Ask, and
    // peers cannot know about each other (invariant 7).
    assert!(!Settings::default().enabled);
}

#[test]
fn a_disabled_policy_raises_nothing() {
    let mut policy = AskPolicy::new();
    let toasts = policy.evaluate(
        &[job("a", "required", "approval")],
        Settings::default(),
        Instant::now(),
    );
    assert!(toasts.is_empty());
}

/// Turning notifications on must not replay every Ask already on screen.
#[test]
fn enabling_it_does_not_announce_the_backlog() {
    let mut policy = AskPolicy::new();
    let jobs = [job("a", "required", "approval")];
    let now = Instant::now();

    policy.evaluate(&jobs, Settings::default(), now);
    let toasts = policy.evaluate(&jobs, on(), now + Duration::from_secs(1));

    assert!(toasts.is_empty(), "replayed {toasts:?}");
}

#[test]
fn a_new_ask_raises_one_toast() {
    let mut policy = AskPolicy::new();
    let toasts = policy.evaluate(&[job("a", "required", "approval")], on(), Instant::now());
    assert_eq!(toasts.len(), 1);
    assert_eq!(toasts[0].job_id, "a");
    assert_eq!(toasts[0].title, "Approval needed: a");
}

#[test]
fn the_same_ask_in_the_next_frame_is_silent() {
    let mut policy = AskPolicy::new();
    let jobs = [job("a", "required", "approval")];
    let now = Instant::now();

    assert_eq!(policy.evaluate(&jobs, on(), now).len(), 1);
    assert!(policy
        .evaluate(&jobs, on(), now + Duration::from_secs(1))
        .is_empty());
}

#[test]
fn a_louder_ask_is_heard_again() {
    let mut policy = AskPolicy::new();
    let now = Instant::now();
    policy.evaluate(&[job("a", "suggested", "input")], on(), now);
    let toasts = policy.evaluate(
        &[job("a", "required", "input")],
        on(),
        now + Duration::from_secs(1),
    );
    assert_eq!(toasts.len(), 1);
}

#[test]
fn a_flapping_ask_is_silent_inside_the_dedupe_window() {
    let mut policy = AskPolicy::new();
    let asking = [job("a", "required", "approval")];
    let now = Instant::now();

    policy.evaluate(&asking, on(), now);
    policy.evaluate(&[quiet("a")], on(), now + Duration::from_secs(1));
    let toasts = policy.evaluate(&asking, on(), now + Duration::from_secs(2));

    assert!(toasts.is_empty(), "flapping produced {toasts:?}");
}

#[test]
fn the_same_ask_after_the_window_is_heard_again() {
    let mut policy = AskPolicy::new();
    let asking = [job("a", "required", "approval")];
    let now = Instant::now();

    policy.evaluate(&asking, on(), now);
    policy.evaluate(&[quiet("a")], on(), now + Duration::from_secs(1));
    let toasts = policy.evaluate(&asking, on(), now + DEDUPE + Duration::from_secs(1));

    assert_eq!(toasts.len(), 1);
}

/// A row that left and came back is a different piece of work, not a repeat.
#[test]
fn a_job_that_departed_is_heard_when_it_returns() {
    let mut policy = AskPolicy::new();
    let asking = [job("a", "required", "approval")];
    let now = Instant::now();

    policy.evaluate(&asking, on(), now);
    policy.evaluate(&[], on(), now + Duration::from_secs(1));
    let toasts = policy.evaluate(&asking, on(), now + Duration::from_secs(2));

    assert_eq!(toasts.len(), 1);
}

#[test]
fn waiting_on_a_machine_never_toasts() {
    let mut policy = AskPolicy::new();
    let toasts = policy.evaluate(&[job("a", "urgent", "lock")], on(), Instant::now());
    assert!(toasts.is_empty(), "a lock interrupted: {toasts:?}");
}

#[test]
fn the_floor_holds_back_quieter_asks() {
    let mut policy = AskPolicy::new();
    let settings = Settings {
        floor: AttentionLevel::Required,
        ..on()
    };
    assert!(policy
        .evaluate(&[job("a", "suggested", "input")], settings, Instant::now())
        .is_empty());
}

#[test]
fn sound_is_only_for_the_loud_ones_and_only_when_asked() {
    let mut policy = AskPolicy::new();
    let loud = Settings {
        sound: true,
        ..on()
    };
    let now = Instant::now();

    let quiet_ask = policy.evaluate(&[job("a", "suggested", "input")], loud, now);
    assert!(!quiet_ask[0].sound, "a suggestion made a noise");

    let loud_ask = policy.evaluate(&[job("b", "required", "approval")], loud, now);
    assert!(loud_ask[0].sound);

    let mut silent = AskPolicy::new();
    let muted = policy_toasts(&mut silent, "c", on(), now);
    assert!(!muted[0].sound, "sound fired with the setting off");
}

fn policy_toasts(
    policy: &mut AskPolicy,
    id: &str,
    settings: Settings,
    now: Instant,
) -> Vec<nerve_windows_surface::notify::policy::Toast> {
    policy.evaluate(&[job(id, "required", "approval")], settings, now)
}

#[test]
fn two_asking_jobs_each_get_their_own_toast() {
    let mut policy = AskPolicy::new();
    let toasts = policy.evaluate(
        &[
            job("a", "required", "approval"),
            job("b", "required", "input"),
        ],
        on(),
        Instant::now(),
    );
    assert_eq!(toasts.len(), 2);
    let tags: Vec<_> = toasts.iter().map(|toast| toast.tag.as_str()).collect();
    assert_eq!(tags, vec!["a|required", "b|required"]);
}
