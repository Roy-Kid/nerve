//! Reading the hub and resetting it: health, the job list, refresh, demo, clear.

use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::lifecycle::NotifyPolicy;

use super::HubState;

/// Pinned by the contract, not by the crate version: producers, the site
/// handbook and `verify_loop.sh` all match this exact literal
/// (`IngestServer.swift:168`).
const SERVICE_VERSION: &str = "0.1.0";

pub(super) async fn health(State(state): State<HubState>) -> (StatusCode, Json<Value>) {
    let lease = state.roster().lease();
    (
        StatusCode::OK,
        Json(json!({
            "ok": true,
            "service": "nerve",
            "version": SERVICE_VERSION,
            "watchers": lease.watchers,
            "notify": lease.to_json(),
        })),
    )
}

/// Every stored job as a **bare array** — never an object wrapper — each with
/// the timeline the hub maintains for it.
pub(super) async fn jobs(State(state): State<HubState>) -> (StatusCode, Json<Value>) {
    let jobs = state.store().jobs_json();
    (StatusCode::OK, Json(jobs))
}

/// Surface Refresh: run the maintenance tick now, always republish a frame,
/// and answer the same bare job array as `GET /v1/jobs`.
///
/// The panel's refresh is this write, not a local re-read. Reaping dead local
/// PIDs and expiring pending requests is hub work; a GET would just echo
/// whatever was already in RAM.
pub(super) async fn refresh(State(state): State<HubState>) -> (StatusCode, Json<Value>) {
    let changed = state.store().expire_and_reap();
    state.changed();
    tracing::info!(changed, "refresh");
    (StatusCode::OK, Json(state.store().jobs_json()))
}

/// Seed the four demo rows (`SubjectStore.swift:1039`). The body is ignored:
/// this route is a button, not a report.
pub(super) async fn demo(State(state): State<HubState>) -> (StatusCode, Json<Value>) {
    state.store().load_demo();
    state.changed();
    tracing::info!("demo loaded");
    (StatusCode::OK, Json(json!({ "ok": true, "demo": true })))
}

/// Drop every job, timeline, pending request and seen event id.
pub(super) async fn clear(State(state): State<HubState>) -> (StatusCode, Json<Value>) {
    state.store().clear();
    state.changed();
    tracing::info!("cleared");
    (StatusCode::OK, Json(json!({ "ok": true })))
}

/// The live notify lease: policy, elected owner, connected surface labels.
pub(super) async fn notify(State(state): State<HubState>) -> (StatusCode, Json<Value>) {
    (StatusCode::OK, Json(state.roster().lease().to_json()))
}

#[derive(Deserialize)]
pub(super) struct NotifyBody {
    policy: String,
}

/// Replace the notify policy. Surfaces learn the new owner on the next frame.
pub(super) async fn put_notify(
    State(state): State<HubState>,
    Json(body): Json<NotifyBody>,
) -> (StatusCode, Json<Value>) {
    let Some(policy) = NotifyPolicy::parse(&body.policy) else {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": "unknown notify policy" })),
        );
    };
    tracing::info!(policy = body.policy, "notify policy");
    state.roster().set_policy(policy);
    (StatusCode::OK, Json(state.roster().lease().to_json()))
}
