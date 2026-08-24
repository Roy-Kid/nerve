//! Host-event JSON: Claude / Codex / Grok all POST slightly different spellings.

use serde_json::Value;

/// First present, non-empty string among `keys`.
pub fn get_str<'a>(payload: &'a Value, keys: &[&str]) -> Option<&'a str> {
    let obj = payload.as_object()?;
    for key in keys {
        match obj.get(*key) {
            Some(Value::String(s)) if !s.is_empty() => return Some(s.as_str()),
            _ => {}
        }
    }
    None
}

/// Like [`get_str`] but `Display`s non-strings.
pub fn get_text(payload: &Value, keys: &[&str]) -> Option<String> {
    let obj = payload.as_object()?;
    for key in keys {
        match obj.get(*key) {
            Some(Value::Null) | None => continue,
            Some(Value::String(s)) if s.is_empty() => continue,
            Some(Value::String(s)) => return Some(s.clone()),
            Some(other) => return Some(other.to_string()),
        }
    }
    None
}

pub fn get_object<'a>(payload: &'a Value, keys: &[&str]) -> Option<&'a Value> {
    let obj = payload.as_object()?;
    for key in keys {
        match obj.get(*key) {
            Some(v) if v.is_object() => return Some(v),
            _ => {}
        }
    }
    None
}

pub fn event_name(payload: &Value) -> String {
    let raw = get_str(
        payload,
        &["hook_event_name", "hookEventName", "event", "event_name"],
    )
    .unwrap_or("");
    raw.chars()
        .filter(|c| !matches!(c, '_' | '-' | ' '))
        .flat_map(|c| c.to_lowercase())
        .collect()
}

pub fn session_id(payload: &Value) -> String {
    if let Some(sid) = get_text(
        payload,
        &[
            "session_id",
            "sessionId",
            "conversation_id",
            "conversationId",
            "thread_id",
            "threadId",
        ],
    ) {
        return sid;
    }
    let cwd = cwd(payload);
    format!("anon-{}", cwd.len().wrapping_mul(1_000_003) % 10_000_000)
}

pub fn cwd(payload: &Value) -> String {
    if let Some(cwd) = get_str(
        payload,
        &[
            "cwd",
            "working_directory",
            "workspaceRoot",
            "workspace_root",
        ],
    ) {
        return cwd.to_string();
    }
    if let Some(roots) = payload
        .get("workspace_roots")
        .or_else(|| payload.get("workspaceRoots"))
        .and_then(Value::as_array)
    {
        if let Some(Value::String(first)) = roots.first() {
            return first.clone();
        }
    }
    String::new()
}

pub fn agent_id(payload: &Value) -> Option<String> {
    get_str(payload, &["agent_id", "agentId"])
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

pub fn agent_type(payload: &Value) -> Option<String> {
    get_str(payload, &["agent_type", "agentType"])
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

pub fn notification_type(payload: &Value) -> String {
    get_str(payload, &["notification_type", "notificationType"])
        .unwrap_or("")
        .trim()
        .to_ascii_lowercase()
        .replace('-', "_")
}

pub fn background_tasks(payload: &Value) -> &[Value] {
    payload
        .get("background_tasks")
        .or_else(|| payload.get("backgroundTasks"))
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or(&[])
}

pub fn project_name(cwd: &str) -> &str {
    if cwd.is_empty() {
        return "unknown";
    }
    cwd.rsplit('/').find(|s| !s.is_empty()).unwrap_or("unknown")
}

pub fn truncate(s: &str, n: usize) -> String {
    let collapsed: String = s.split_whitespace().collect::<Vec<_>>().join(" ");
    if collapsed.chars().count() <= n {
        return collapsed;
    }
    let mut out = String::new();
    for (i, ch) in collapsed.chars().enumerate() {
        if i + 1 >= n {
            out.push('…');
            break;
        }
        out.push(ch);
    }
    out
}

/// Tool chatter inside a subagent is noise; permission / lifecycle still apply.
pub const SUBAGENT_NOISE: &[&str] = &[
    "pretooluse",
    "posttooluse",
    "posttoolusefailure",
    "userpromptsubmit",
];

pub fn skip_subagent_noise(event: &str, payload: &Value) -> bool {
    agent_id(payload).is_some() && SUBAGENT_NOISE.contains(&event)
}
