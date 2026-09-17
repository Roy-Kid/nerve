//! Native host-event ingest.
//!
//! Claude Code and Grok POST their official hook JSON here (`type: "http"`).
//! Codex has no HTTP hook type, so `nerve-hub hook` reads stdin and POSTs the
//! same body. Mapping lives in the hub — one process, no Python, no trampoline.

use std::collections::HashMap;

use serde_json::Value;

use crate::clock::Clock;
use crate::model::Job;
use crate::state::JobStore;

mod build;
mod map;
mod payload;

pub use map::map_event;
pub use payload::event_name;

/// Who reported this event. Query `?producer=` on `/v1/hook`, or Codex CLI env.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Producer {
    Claude,
    Codex,
    Grok,
}

impl Producer {
    pub fn parse(raw: &str) -> Self {
        let s = raw.trim().to_ascii_lowercase();
        if s.contains("grok") {
            Self::Grok
        } else if s.contains("codex") || s == "gpt" {
            Self::Codex
        } else {
            Self::Claude
        }
    }

    pub fn from_env() -> Self {
        if std::env::var_os("GROK_PLUGIN_ROOT").is_some()
            || std::env::var_os("GROK_SESSION_ID").is_some()
            || std::env::var_os("GROK_HOOK_EVENT").is_some()
        {
            return Self::Grok;
        }
        if std::env::var_os("CODEX_HOME").is_some() || std::env::var_os("PLUGIN_ROOT").is_some() {
            return Self::Codex;
        }
        Self::Claude
    }

    pub fn key(self) -> &'static str {
        match self {
            Self::Claude => "claude",
            Self::Codex => "codex",
            Self::Grok => "grok",
        }
    }

    pub fn id(self) -> &'static str {
        match self {
            Self::Claude => "claude-code",
            Self::Codex => "codex",
            Self::Grok => "grok",
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Claude => "Claude Code",
            Self::Codex => "Codex",
            Self::Grok => "Grok",
        }
    }

    pub fn kind(self) -> &'static str {
        match self {
            Self::Claude => "agent.claude",
            Self::Codex => "agent.codex",
            Self::Grok => "agent.grok",
        }
    }
}

/// Last session_id per UI slot, so SessionStart can close a superseded row.
#[derive(Debug, Default)]
pub struct SlotMap {
    inner: HashMap<String, String>,
}

impl SlotMap {
    pub fn new() -> Self {
        Self::default()
    }

    /// Remember `session` for `slot`. Previous different session, if any.
    pub fn supersede(&mut self, slot: String, session: String) -> Option<String> {
        match self.inner.insert(slot, session.clone()) {
            Some(prev) if prev != session => Some(prev),
            _ => None,
        }
    }

    pub fn clear_if(&mut self, slot: &str, session: &str) {
        if self.inner.get(slot).map(String::as_str) == Some(session) {
            self.inner.remove(slot);
        }
    }
}

/// Map one host event into zero or more jobs the store should apply.
pub fn jobs_from_event(
    producer: Producer,
    payload: &Value,
    clock: &dyn Clock,
    slots: &mut SlotMap,
) -> Vec<Job> {
    if payload::skip_subagent_noise(&event_name(payload), payload) {
        return Vec::new();
    }
    let Some(facets) = map::map_event(payload) else {
        return Vec::new();
    };
    let session = payload::session_id(payload);
    let slot = build::slot_id(producer, payload);
    let mut jobs = Vec::new();
    if event_name(payload) == "sessionstart" {
        if let Some(prev) = slots.supersede(slot.clone(), session.clone()) {
            jobs.push(build::ended_supersede(payload, producer, &prev, clock));
        }
    } else if event_name(payload) == "sessionend" {
        slots.clear_if(&slot, &session);
    } else {
        let _ = slots.supersede(slot, session.clone());
    }
    let job = build::build_job(payload, producer, clock, &facets, &session);
    // Python refused ids with two or more extra colons (legacy children).
    if job.id.matches(':').count() >= 2 {
        return jobs;
    }
    jobs.push(job);
    jobs
}

/// Apply a host event to the store. Returns how many jobs were read.
pub fn apply(
    store: &mut JobStore,
    slots: &mut SlotMap,
    producer: Producer,
    payload: &Value,
) -> usize {
    let jobs = jobs_from_event(producer, payload, store.clock(), slots);
    if jobs.is_empty() {
        return 0;
    }
    store.apply_snapshot(jobs)
}

/// Fail-open POST of stdin to the local hub (`nerve-hub hook`).
pub fn forward_stdin() -> i32 {
    use std::io::Read;
    let mut body = Vec::new();
    let _ = std::io::stdin().read_to_end(&mut body);
    if body.is_empty() {
        return 0;
    }
    let producer = Producer::from_env();
    let path = format!("/v1/hook?producer={}", producer.key());
    let _ = post_loopback(&path, &body);
    0
}

/// Forward one event to the hub already running on this machine.
///
/// Fail-open in every arm (CLAUDE.md invariant 2): a hub that is not there, a
/// refused connection and a slow answer all mean the same thing to the agent,
/// which is that nothing happened and it may carry on. The caller exits 0
/// regardless.
fn post_loopback(path: &str, body: &[u8]) -> Result<(), ()> {
    use std::time::Duration;

    let url = format!("http://{}{path}", crate::INGEST_ADDR);
    let client = reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_millis(400))
        .timeout(Duration::from_millis(800))
        .build()
        .map_err(|_| ())?;
    client
        .post(url)
        .header("Content-Type", "application/json")
        .body(body.to_vec())
        .send()
        .map(|_| ())
        .map_err(|_| ())
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use time::macros::datetime;

    use crate::clock::FakeClock;
    use crate::state::{JobStore, SignalProbe};
    use std::sync::Arc;

    use super::*;

    fn store() -> (JobStore, SlotMap) {
        let clock = Arc::new(FakeClock::new(datetime!(2026-08-23 12:00:00 UTC)));
        (
            JobStore::new(clock, "test-mac".into(), Arc::new(SignalProbe)),
            SlotMap::new(),
        )
    }

    #[test]
    fn a_session_start_opens_one_job() {
        let (mut store, mut slots) = store();
        let n = apply(
            &mut store,
            &mut slots,
            Producer::Claude,
            &json!({
                "hook_event_name": "SessionStart",
                "session_id": "s1",
                "cwd": "/tmp/work"
            }),
        );
        assert_eq!(n, 1);
        let jobs = store.jobs_json();
        assert_eq!(jobs[0]["id"], "claude-code:s1");
        assert_eq!(jobs[0]["name"], "work");
        assert_eq!(jobs[0]["current"]["type"], "starting");
    }

    #[test]
    fn a_new_session_in_the_same_slot_supersedes() {
        let (mut store, mut slots) = store();
        apply(
            &mut store,
            &mut slots,
            Producer::Claude,
            &json!({"hook_event_name": "SessionStart", "session_id": "old", "cwd": "/tmp/p"}),
        );
        apply(
            &mut store,
            &mut slots,
            Producer::Claude,
            &json!({"hook_event_name": "SessionStart", "session_id": "new", "cwd": "/tmp/p"}),
        );
        let jobs = store.jobs_json();
        let ids: Vec<&str> = jobs
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|j| j["id"].as_str())
            .collect();
        assert!(ids.contains(&"claude-code:new"));
        assert!(
            !ids.contains(&"claude-code:old"),
            "superseded row is evicted"
        );
    }

    #[test]
    fn tool_events_inside_a_subagent_are_ignored() {
        let (mut store, mut slots) = store();
        let n = apply(
            &mut store,
            &mut slots,
            Producer::Claude,
            &json!({
                "hook_event_name": "PreToolUse",
                "session_id": "s1",
                "agent_id": "child",
                "tool_name": "Bash"
            }),
        );
        assert_eq!(n, 0);
    }

    #[test]
    fn permission_inside_a_subagent_still_updates_main() {
        let (mut store, mut slots) = store();
        let n = apply(
            &mut store,
            &mut slots,
            Producer::Claude,
            &json!({
                "hook_event_name": "PermissionRequest",
                "session_id": "s1",
                "agent_id": "child",
                "tool_name": "Bash"
            }),
        );
        assert_eq!(n, 1);
        assert_eq!(store.jobs_json()[0]["attention"]["reason"], "approval");
    }

    #[test]
    fn job_id_never_includes_agent_id() {
        let (mut store, mut slots) = store();
        apply(
            &mut store,
            &mut slots,
            Producer::Claude,
            &json!({
                "hook_event_name": "SubagentStart",
                "session_id": "s1",
                "agent_id": "child-9",
                "agent_type": "Explore"
            }),
        );
        assert_eq!(store.jobs_json()[0]["id"], "claude-code:s1");
    }

    #[test]
    fn user_prompt_travels_as_a_sticky_extension() {
        let (mut store, mut slots) = store();
        apply(
            &mut store,
            &mut slots,
            Producer::Claude,
            &json!({
                "hook_event_name": "UserPromptSubmit",
                "session_id": "s1",
                "prompt": "fix the tests"
            }),
        );
        assert_eq!(
            store.jobs_json()[0]["extensions"]["lastPrompt"],
            "fix the tests"
        );
    }

    /// A Windows producer reporting through a tunnel used to arrive with its
    /// whole path as the job name and no `openURL` at all, because both were
    /// decided by `starts_with('/')`.
    #[test]
    fn a_windows_cwd_names_the_project_and_still_links() {
        let (mut store, mut slots) = store();
        apply(
            &mut store,
            &mut slots,
            Producer::Claude,
            &json!({
                "hook_event_name": "SessionStart",
                "session_id": "s1",
                "cwd": "C:\\Users\\me\\work\\nerve"
            }),
        );
        let jobs = store.jobs_json();
        assert_eq!(jobs[0]["name"], "nerve");
        assert_eq!(
            jobs[0]["location"]["openURL"],
            "file:///C:/Users/me/work/nerve"
        );
    }

    #[test]
    fn a_unc_cwd_names_the_project_and_still_links() {
        let (mut store, mut slots) = store();
        apply(
            &mut store,
            &mut slots,
            Producer::Claude,
            &json!({
                "hook_event_name": "SessionStart",
                "session_id": "s1",
                "cwd": "\\\\srv\\share\\nerve"
            }),
        );
        let jobs = store.jobs_json();
        assert_eq!(jobs[0]["name"], "nerve");
        assert_eq!(jobs[0]["location"]["openURL"], "file://srv/share/nerve");
    }

    /// A relative `cwd` is a degraded report, not a reason to lose the name.
    #[test]
    fn a_relative_cwd_still_names_the_project_but_links_nowhere() {
        let (mut store, mut slots) = store();
        apply(
            &mut store,
            &mut slots,
            Producer::Claude,
            &json!({
                "hook_event_name": "SessionStart",
                "session_id": "s1",
                "cwd": "work/nerve"
            }),
        );
        let jobs = store.jobs_json();
        assert_eq!(jobs[0]["name"], "nerve");
        assert!(jobs[0]["location"]["openURL"].is_null());
    }
}
