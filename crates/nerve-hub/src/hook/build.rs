//! Host event + facets → one Nerve job snapshot.

use nerve_platform::path;
use serde_json::{json, Map, Value};

use crate::clock::Clock;
use crate::model::{
    ActionState, Attention, AttentionLevel, ContextInfo, Current, Health, Job, JobAction,
    Lifecycle, LocationInfo, Outcome, ProducerInfo, Progress, ProgressKind, WireTime,
};

use super::map::{Facets, PROMPT_MAX};
use super::payload::{
    agent_id, agent_type, cwd, event_name, get_str, get_text, project_name, truncate,
};
use super::Producer;

pub fn build_job(
    payload: &Value,
    producer: Producer,
    clock: &dyn Clock,
    facets: &Facets,
    session: &str,
) -> Job {
    let now = WireTime::new(clock.now());
    let cwd = cwd(payload);
    let project = project_name(&cwd).to_string();
    let location = location(payload, producer, &cwd, &project);
    let mut extensions = Map::new();
    if let Some(ev) = get_str(payload, &["hook_event_name", "hookEventName", "event"]) {
        extensions.insert("hookEvent".into(), json!(ev));
    }
    extensions.insert("sessionId".into(), json!(session));
    if let Some(model) = get_text(payload, &["model"]) {
        extensions.insert("model".into(), json!(model));
    }
    if let Some(at) = agent_type(payload) {
        extensions.insert("agentType".into(), json!(at));
    }
    let event = event_name(payload);
    if event == "subagentstart" || event == "subagentstop" {
        if let Some(aid) = agent_id(payload) {
            extensions.insert("agentId".into(), json!(aid));
        }
    }
    if let Some(reason) = &facets.end_reason {
        extensions.insert("endReason".into(), json!(reason));
    }
    if event == "userpromptsubmit" {
        if let Some(prompt) = get_text(payload, &["prompt", "user_prompt"]) {
            let prompt = truncate(&prompt, PROMPT_MAX);
            if !prompt.is_empty() {
                extensions.insert("lastPrompt".into(), json!(prompt));
                extensions.insert(
                    "lastPromptAt".into(),
                    serde_json::to_value(now).unwrap_or(Value::Null),
                );
            }
        }
    }

    let current = Current {
        kind: facets.current_type.to_string(),
        name: facets.current_name.clone(),
        summary: facets.current_summary.clone(),
        detail: None,
        started_at: if facets.ended { None } else { Some(now) },
    };

    Job {
        id: format!("{}:{session}", producer.id()),
        kind: "session".into(),
        name: project.clone(),
        alias: String::new(), // store fills this machine's alias
        lifecycle: if facets.ended {
            Lifecycle::Ended
        } else {
            Lifecycle::Active
        },
        current: Some(current),
        attention: Attention {
            level: match facets.attention_level {
                "informational" => AttentionLevel::Informational,
                "suggested" => AttentionLevel::Suggested,
                "required" => AttentionLevel::Required,
                "urgent" => AttentionLevel::Urgent,
                _ => AttentionLevel::None,
            },
            reason: facets.attention_reason.map(str::to_string),
            title: facets.attention_title.map(str::to_string),
            summary: facets.attention_summary.clone(),
            deferrable: None,
            deadline: None,
        },
        health: match facets.health {
            "degraded" => Health::Degraded,
            "unresponsive" => Health::Unresponsive,
            _ => Health::Ok,
        },
        outcome: facets.outcome.map(|o| match o {
            "success" => Outcome::Success,
            "cancelled" => Outcome::Cancelled,
            "partial" => Outcome::Partial,
            "failure" => Outcome::Failure,
            _ => Outcome::Unknown,
        }),
        progress: Progress {
            kind: ProgressKind::None,
            ratio: None,
            label: None,
            metrics: None,
        },
        producer: ProducerInfo {
            id: producer.id().into(),
            name: Some(producer.name().into()),
            kind: Some(producer.kind().into()),
        },
        context: Some(ContextInfo {
            project: Some(project),
            workspace: (!cwd.is_empty()).then_some(cwd),
            labels: Some(vec![producer.key().into(), "session".into()]),
        }),
        location: Some(location),
        capabilities: Vec::new(),
        actions: local_actions(),
        created_at: now,
        started_at: Some(now),
        ended_at: facets.ended.then_some(now),
        updated_at: now,
        version: (clock.now().unix_timestamp_nanos() / 1_000_000) as u64,
        extensions,
    }
}

fn location(payload: &Value, producer: Producer, cwd: &str, project: &str) -> LocationInfo {
    let host = "session";
    let mut focus_hint = format!("{} · {project} · {host}", producer.name());
    if !cwd.is_empty() {
        focus_hint = format!("{focus_hint} · {cwd}");
    }
    let open_url = path::to_file_uri(cwd);
    LocationInfo {
        open_url,
        focus_hint: Some(focus_hint),
        log_path: get_text(payload, &["transcript_path", "transcriptPath"]),
    }
}

fn local_actions() -> Vec<JobAction> {
    vec![
        JobAction {
            id: "open".into(),
            title: "Open".into(),
            kind: "open".into(),
            state: ActionState::Available,
            destructive: false,
            confirmation_required: false,
        },
        JobAction {
            id: "copy".into(),
            title: "Copy".into(),
            kind: "copy_summary".into(),
            state: ActionState::Available,
            destructive: false,
            confirmation_required: false,
        },
    ]
}

/// Slot key: producer + workspace. HTTP hooks have no terminal env; Codex
/// command can still distinguish windows via cwd + session file.
pub fn slot_id(producer: Producer, payload: &Value) -> String {
    let cwd = cwd(payload);
    format!("{}:{cwd}", producer.key())
}

pub fn ended_supersede(
    payload: &Value,
    producer: Producer,
    previous: &str,
    clock: &dyn Clock,
) -> Job {
    let facets = Facets {
        lifecycle: "ended",
        current_type: "idle",
        current_name: None,
        current_summary: Some("Session ended (superseded)".into()),
        attention_level: "none",
        attention_reason: None,
        attention_title: None,
        attention_summary: None,
        health: "ok",
        outcome: Some("cancelled"),
        ended: true,
        end_reason: Some("superseded".into()),
    };
    let mut job = build_job(payload, producer, clock, &facets, previous);
    job.extensions
        .insert("endReason".into(), json!("superseded"));
    job
}
