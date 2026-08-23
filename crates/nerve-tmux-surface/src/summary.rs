//! Rendering a tally into the `@nerve_status` text `status-right` shows.
//!
//! ─────────────────────────────────────────────────────────────────────────
//! The template language, whole:
//!
//! 1. A template is split on runs of ASCII whitespace into **segments**.
//! 2. Count tokens are `{problem} {attention} {waiting} {running} {success}
//!    {inactive} {total}`; each renders as decimal digits.
//! 3. A segment whose count tokens **all** render `0` is dropped whole —
//!    colour markers, glyphs and punctuation with it.
//! 4. A segment containing **no** count token is a literal separator and is
//!    always kept.
//! 5. An unrecognised `{token}` is left verbatim and is not a count token.
//! 6. Surviving segments are joined with a single space.
//!
//! ─────────────────────────────────────────────────────────────────────────
//!
//! Placeholders are `{token}` rather than `#{token}` because tmux expands an
//! option value a second time when `status-right` interpolates it: `#{…}` of
//! our own would be eaten. That same second expansion is why a *template's*
//! `#[fg=…]` markers are deliberately left alone — they are the part we want
//! expanded — while every `#` in *producer* text goes through
//! [`escape_dynamic`] first.

use crate::tally::Tally;

/// Make producer text safe to place inside a tmux option value.
///
/// tmux re-expands the value, so an unescaped `#` from a job name could inject
/// a style, a format expansion or a conditional into the status line.
pub fn escape_dynamic(text: &str) -> String {
    text.replace('#', "##")
}

/// The `@nerve_status_format` renderer.
pub struct SummaryRenderer {
    template: String,
}

impl SummaryRenderer {
    /// Default `@nerve_status_format`.
    pub const DEFAULT_TEMPLATE: &'static str = "#[fg=red]{problem}!#[default] \
         #[fg=yellow]{attention}?#[default] \
         #[fg=magenta]{waiting}~#[default] \
         #[fg=blue]{running}>#[default]";

    /// Default `@nerve_status_offline`.
    pub const DEFAULT_OFFLINE: &'static str = "#[fg=brightblack]nerve: offline#[default]";

    pub fn new(template: impl Into<String>) -> Self {
        Self {
            template: template.into(),
        }
    }

    /// The status-line text for `tally`.
    pub fn render(&self, tally: &Tally) -> String {
        self.template
            .split_whitespace()
            .filter_map(|segment| Self::render_segment(segment, tally))
            .collect::<Vec<String>>()
            .join(" ")
    }

    /// One segment, or `None` when every count it carries is zero.
    fn render_segment(segment: &str, tally: &Tally) -> Option<String> {
        let mut rendered = String::with_capacity(segment.len());
        let mut counted = false;
        let mut any_non_zero = false;
        let mut rest = segment;

        while let Some(open) = rest.find('{') {
            rendered.push_str(&rest[..open]);
            let brace = &rest[open..];
            let Some(close) = brace.find('}') else {
                // An unclosed brace is the user's own text, not a token.
                rendered.push_str(brace);
                return (!counted || any_non_zero).then_some(rendered);
            };
            match Self::count(&brace[1..close], tally) {
                Some(count) => {
                    counted = true;
                    any_non_zero |= count > 0;
                    rendered.push_str(&count.to_string());
                }
                None => rendered.push_str(&brace[..=close]),
            }
            rest = &brace[close + 1..];
        }
        rendered.push_str(rest);

        (!counted || any_non_zero).then_some(rendered)
    }

    /// The count a token names, or `None` when it is not a count token.
    fn count(token: &str, tally: &Tally) -> Option<usize> {
        match token {
            "problem" => Some(tally.problem),
            "attention" => Some(tally.attention),
            "waiting" => Some(tally.waiting),
            "running" => Some(tally.running),
            "success" => Some(tally.success),
            "inactive" => Some(tally.inactive),
            "total" => Some(tally.total()),
            _ => None,
        }
    }
}

impl Default for SummaryRenderer {
    fn default() -> Self {
        Self::new(Self::DEFAULT_TEMPLATE)
    }
}
