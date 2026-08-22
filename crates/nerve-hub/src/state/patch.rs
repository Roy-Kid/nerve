//! Event → job facet merge.
//!
//! The two state transitions a single event can cause: patch a job that exists,
//! or seed the one it refers to. Both produce a **new** job value — the store
//! decides whether to keep it (`SubjectStore.swift:782` / `:461`).

use crate::model::{
    Attention, Event, EventKind, Extensions, Health, Job, Lifecycle, ProducerInfo, Progress,
};

impl Job {
    /// A copy of this job with every facet the event carries applied.
    pub(crate) fn patched(&self, event: &Event) -> Job {
        let mut next = self.clone();
        if let Some(name) = &event.name {
            next.name = name.clone();
        }
        if let Some(kind) = &event.job_kind {
            next.kind = kind.clone();
        }
        next.apply_lifecycle(event);
        if let Some(current) = &event.current {
            next.current = Some(current.clone());
        }
        if let Some(attention) = &event.attention {
            next.attention = attention.clone();
        }
        if let Some(health) = event.health {
            next.health = health;
        }
        if let Some(outcome) = event.outcome {
            next.outcome = Some(outcome);
        }
        if let Some(progress) = &event.progress {
            next.progress = progress.clone();
        }
        if let Some(context) = &event.context {
            next.context = Some(context.clone());
        }
        if let Some(location) = &event.location {
            next.location = Some(location.clone());
        }
        if let Some(capabilities) = &event.capabilities {
            next.capabilities = capabilities.clone();
        }
        if let Some(actions) = &event.actions {
            next.actions = actions.clone();
        }
        if let Some(extensions) = &event.extensions {
            // Open fields merge per key; a patch never wipes what it omits.
            for (key, value) in extensions {
                next.extensions.insert(key.clone(), value.clone());
            }
        }
        next
    }

    /// Lifecycle is the one facet with a side effect: reaching `ended` stamps
    /// `endedAt` from the event that reported it.
    fn apply_lifecycle(&mut self, event: &Event) {
        if let Some(lifecycle) = event.lifecycle {
            self.lifecycle = lifecycle;
            if lifecycle == Lifecycle::Ended {
                self.ended_at = Some(event.timestamp);
            }
        }
        if event.kind == EventKind::JobEnded {
            self.lifecycle = Lifecycle::Ended;
            self.ended_at = Some(event.timestamp);
        }
    }

    /// The job an event opens when its `jobId` is unknown.
    ///
    /// Every anchor comes from the event's own timestamp, so a replayed event
    /// rebuilds the same row (`SubjectStore.swift:464`).
    pub(crate) fn opened_by(event: &Event, machine_alias: &str) -> Job {
        let alias = event
            .alias
            .as_deref()
            .map(str::trim)
            .filter(|alias| !alias.is_empty())
            .unwrap_or(machine_alias);

        Job {
            id: event.job_id.clone(),
            kind: event.job_kind.clone().unwrap_or_else(Job::default_kind),
            // A nameless create falls back to the job id.
            name: event.name.clone().unwrap_or_else(|| event.job_id.clone()),
            alias: alias.to_string(),
            lifecycle: event.lifecycle.unwrap_or_default(),
            current: None,
            attention: Attention::default(),
            health: Health::Ok,
            outcome: None,
            progress: Progress::default(),
            producer: ProducerInfo {
                id: event.producer_id.clone(),
                name: None,
                kind: None,
            },
            context: None,
            location: None,
            capabilities: Vec::new(),
            actions: Vec::new(),
            created_at: event.timestamp,
            started_at: Some(event.timestamp),
            ended_at: None,
            updated_at: event.timestamp,
            version: 1,
            extensions: Extensions::new(),
        }
    }
}
