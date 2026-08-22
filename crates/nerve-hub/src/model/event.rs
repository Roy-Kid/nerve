//! An observation of a job change, or a full snapshot correction.
//!
//! Ported from `Nerve/Nerve/Models/Event.swift`, including the legacy wire
//! names (`subjectId` / `sourceId` / `type` / `subject`) that old producers
//! still send.

use serde::{Deserialize, Deserializer};

use super::facet::{
    Attention, ContextInfo, Current, Health, JobAction, Lifecycle, LocationInfo, Outcome, Progress,
};
use super::job::{Extensions, Job};
use super::time::WireTime;

/// What kind of change an event reports.
///
/// Unknown kinds decode to [`EventKind::Unknown`] rather than failing: hooks
/// are fail-open, and an unrecognised kind still carries usable facets.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum EventKind {
    JobCreated,
    LifecycleChanged,
    CurrentChanged,
    AttentionChanged,
    HealthChanged,
    ProgressUpdated,
    OutcomeReported,
    Heartbeat,
    JobEnded,
    ActionCompleted,
    ProducerDisconnected,
    Snapshot,
    Unknown,
}

impl EventKind {
    /// The wire spelling. Also what the timeline records as its `kind`.
    pub fn wire(self) -> &'static str {
        match self {
            Self::JobCreated => "job.created",
            Self::LifecycleChanged => "lifecycle.changed",
            Self::CurrentChanged => "current.changed",
            Self::AttentionChanged => "attention.changed",
            Self::HealthChanged => "health.changed",
            Self::ProgressUpdated => "progress.updated",
            Self::OutcomeReported => "outcome.reported",
            Self::Heartbeat => "heartbeat",
            Self::JobEnded => "job.ended",
            Self::ActionCompleted => "action.completed",
            Self::ProducerDisconnected => "producer.disconnected",
            Self::Snapshot => "snapshot",
            Self::Unknown => "unknown",
        }
    }

    /// Exact match only — event kinds are protocol constants, not prose.
    fn from_wire(raw: &str) -> Self {
        match raw {
            "job.created" | "subject.created" => Self::JobCreated,
            "lifecycle.changed" => Self::LifecycleChanged,
            "current.changed" => Self::CurrentChanged,
            "attention.changed" => Self::AttentionChanged,
            "health.changed" => Self::HealthChanged,
            "progress.updated" => Self::ProgressUpdated,
            "outcome.reported" => Self::OutcomeReported,
            "heartbeat" => Self::Heartbeat,
            "job.ended" | "subject.ended" => Self::JobEnded,
            "action.completed" => Self::ActionCompleted,
            "producer.disconnected" | "source.disconnected" => Self::ProducerDisconnected,
            "snapshot" => Self::Snapshot,
            _ => Self::Unknown,
        }
    }
}

impl<'de> Deserialize<'de> for EventKind {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let raw = String::deserialize(deserializer)?;
        Ok(Self::from_wire(&raw))
    }
}

/// One reported change. Every facet is optional: an event patches only what it
/// carries (`SubjectStore.swift:782`).
#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Event {
    pub id: String,
    #[serde(alias = "subjectId")]
    pub job_id: String,
    pub kind: EventKind,
    pub timestamp: WireTime,
    #[serde(alias = "sourceId")]
    pub producer_id: String,

    #[serde(default)]
    pub alias: Option<String>,
    /// Producer-side version for the job. Higher wins; a lower one is dropped.
    #[serde(default)]
    pub version: Option<u64>,
    #[serde(default)]
    pub sequence: Option<u64>,

    #[serde(default)]
    pub name: Option<String>,
    #[serde(default, alias = "type")]
    pub job_kind: Option<String>,
    #[serde(default)]
    pub lifecycle: Option<Lifecycle>,
    #[serde(default)]
    pub current: Option<Current>,
    #[serde(default)]
    pub attention: Option<Attention>,
    #[serde(default)]
    pub health: Option<Health>,
    #[serde(default)]
    pub outcome: Option<Outcome>,
    #[serde(default)]
    pub progress: Option<Progress>,
    #[serde(default)]
    pub context: Option<ContextInfo>,
    #[serde(default)]
    pub location: Option<LocationInfo>,
    #[serde(default)]
    pub capabilities: Option<Vec<String>>,
    #[serde(default)]
    pub actions: Option<Vec<JobAction>>,
    #[serde(default)]
    pub extensions: Option<Extensions>,

    /// Full job body for snapshot / create events.
    #[serde(default, alias = "subject")]
    pub job: Option<Job>,
}

impl Event {
    /// The timeline line this event leaves behind (`SubjectStore.swift:813`).
    pub fn timeline_title(&self) -> String {
        // A facet event that forgot to carry its facet prints `?`, as in Swift.
        match self.kind {
            EventKind::AttentionChanged => format!(
                "Attention → {}",
                self.attention
                    .as_ref()
                    .map_or("?", |attention| attention.level.wire())
            ),
            EventKind::LifecycleChanged => format!(
                "Lifecycle → {}",
                self.lifecycle.map_or("?", Lifecycle::wire)
            ),
            EventKind::CurrentChanged => self.current_title(),
            EventKind::HealthChanged => {
                format!("Health → {}", self.health.map_or("?", Health::wire))
            }
            EventKind::OutcomeReported => {
                format!("Outcome → {}", self.outcome.map_or("?", Outcome::wire))
            }
            EventKind::JobEnded => "Ended".to_string(),
            EventKind::ProgressUpdated => self.progress_title(),
            EventKind::Heartbeat => "Heartbeat".to_string(),
            _ => self.kind.wire().to_string(),
        }
    }

    fn current_title(&self) -> String {
        let Some(current) = self.current.as_ref() else {
            return "Current changed".to_string();
        };
        current
            .summary
            .clone()
            .or_else(|| current.name.clone())
            .unwrap_or_else(|| "Current changed".to_string())
    }

    fn progress_title(&self) -> String {
        self.progress
            .as_ref()
            .and_then(|progress| progress.label.clone())
            .unwrap_or_else(|| "Progress".to_string())
    }
}
