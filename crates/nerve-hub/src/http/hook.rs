//! `POST /v1/hook` — native host events from Claude / Grok HTTP hooks
//! and from `nerve-hub hook` (Codex).

use axum::body::Bytes;
use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::hook::{self, Producer};

use super::HubState;

type Reply = (StatusCode, Json<Value>);

#[derive(Debug, Deserialize)]
pub(super) struct ProducerQuery {
    producer: Option<String>,
}

pub(super) async fn ingest(
    State(state): State<HubState>,
    Query(query): Query<ProducerQuery>,
    body: Bytes,
) -> Reply {
    let payload: Value = match serde_json::from_slice(&body) {
        Ok(obj @ Value::Object(_)) => obj,
        _ => {
            return (StatusCode::OK, Json(json!({ "applied": 0 })));
        }
    };
    let producer = query
        .producer
        .as_deref()
        .map(Producer::parse)
        .unwrap_or_else(Producer::from_env);
    let applied = hook::apply(&mut state.store(), &mut state.slots(), producer, &payload);
    if applied > 0 {
        state.changed();
    }
    (StatusCode::OK, Json(json!({ "applied": applied })))
}
