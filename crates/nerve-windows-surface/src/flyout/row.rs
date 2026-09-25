//! One job, and what it looks like opened up.

use egui::{Align, Color32, Layout, Response, RichText, Sense, Ui, Vec2};
use nerve_surface_core::display::{activity_text, age_label};
use nerve_surface_core::frame::JobView;
use nerve_surface_core::palette;
use nerve_surface_core::status::StatusClass;
use time::OffsetDateTime;

use super::theme::{color, secondary};
use crate::tray::icon::Theme;

/// The status dot's diameter.
const DOT: f32 = 8.0;
/// How many timeline entries the detail block shows.
const RECENT: usize = 5;

/// What the user asked the surface to do about a row.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RowAction {
    /// Take me there.
    Open,
    /// Put it on the clipboard.
    Copy,
}

/// Draw one row; returns an action if a button in it was pressed.
///
/// `expanded` is owned by the caller so only one row can be open at a time —
/// a panel with three detail blocks unfurled is a scroll bar, not a glance.
pub fn show(
    ui: &mut Ui,
    job: &JobView,
    timeline: &[nerve_surface_core::frame::TimelineEntry],
    expanded: bool,
    theme: Theme,
    now: OffsetDateTime,
) -> (Response, Option<RowAction>) {
    let mut action = None;

    let response = ui
        .scope(|ui| {
            ui.horizontal(|ui| {
                dot(ui, StatusClass::of(job));
                ui.add_space(6.0);
                ui.add_sized(
                    [(ui.available_width() - 55.0).max(0.0), 20.0],
                    egui::Label::new(RichText::new(job.name.trim()).strong()).truncate(),
                )
                .on_hover_text(job.name.trim());

                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    ui.label(
                        RichText::new(age_label(now, job))
                            .color(secondary(theme))
                            .small(),
                    );
                });
            });
            let activity = activity_text(job).trim();
            if !activity.is_empty() {
                ui.add(
                    egui::Label::new(RichText::new(activity).color(secondary(theme)).small())
                        .truncate(),
                )
                .on_hover_text(activity);
            }
        })
        .response
        .interact(Sense::click());

    if expanded {
        ui.indent(&job.id, |ui| {
            action = detail(ui, job, timeline, theme);
        });
    }

    (response, action)
}

fn dot(ui: &mut Ui, class: StatusClass) {
    let (rect, _) = ui.allocate_exact_size(Vec2::splat(DOT), Sense::hover());
    ui.painter()
        .circle_filled(rect.center(), DOT / 2.0, color(palette::color_of(class)));
}

/// Prompt, context, actions, recent activity.
///
/// The prompt is the job's own `extensions.lastPrompt` and never falls back to
/// the activity summary: showing what the agent is doing in the place a person
/// looks for what they asked is worse than showing nothing.
fn detail(
    ui: &mut Ui,
    job: &JobView,
    timeline: &[nerve_surface_core::frame::TimelineEntry],
    theme: Theme,
) -> Option<RowAction> {
    let mut action = None;
    let muted = secondary(theme);

    if let Some(prompt) = job.extensions.last_prompt.as_deref().map(str::trim)
        && !prompt.is_empty()
    {
        ui.add_space(4.0);
        ui.label(RichText::new("Prompt").color(muted).small());
        ui.label(RichText::new(truncate(prompt, 240)).small());
    }

    field(ui, "Machine", job.alias.trim(), muted);
    if let Some(workspace) = job.context.workspace.as_deref().map(str::trim)
        && !workspace.is_empty()
        && workspace != job.name.trim()
    {
        field(ui, "Project", workspace, muted);
    }

    if let Some(location) = &job.location
        && let Some(value) = location
            .focus_hint
            .as_deref()
            .or(location.open_url.as_deref())
    {
        field(ui, "Location", value.trim(), muted);
    }

    ui.add_space(6.0);
    ui.horizontal(|ui| {
        if ui.small_button("Open").clicked() {
            action = Some(RowAction::Open);
        }
        if ui.small_button("Copy").clicked() {
            action = Some(RowAction::Copy);
        }
    });

    if !timeline.is_empty() {
        ui.add_space(6.0);
        ui.label(RichText::new("Recent").color(muted).small());
        for entry in timeline.iter().rev().take(RECENT) {
            ui.label(
                RichText::new(format!("{}  {}", clock(entry), truncate(&entry.title, 40)))
                    .color(muted)
                    .small(),
            );
        }
    }
    ui.add_space(4.0);

    action
}

fn field(ui: &mut Ui, label: &str, value: &str, muted: Color32) {
    if value.is_empty() {
        return;
    }
    ui.horizontal(|ui| {
        ui.label(RichText::new(label).color(muted).small());
        ui.add(egui::Label::new(RichText::new(value).small()).truncate())
            .on_hover_text(value);
    });
}

/// `HH:MM`, or nothing when the entry carries no time.
fn clock(entry: &nerve_surface_core::frame::TimelineEntry) -> String {
    entry
        .at
        .map(|at| {
            let time = at.instant();
            format!("{:02}:{:02}", time.hour(), time.minute())
        })
        .unwrap_or_default()
}

/// Cut on a character boundary, with an ellipsis when something was removed.
fn truncate(text: &str, limit: usize) -> String {
    if text.chars().count() <= limit {
        return text.to_string();
    }
    let mut out: String = text.chars().take(limit.saturating_sub(1)).collect();
    out.push('…');
    out
}
