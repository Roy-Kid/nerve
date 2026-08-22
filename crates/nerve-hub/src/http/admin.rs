//! Reading the hub and resetting it: health, the job list, demo, clear.

use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use serde_json::{json, Value};

use super::HubState;

/// Pinned by the contract, not by the crate version: producers, the site
/// handbook and `verify_loop.sh` all match this exact literal
/// (`IngestServer.swift:168`).
const SERVICE_VERSION: &str = "0.1.0";

pub(super) async fn health() -> (StatusCode, Json<Value>) {
    (
        StatusCode::OK,
        Json(json!({ "ok": true, "service": "nerve", "version": SERVICE_VERSION })),
    )
}

/// Every stored job as a **bare array** — never an object wrapper — each with
/// the timeline the hub maintains for it.
pub(super) async fn jobs(State(state): State<HubState>) -> (StatusCode, Json<Value>) {
    let jobs = state.store().jobs_json();
    (StatusCode::OK, Json(jobs))
}

/// Seed the four demo rows (`SubjectStore.swift:1039`). The body is ignored:
/// this route is a button, not a report.
pub(super) async fn demo(State(state): State<HubState>) -> (StatusCode, Json<Value>) {
    state.store().load_demo();
    state.changed();
    (StatusCode::OK, Json(json!({ "ok": true, "demo": true })))
}

/// Drop every job, timeline, pending request and seen event id.
pub(super) async fn clear(State(state): State<HubState>) -> (StatusCode, Json<Value>) {
    state.store().clear();
    state.changed();
    (StatusCode::OK, Json(json!({ "ok": true })))
}
