//! Action requests waiting on their owning producer.
//!
//! Ported whole but **dormant** (spec D6): nothing enqueues today because Nerve
//! is display-only — it never reverse-controls an agent. The queue keeps its
//! contract correct so `/v1/actions/*` answers honestly and a future spec can
//! decide, explicitly, whether to wake it.

use serde::Serialize;

use crate::model::{ActionState, WireTime};

/// Requests kept before the oldest are dropped (`SubjectStore.swift:29`).
pub const MAX_PENDING_ACTIONS: usize = 200;

/// How long a request stays answerable (`SubjectStore.swift:946`).
pub const PENDING_TTL_SECS: i64 = 3_600;

/// One user-requested action awaiting its producer.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PendingAction {
    pub id: String,
    pub job_id: String,
    /// Only this producer may complete the request.
    pub producer_id: String,
    pub action_id: String,
    pub action_kind: String,
    pub title: String,
    pub requested_at: WireTime,
    pub state: ActionState,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result_message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<WireTime>,
}

/// Which declared action a queue change refers to. The queue never touches a
/// job; it reports what the store must re-state.
#[derive(Clone, Debug)]
pub struct ActionRef {
    pub job_id: String,
    pub action_id: String,
    pub title: String,
}

/// The newest-first request queue.
#[derive(Debug, Default)]
pub struct PendingQueue {
    requests: Vec<PendingAction>,
}

impl PendingQueue {
    /// Queue a request, stamping the TTL the queue itself owns.
    pub fn enqueue(&mut self, request: PendingAction) {
        let expires_at = request.requested_at.plus_seconds(PENDING_TTL_SECS);
        let request = PendingAction {
            expires_at: Some(expires_at),
            ..request
        };
        self.requests.insert(0, request);
        self.requests.truncate(MAX_PENDING_ACTIONS);
    }

    /// Requests still awaiting an answer, newest first
    /// (`SubjectStore.swift:191`).
    pub fn open(&self, now: WireTime, producer_id: Option<&str>) -> Vec<&PendingAction> {
        self.requests
            .iter()
            .filter(|request| request.state == ActionState::Pending)
            .filter(|request| request.expires_at.is_none_or(|expiry| expiry >= now))
            .filter(|request| producer_id.is_none_or(|owner| request.producer_id == owner))
            .collect()
    }

    /// Mark every request past its TTL expired, and report which declared
    /// actions the store must re-state.
    pub fn expire(&mut self, now: WireTime) -> Vec<ActionRef> {
        let mut expired = Vec::new();
        for request in &mut self.requests {
            if request.state != ActionState::Pending {
                continue;
            }
            if request.expires_at.is_none_or(|expiry| expiry >= now) {
                continue;
            }
            request.state = ActionState::Expired;
            expired.push(ActionRef {
                job_id: request.job_id.clone(),
                action_id: request.action_id.clone(),
                title: request.title.clone(),
            });
        }
        expired
    }

    /// Record a producer's answer.
    ///
    /// `None` means the request is unknown, owned by another producer, or the
    /// reported state is not an ending — all of which the caller reports as a
    /// miss (`SubjectStore.swift:973`).
    pub fn complete(
        &mut self,
        id: &str,
        state: ActionState,
        message: Option<&str>,
        producer_id: Option<&str>,
    ) -> Option<ActionRef> {
        let request = self.requests.iter_mut().find(|request| request.id == id)?;
        if producer_id.is_some_and(|owner| request.producer_id != owner) {
            return None;
        }
        if !state.is_completion() {
            return None;
        }
        request.state = state;
        request.result_message = message.map(str::to_string);
        Some(ActionRef {
            job_id: request.job_id.clone(),
            action_id: request.action_id.clone(),
            title: request.title.clone(),
        })
    }

    pub fn clear(&mut self) {
        self.requests.clear();
    }
}
