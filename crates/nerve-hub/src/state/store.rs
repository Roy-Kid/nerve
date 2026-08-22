//! The single write point for every job the hub knows about.
//!
//! Ported from `Nerve/Nerve/Store/SubjectStore.swift`, minus everything that is
//! a surface concern: no ribbon geometry, no status derivation, and no
//! `ensureLocalActions` — producer actions are echoed verbatim, Open/Copy are
//! derived where they are used.
//!
//! Deliberate additions over the Swift original: a `departed` buffer (SessionEnd
//! evicts immediately, so a plain frame diff would lose the terminal state) and
//! the per-job `timeline` published inside each job.

use std::collections::BTreeMap;
use std::sync::Arc;

use serde::Serialize;
use serde_json::Value;

use crate::clock::Clock;
use crate::model::{
    ActionState, Attention, Current, Event, EventKind, Health, Job, Lifecycle, Outcome, WireTime,
};

use super::dedupe::SeenEvents;
use super::demo::DemoRows;
use super::pending::{PendingAction, PendingQueue};
use super::reaper::{PidProbe, Reaper};
use super::timeline::{TimelineEntry, Timelines};

/// Every job, its timeline, and the requests waiting on producers.
///
/// In memory only: jobs, timelines and pending requests never touch disk.
pub struct JobStore {
    clock: Arc<dyn Clock>,
    /// Alias for "this machine" — fills empty job aliases and gates the reaper.
    machine_alias: String,
    reaper: Reaper,
    jobs: BTreeMap<String, Job>,
    timelines: Timelines,
    pending: PendingQueue,
    seen: SeenEvents,
    departed: Vec<Job>,
}

/// A job as published: its own wire shape plus the timeline the hub keeps for it.
#[derive(Serialize)]
struct JobView<'a> {
    #[serde(flatten)]
    job: &'a Job,
    timeline: &'a [TimelineEntry],
}

impl JobStore {
    pub fn new(clock: Arc<dyn Clock>, machine_alias: String, probe: Arc<dyn PidProbe>) -> Self {
        Self {
            clock,
            machine_alias,
            reaper: Reaper::new(probe),
            jobs: BTreeMap::new(),
            timelines: Timelines::default(),
            pending: PendingQueue::default(),
            seen: SeenEvents::default(),
            departed: Vec::new(),
        }
    }

    // ── Ingest ──────────────────────────────────────────────────────────────

    /// Apply a snapshot batch; returns how many jobs were **seen**.
    ///
    /// Ended and legacy-noise rows count too: the producer reported them, and
    /// `{"applied":N}` answers "how much of your batch did I read".
    pub fn apply_snapshot(&mut self, jobs: Vec<Job>) -> usize {
        let seen = jobs.len();
        for job in jobs {
            self.store_snapshot(job);
        }
        seen
    }

    /// Apply one event; `false` means it changed nothing (duplicate id, stale
    /// version, or an unknown job with nothing to create from).
    pub fn apply_event(&mut self, event: Event) -> bool {
        if !self.seen.remember(&event.id) {
            return false;
        }
        if let Some(full) = self.body_to_apply(&event) {
            let title = if event.kind == EventKind::Snapshot {
                "Snapshot"
            } else {
                "Created"
            };
            let job_id = full.id.clone();
            self.store_snapshot(full);
            self.timelines.record(
                &job_id,
                event.kind.wire(),
                title.to_string(),
                event.timestamp,
            );
            return true;
        }
        if self.jobs.contains_key(&event.job_id) {
            self.patch_existing(&event)
        } else {
            self.open_on_miss(&event)
        }
    }

    /// The full job body an event carries, when the port applies it as a
    /// snapshot rather than a patch (`SubjectStore.swift:439`).
    fn body_to_apply(&self, event: &Event) -> Option<Job> {
        let full = event.job.clone()?;
        let as_snapshot = event.kind == EventKind::Snapshot
            || event.kind == EventKind::JobCreated
            || !self.jobs.contains_key(&event.job_id);
        as_snapshot.then_some(full)
    }

    fn store_snapshot(&mut self, mut job: Job) {
        // Job-level alias fallback, after envelope-level normalisation.
        if job.alias.is_empty() {
            job.alias.clone_from(&self.machine_alias);
        }
        if !job.is_conversation_job() {
            self.drop_legacy_child(&job.id);
            return;
        }
        if let Some(stored) = self.jobs.get(&job.id) {
            if job.version < stored.version {
                return;
            }
        }
        if job.is_ended() {
            let ended = self.sealed(job);
            self.evict_ended(ended);
            return;
        }
        let id = job.id.clone();
        self.jobs.insert(id.clone(), job);
        // A parent update also scrubs leftover child rows for that session.
        self.purge_legacy_children(&id);
    }

    fn patch_existing(&mut self, event: &Event) -> bool {
        let Some(stored) = self.jobs.get(&event.job_id) else {
            return false;
        };
        if event
            .version
            .is_some_and(|version| version < stored.version)
        {
            return false;
        }
        let mut next = stored.patched(event);
        next.version = match event.version {
            Some(version) => next.version.max(version),
            None => next.version.saturating_add(1),
        };
        next.updated_at = next.updated_at.max(event.timestamp);
        self.keep_or_evict(next, event)
    }

    /// Create-on-miss: only a `job.created` event, or one carrying a name, may
    /// open a job that the hub has never heard of (`SubjectStore.swift:462`).
    fn open_on_miss(&mut self, event: &Event) -> bool {
        if event.kind != EventKind::JobCreated && event.name.is_none() {
            return false;
        }
        let opened = Job::opened_by(event, &self.machine_alias);
        let next = opened.patched(event);
        self.keep_or_evict(next, event)
    }

    /// Store the patched job, or let it leave if the event closed it. A closed
    /// session is never inserted into the panel first.
    fn keep_or_evict(&mut self, next: Job, event: &Event) -> bool {
        if next.is_ended() {
            self.evict_ended(next);
            return true;
        }
        self.timelines.record(
            &next.id,
            event.kind.wire(),
            event.timeline_title(),
            event.timestamp,
        );
        self.jobs.insert(next.id.clone(), next);
        true
    }

    // ── Leaving ─────────────────────────────────────────────────────────────

    /// A closing job with its stored duration anchors kept, and `endedAt`
    /// filled from the injected clock when the producer left it out
    /// (`SubjectStore.swift:530`).
    fn sealed(&self, job: Job) -> Job {
        let mut ended = job;
        if let Some(stored) = self.jobs.get(&ended.id) {
            ended.created_at = stored.created_at;
            ended.started_at = Some(stored.started_at.unwrap_or(stored.created_at));
        }
        if ended.ended_at.is_none() {
            ended.ended_at = Some(self.now());
        }
        ended
    }

    /// Session closed: keep the terminal state for subscribers, then drop the
    /// row. There is no Success linger — only open work stays visible.
    fn evict_ended(&mut self, ended: Job) {
        let id = ended.id.clone();
        self.jobs.remove(&id);
        self.timelines.forget(&id);
        // Legacy children of this conversation leave with their parent.
        self.purge_legacy_children(&id);
        self.departed.push(ended);
    }

    /// Terminal states since the last call, drained.
    pub fn take_departed(&mut self) -> Vec<Job> {
        std::mem::take(&mut self.departed)
    }

    /// The same terminal states, drained and in the published job shape.
    ///
    /// Two rules the typed drain above does not carry, both belonging to the
    /// frame that publishes them: one id appears at most once — a producer that
    /// reports the end twice inside a window leaves only its last word — and a
    /// departed row publishes an empty `timeline`, because eviction forgets it
    /// and a surface must parse one job shape rather than two.
    pub fn drain_departed_json(&mut self) -> Value {
        let departed = self.take_departed();
        let mut last: BTreeMap<&str, &Job> = BTreeMap::new();
        for job in &departed {
            last.insert(job.id.as_str(), job);
        }
        let views: Vec<JobView<'_>> = last
            .into_values()
            .map(|job| JobView { job, timeline: &[] })
            .collect();
        // See `pending_json`: plain data, unreachable fallback, array shape kept.
        serde_json::to_value(views).unwrap_or_else(|_| Value::Array(Vec::new()))
    }

    fn drop_legacy_child(&mut self, id: &str) {
        self.jobs.remove(id);
        self.timelines.forget(id);
    }

    fn purge_legacy_children(&mut self, parent_id: &str) {
        let children: Vec<String> = self
            .jobs
            .values()
            .filter(|job| !job.is_conversation_job() && job.has_legacy_parent(parent_id))
            .map(|job| job.id.clone())
            .collect();
        for id in children {
            self.drop_legacy_child(&id);
        }
    }

    /// Local policy closes a row (dead pid today). Producers are not told —
    /// the hub never signals an agent.
    fn end_locally(&mut self, id: &str, reason: &str, summary: &str, outcome: Outcome) {
        let now = self.now();
        let Some(stored) = self.jobs.get(id) else {
            return;
        };
        if stored.is_ended() {
            return;
        }
        let mut ended = stored.clone();
        ended.lifecycle = Lifecycle::Ended;
        ended.outcome = Some(outcome);
        ended.ended_at = Some(now);
        ended.updated_at = now;
        ended.version = ended.version.saturating_add(1);
        ended.attention = Attention::default();
        ended.health = Health::Ok;
        ended.current = Some(Current {
            kind: "idle".to_string(),
            name: None,
            summary: Some(summary.to_string()),
            detail: None,
            started_at: None,
        });
        ended
            .extensions
            .insert("endReason".to_string(), Value::String(reason.to_string()));
        self.evict_ended(ended);
    }

    // ── Maintenance ─────────────────────────────────────────────────────────

    /// Periodic tick: expire stale requests, then reap dead local producers
    /// (`SubjectStore.swift:1021`).
    ///
    /// Reports whether it changed anything, so a caller driving it on a timer
    /// can tell a quiet tick from one that closed a row — the hub publishes a
    /// frame for the second kind only.
    pub fn expire_and_reap(&mut self) -> bool {
        let expired = self.expire_pending();
        let reaped = self.reap_dead_local_producers();
        expired || reaped
    }

    /// Mark every request past its TTL expired and re-state the actions they
    /// referred to. `GET /v1/actions/pending` runs this before it filters
    /// (`IngestServer.swift:178`), so a stale request is never handed out.
    pub fn expire_pending(&mut self) -> bool {
        let now = self.now();
        let expired = self.pending.expire(now);
        let changed = !expired.is_empty();
        for reference in expired {
            self.set_action_state(
                &reference.job_id,
                &reference.action_id,
                ActionState::Expired,
            );
        }
        changed
    }

    fn reap_dead_local_producers(&mut self) -> bool {
        let now = self.now();
        let victims = self
            .reaper
            .victims(self.jobs.values(), now, &self.machine_alias);
        let reaped = !victims.is_empty();
        for victim in victims {
            self.end_locally(
                &victim.job_id,
                "process_gone",
                &victim.summary,
                Outcome::Cancelled,
            );
        }
        reaped
    }

    /// Seed the demo rows (`SubjectStore.swift:1090`).
    ///
    /// They enter through the same door as any reported job, so a demo row is
    /// subject to every rule a real one is — including this machine's alias and
    /// the legacy-noise filter.
    pub fn load_demo(&mut self) {
        let now = self.now();
        for job in DemoRows::new(self.machine_alias.clone(), now).jobs() {
            let id = job.id.clone();
            self.store_snapshot(job);
            self.timelines
                .record(&id, "snapshot", "Demo loaded".to_string(), now);
        }
    }

    /// Admin wipe. Not a lifecycle transition, so nothing departs.
    pub fn clear(&mut self) {
        self.jobs.clear();
        self.timelines.clear();
        self.pending.clear();
        self.seen.clear();
    }

    // ── Pending actions (dormant — nothing enqueues today) ───────────────────

    /// Bind a request to a declared action. `false` when the job or the action
    /// is unknown: the hub never invents an action.
    pub fn enqueue_pending(&mut self, id: &str, job_id: &str, action_id: &str) -> bool {
        let Some((producer_id, action_kind, title)) = self.declared_action(job_id, action_id)
        else {
            return false;
        };
        let now = self.now();
        self.pending.enqueue(PendingAction {
            id: id.to_string(),
            job_id: job_id.to_string(),
            producer_id,
            action_id: action_id.to_string(),
            action_kind,
            title: title.clone(),
            requested_at: now,
            state: ActionState::Pending,
            result_message: None,
            expires_at: None,
        });
        self.set_action_state(job_id, action_id, ActionState::Pending);
        self.timelines
            .record(job_id, "action.pending", format!("{title} → source"), now);
        true
    }

    /// Open requests as a bare JSON array, optionally for one producer.
    pub fn pending_json(&self, producer_id: Option<&str>) -> Value {
        let open = self.pending.open(self.now(), producer_id);
        // Plain data: the fallback is unreachable, and an empty array is the
        // only answer that still honours "this endpoint returns an array".
        serde_json::to_value(open).unwrap_or_else(|_| Value::Array(Vec::new()))
    }

    /// A producer reports how its action ended.
    ///
    /// Swift defers the re-arm to the main queue; the hub has no run loop, so a
    /// succeeded/failed action returns to `available` inline — re-usable rather
    /// than frozen (`SubjectStore.swift:984`).
    pub fn complete_pending(
        &mut self,
        id: &str,
        state: ActionState,
        message: Option<&str>,
        producer_id: Option<&str>,
    ) -> bool {
        let Some(done) = self.pending.complete(id, state, message, producer_id) else {
            return false;
        };
        // An expired action stays expired; a succeeded/failed one re-arms so the
        // row is usable again if the producer re-declares it.
        let settled = match state {
            ActionState::Expired => ActionState::Expired,
            _ => ActionState::Available,
        };
        self.set_action_state(&done.job_id, &done.action_id, settled);
        let title = message.map_or_else(
            || format!("{}: {}", done.title, state.wire()),
            str::to_string,
        );
        let now = self.now();
        self.timelines
            .record(&done.job_id, "action.completed", title, now);
        true
    }

    fn declared_action(&self, job_id: &str, action_id: &str) -> Option<(String, String, String)> {
        let job = self.jobs.get(job_id)?;
        let action = job.actions.iter().find(|action| action.id == action_id)?;
        Some((
            job.producer.id.clone(),
            action.kind.clone(),
            action.title.clone(),
        ))
    }

    fn set_action_state(&mut self, job_id: &str, action_id: &str, state: ActionState) {
        let now = self.now();
        let Some(job) = self.jobs.get_mut(job_id) else {
            return;
        };
        let Some(action) = job.actions.iter_mut().find(|action| action.id == action_id) else {
            return;
        };
        action.state = state;
        job.updated_at = now;
    }

    // ── Publication ─────────────────────────────────────────────────────────

    /// Every stored job as a bare JSON array, each with its timeline.
    pub fn jobs_json(&self) -> Value {
        let views: Vec<JobView<'_>> = self
            .jobs
            .values()
            .map(|job| JobView {
                job,
                timeline: self.timelines.of(&job.id),
            })
            .collect();
        // See `pending_json`: plain data, unreachable fallback, array shape kept.
        serde_json::to_value(views).unwrap_or_else(|_| Value::Array(Vec::new()))
    }

    fn now(&self) -> WireTime {
        WireTime::new(self.clock.now())
    }
}
