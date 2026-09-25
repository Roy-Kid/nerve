//! `summary.rs` — rendering `@nerve_status` (spec T3 · acceptance A2).
//!
//! ─────────────────────────────────────────────────────────────────────────
//! API CONTRACT — the implementer fills `src/summary.rs` to satisfy this file.
//! Tests are never edited to fit an implementation.
//! ─────────────────────────────────────────────────────────────────────────
//!
//! ```ignore
//! // nerve_tmux_surface::summary
//!
//! pub struct SummaryRenderer { /* template: String */ }
//!
//! impl SummaryRenderer {
//!     /// Default `@nerve_status_format`.
//!     pub const DEFAULT_TEMPLATE: &'static str =
//!         "#[fg=red]{problem}!#[default] \
//!          #[fg=yellow]{ask}?#[default] \
//!          #[fg=magenta]{monitor}~#[default] \
//!          #[fg=blue]{running}>#[default]";
//!     /// Default `@nerve_status_offline`.
//!     pub const DEFAULT_OFFLINE: &'static str = "#[fg=brightblack]nerve: offline#[default]";
//!
//!     pub fn new(template: impl Into<String>) -> Self;
//!     pub fn render(&self, tally: &tally::Tally) -> String;
//! }
//!
//! impl Default for SummaryRenderer { /* new(DEFAULT_TEMPLATE) */ }
//!
//! /// Make producer text safe to place inside a tmux option value.
//! pub fn escape_dynamic(text: &str) -> String;
//! ```
//!
//! ─────────────────────────────────────────────────────────────────────────
//! TEMPLATE LANGUAGE (pinned here so the implementer has no latitude)
//! ─────────────────────────────────────────────────────────────────────────
//!
//! 1. A template is split on runs of ASCII whitespace into **segments**.
//! 2. Count tokens are `{problem} {ask} {attention} {waiting} {running}
//!    {monitor} {success} {inactive} {total}`; each renders as decimal digits.
//! 3. A segment whose count tokens **all** render `0` is dropped whole —
//!    colour markers, glyphs and punctuation with it.
//! 4. A segment containing **no** count token is a literal separator and is
//!    always kept.
//! 5. An unrecognised `{token}` is left verbatim and is not a count token.
//! 6. Surviving segments are joined with a single space.
//!
//! Placeholders are `{token}`, not `#{token}`, because tmux expands an option
//! value a second time when `status-right` interpolates it (spec Domain basis,
//! "tmux(1) 事实"): `#{…}` in our own text would be eaten. The same expansion
//! is why `#[fg=…]` in a *template* is deliberately left alone while every
//! `#` in *producer* text is doubled by `escape_dynamic`.
//!
//! Determinism: literal templates and tallies, no clock, no socket, no
//! filesystem, no hub.

use nerve_surface_core::tally::Tally;
use nerve_tmux_surface::summary::{SummaryRenderer, escape_dynamic};

/// The tally acceptance A2 names: two running, one ask, no problems.
fn a2_tally() -> Tally {
    Tally {
        running: 2,
        attention: 1,
        ask: 1,
        problem: 0,
        ..Tally::default()
    }
}

// ── The default template, golden ────────────────────────────────────────────

/// Acceptance A2, hard-coded: the default format over `{running:2,
/// ask:1, problem:0}`.
#[test]
fn test_default_template_over_the_a2_tally_is_the_golden_segment() {
    let rendered = SummaryRenderer::default().render(&a2_tally());

    assert_eq!(rendered, "#[fg=yellow]1?#[default] #[fg=blue]2>#[default]");
}

#[test]
fn test_default_template_is_the_literal_the_docs_publish() {
    assert_eq!(
        SummaryRenderer::DEFAULT_TEMPLATE,
        "#[fg=red]{problem}!#[default] #[fg=yellow]{ask}?#[default] \
         #[fg=magenta]{monitor}~#[default] #[fg=blue]{running}>#[default]"
    );
}

#[test]
fn test_default_offline_placeholder_is_the_literal_the_docs_publish() {
    assert_eq!(
        SummaryRenderer::DEFAULT_OFFLINE,
        "#[fg=brightblack]nerve: offline#[default]"
    );
}

#[test]
fn test_default_renderer_uses_the_default_template() {
    let tally = a2_tally();

    assert_eq!(
        SummaryRenderer::default().render(&tally),
        SummaryRenderer::new(SummaryRenderer::DEFAULT_TEMPLATE).render(&tally)
    );
}

/// One of every class: the default format shows problem / ask / monitor /
/// running and stays quiet about `waiting` (merged into attention), `success`,
/// and `inactive`. Wait-only attention without `ask` does not light the `?`.
#[test]
fn test_default_template_over_one_of_each_class() {
    let tally = Tally {
        problem: 1,
        attention: 1,
        waiting: 1,
        running: 1,
        monitor: 1,
        success: 1,
        inactive: 1,
        ask: 1,
    };

    assert_eq!(
        SummaryRenderer::default().render(&tally),
        "#[fg=red]1!#[default] #[fg=yellow]1?#[default] \
         #[fg=magenta]1~#[default] #[fg=blue]1>#[default]"
    );
}

// ── Zero-count elision ──────────────────────────────────────────────────────

#[test]
fn test_a_zero_count_drops_its_whole_segment_including_the_colour_marker() {
    let rendered = SummaryRenderer::default().render(&a2_tally());

    assert!(
        !rendered.contains("fg=red"),
        "the empty problem segment must leave nothing behind: {rendered}"
    );
    assert!(
        !rendered.contains('0'),
        "no zero may be painted: {rendered}"
    );
}

#[test]
fn test_an_empty_tally_renders_an_empty_segment() {
    assert_eq!(SummaryRenderer::default().render(&Tally::default()), "");
}

#[test]
fn test_a_segment_is_kept_when_any_of_its_count_tokens_is_non_zero() {
    let renderer = SummaryRenderer::new("[{problem}/{running}]");

    assert_eq!(renderer.render(&a2_tally()), "[0/2]");
}

#[test]
fn test_a_segment_is_dropped_only_when_every_count_token_is_zero() {
    let renderer = SummaryRenderer::new("[{problem}/{success}]");

    assert_eq!(renderer.render(&a2_tally()), "");
}

// ── Custom templates ────────────────────────────────────────────────────────

/// Acceptance A2: `{running}/{total}` substitutes positionally.
#[test]
fn test_a_custom_running_over_total_template_substitutes_in_place() {
    let renderer = SummaryRenderer::new("{running}/{total}");

    assert_eq!(renderer.render(&a2_tally()), "2/3");
}

#[test]
fn test_total_counts_every_class_not_just_the_painted_ones() {
    let renderer = SummaryRenderer::new("{total}");
    let tally = Tally {
        problem: 1,
        attention: 1,
        waiting: 1,
        running: 1,
        monitor: 1,
        success: 1,
        inactive: 1,
        ..Tally::default()
    };

    assert_eq!(renderer.render(&tally), "7");
}

#[test]
fn test_every_count_token_is_substitutable() {
    let renderer = SummaryRenderer::new(
        "{problem}-{ask}-{attention}-{waiting}-{running}-{monitor}-{success}-{inactive}-{total}",
    );
    let tally = Tally {
        problem: 1,
        ask: 8,
        attention: 2,
        waiting: 3,
        running: 4,
        monitor: 5,
        success: 6,
        inactive: 7,
    };

    assert_eq!(renderer.render(&tally), "1-8-2-3-4-5-6-7-28");
}

/// A segment carrying no count token is a separator the user asked for.
#[test]
fn test_a_segment_without_count_tokens_is_always_kept() {
    let renderer = SummaryRenderer::new("nerve {running}>");

    assert_eq!(renderer.render(&a2_tally()), "nerve 2>");
    assert_eq!(renderer.render(&Tally::default()), "nerve");
}

/// Unknown braces belong to the user, not to us.
#[test]
fn test_an_unrecognised_token_is_left_verbatim() {
    let renderer = SummaryRenderer::new("{host} {running}>");

    assert_eq!(renderer.render(&a2_tally()), "{host} 2>");
}

#[test]
fn test_whitespace_between_segments_normalises_to_one_space() {
    let renderer = SummaryRenderer::new("{running}>\t\t {attention}?");

    assert_eq!(renderer.render(&a2_tally()), "2> 1?");
}

#[test]
fn test_an_empty_template_renders_nothing() {
    assert_eq!(SummaryRenderer::new("").render(&a2_tally()), "");
}

// ── `#` escaping (tmux re-expands option values) ────────────────────────────

#[test]
fn test_escape_dynamic_doubles_every_hash() {
    assert_eq!(escape_dynamic("fix #42 and #43"), "fix ##42 and ##43");
}

/// The reason the escape exists: producer text must not be able to inject a
/// style, a format expansion, or a conditional into the status line.
#[test]
fn test_escape_dynamic_neutralises_a_style_marker_in_producer_text() {
    assert_eq!(escape_dynamic("#[fg=red]gotcha"), "##[fg=red]gotcha");
}

#[test]
fn test_escape_dynamic_neutralises_a_format_expansion_in_producer_text() {
    assert_eq!(
        escape_dynamic("#{pane_current_command}"),
        "##{pane_current_command}"
    );
}

#[test]
fn test_escape_dynamic_doubles_each_hash_of_a_run() {
    assert_eq!(escape_dynamic("##"), "####");
}

#[test]
fn test_escape_dynamic_leaves_text_without_a_hash_alone() {
    assert_eq!(escape_dynamic("xcodebuild Nerve"), "xcodebuild Nerve");
}

#[test]
fn test_escape_dynamic_leaves_an_empty_string_empty() {
    assert_eq!(escape_dynamic(""), "");
}

/// The template is trusted the other way round: its markers are the part we
/// *want* tmux to expand, so `render` must never escape them.
#[test]
fn test_render_never_escapes_the_templates_own_style_markers() {
    let renderer = SummaryRenderer::new("#[fg=red]{running}#[default]");

    assert_eq!(renderer.render(&a2_tally()), "#[fg=red]2#[default]");
}
