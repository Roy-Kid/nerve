//! The interrupt channel — who gets to break someone's concentration.

use nerve_surface_core::ask::{copy, should_notify};
use nerve_surface_core::frame::JobView;
use serde_json::json;

fn job(value: serde_json::Value) -> JobView {
    serde_json::from_value(value).expect("job fixture")
}

fn asking(level: &str, reason: &str) -> JobView {
    job(json!({
        "id": "j", "name": "nerve",
        "attention": { "level": level, "reason": reason }
    }))
}

#[test]
fn a_new_ask_interrupts() {
    assert!(should_notify(None, &asking("required", "approval")));
}

#[test]
fn the_same_ask_again_does_not() {
    let before = asking("required", "approval");
    let after = asking("required", "approval");
    assert!(!should_notify(Some(&before), &after));
}

#[test]
fn an_ask_that_gets_louder_interrupts_again() {
    let before = asking("suggested", "input");
    let after = asking("required", "input");
    assert!(should_notify(Some(&before), &after));
}

#[test]
fn an_ask_that_gets_quieter_does_not() {
    let before = asking("urgent", "input");
    let after = asking("required", "input");
    assert!(!should_notify(Some(&before), &after));
}

#[test]
fn a_job_that_becomes_an_ask_interrupts() {
    let before = job(json!({ "id": "j", "name": "nerve", "attention": { "level": "none" } }));
    assert!(should_notify(Some(&before), &asking("required", "input")));
}

/// The distinction the whole module exists for. A job blocked on a lock paints
/// orange because it needs a look, but nothing the human does right now moves
/// it — interrupting for that is how a status surface gets muted.
#[test]
fn waiting_on_a_machine_never_interrupts() {
    for reason in [
        "resource",
        "dependency",
        "queue",
        "lock",
        "throttle",
        "capacity",
    ] {
        assert!(
            !should_notify(None, &asking("required", reason)),
            "{reason} interrupted"
        );
    }
}

#[test]
fn every_ask_reason_can_interrupt() {
    for reason in [
        "input",
        "approval",
        "auth",
        "permission",
        "decision",
        "elicitation",
        "review",
    ] {
        assert!(
            should_notify(None, &asking("required", reason)),
            "{reason} stayed silent"
        );
    }
}

#[test]
fn an_ask_below_suggested_does_not_interrupt() {
    assert!(!should_notify(None, &asking("none", "approval")));
}

// ── Copy ────────────────────────────────────────────────────────────────────

#[test]
fn the_producers_own_words_win() {
    let row = job(json!({
        "id": "j", "name": "nerve",
        "attention": {
            "level": "required", "reason": "approval",
            "title": "Run migrations?", "summary": "against production"
        }
    }));
    let words = copy(&row);
    assert_eq!(words.title, "Run migrations?");
    assert_eq!(words.body, "against production");
}

#[test]
fn approval_reads_as_approval() {
    let words = copy(&asking("required", "approval"));
    assert_eq!(words.title, "Approval needed: nerve");
    assert_eq!(words.body, "Return to the agent to approve");
}

#[test]
fn a_review_says_so() {
    assert_eq!(
        copy(&asking("required", "review")).title,
        "A review is waiting: nerve"
    );
}

#[test]
fn a_plain_ask_is_your_turn() {
    assert_eq!(
        copy(&asking("suggested", "input")).title,
        "Your turn: nerve"
    );
}

/// Calm on purpose. A surface that escalates everything teaches people to
/// ignore it, so even urgent asks rather than demands.
#[test]
fn urgent_is_still_polite() {
    let body = copy(&asking("urgent", "input")).body;
    assert_eq!(body, "Please return when you can — continue in the agent");
    assert!(!body.contains('!'), "{body}");
    assert_eq!(body.to_uppercase(), body.to_uppercase()); // no SHOUTING words
    assert!(!body.contains("CRITICAL") && !body.contains("URGENT"));
}

#[test]
fn what_the_job_is_doing_stands_in_for_a_missing_summary() {
    let row = job(json!({
        "id": "j", "name": "nerve",
        "attention": { "level": "required", "reason": "input" },
        "current": { "type": "tool", "summary": "Waiting on your answer" }
    }));
    assert_eq!(copy(&row).body, "Waiting on your answer");
}

#[test]
fn a_blank_title_falls_back_rather_than_showing_nothing() {
    let row = job(json!({
        "id": "j", "name": "nerve",
        "attention": { "level": "required", "reason": "input", "title": "   " }
    }));
    assert_eq!(copy(&row).title, "Your turn: nerve");
}

/// Invariant 7 says every surface dedupes on the same Ask channel. That is
/// only true if the reason sets agree, and they live in three languages — this
/// crate, `vsc-ext/src/model/status.ts`, and `Nerve/Nerve/Models/Subject.swift`.
/// Reading the TypeScript one keeps the promise honest rather than hopeful.
#[test]
fn the_vs_code_surface_asks_about_the_same_reasons() {
    let source = include_str!("../../../vsc-ext/src/model/status.ts");
    let start = source
        .find("export const ASK_REASONS = [")
        .expect("ASK_REASONS moved; this test is the thing keeping the two in step");
    let end = source[start..]
        .find("] as const;")
        .expect("unterminated ASK_REASONS")
        + start;
    let listed: Vec<String> = source[start..end]
        .lines()
        .filter_map(|line| line.trim().strip_prefix('"'))
        .filter_map(|line| line.split('"').next())
        .map(str::to_string)
        .collect();

    for reason in &listed {
        assert!(
            should_notify(None, &asking("required", reason)),
            "TypeScript asks about `{reason}` and Rust does not"
        );
    }
    assert_eq!(listed.len(), 7, "found {listed:?}");
}
