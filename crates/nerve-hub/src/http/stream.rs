//! `GET /v1/stream` — the SSE surface.
//!
//! Its own router rather than a row in [`super::routes`]: this route needs the
//! frame pump and the surface count, which no other route may reach, while the
//! contract table needs only the store. The two cross-cutting guards are
//! applied here as well, so merging the two routers still leaves no route
//! unguarded and no answer carrying two CORS headers.

use std::convert::Infallible;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};

use axum::extract::{Query, State};
use axum::response::sse::{Event, KeepAlive, KeepAliveStream, Sse};
use axum::routing::get;
use axum::{Router, middleware};
use futures_core::Stream;
use serde::Deserialize;
use tokio::sync::broadcast::error::RecvError;
use tokio::sync::{broadcast, mpsc};

use crate::lifecycle::{RosterGuard, SurfaceRoster};
use crate::sse::Broadcaster;

use super::{guard, routes};

/// Frames one connection may be behind before it blocks its relay. Small: a
/// surface that cannot keep up with two frames is better resynchronised than
/// caught up.
const CONNECTION_BACKLOG: usize = 4;

/// What `GET /v1/stream` needs: frames to send, and the presence count a live
/// stream holds open.
#[derive(Clone)]
pub struct StreamState {
    frames: Arc<Broadcaster>,
    roster: SurfaceRoster,
}

impl StreamState {
    pub fn new(frames: Arc<Broadcaster>, roster: SurfaceRoster) -> Self {
        Self { frames, roster }
    }
}

/// The stream route, guarded exactly like the contract table.
pub fn stream_router(state: StreamState) -> Router {
    Router::new()
        .route("/v1/stream", get(stream))
        // The table's answer for a known path with the wrong method, so merging
        // the two routers does not leave one route answering 405 and the rest
        // 404. The unknown-path fallback stays in `routes.rs`: two of those
        // cannot be merged, and there is only one of them.
        .method_not_allowed_fallback(routes::not_found)
        .with_state(state)
        .layer(middleware::from_fn(guard::loopback_only))
        .layer(middleware::from_fn(guard::allow_any_origin))
}

/// `?surface=<label>` names this connection for the notify lease. Every
/// surface still sees every frame — there is no per-surface job filtering.
#[derive(Debug, Deserialize)]
struct SurfaceQuery {
    surface: Option<String>,
}

async fn stream(
    State(state): State<StreamState>,
    Query(query): Query<SurfaceQuery>,
) -> Sse<KeepAliveStream<FrameStream>> {
    let label = query.surface.as_deref().unwrap_or("anonymous");
    let presence = state.roster.subscribe(label);
    tracing::info!(surface = label, "surface attached");

    let (updates, connect) = state.frames.join();
    let (outgoing, incoming) = mpsc::channel(CONNECTION_BACKLOG);
    // The connect frame is queued before the relay starts, so a surface that
    // never sees another change still renders the current state.
    let _ = outgoing.try_send(connect);
    tokio::spawn(relay(Arc::clone(&state.frames), updates, outgoing));

    Sse::new(FrameStream {
        frames: incoming,
        _presence: presence,
    })
    .keep_alive(KeepAlive::new())
}

/// Feed one connection until it goes away.
///
/// A task per connection rather than a shared loop: it is what lets a slow
/// surface be resynchronised on its own without holding up the others, and it
/// ends the moment its connection does.
async fn relay(
    frames: Arc<Broadcaster>,
    mut updates: broadcast::Receiver<Arc<str>>,
    outgoing: mpsc::Sender<Arc<str>>,
) {
    loop {
        let frame = tokio::select! {
            () = outgoing.closed() => return,
            received = updates.recv() => match received {
                Ok(frame) => frame,
                // Too far behind to catch up. `jobs` is authoritative, so one
                // fresh full frame restores this surface completely; all it
                // misses are the `departed` hints from the frames it skipped.
                Err(RecvError::Lagged(_)) => frames.resync(),
                Err(RecvError::Closed) => return,
            },
        };
        if outgoing.send(frame).await.is_err() {
            return;
        }
    }
}

/// The response body: the frames this connection has not written yet, and the
/// presence reference it holds.
///
/// Dropping the body — which is what a disconnect does — releases the
/// reference, so the lifecycle needs no notion of sockets at all.
struct FrameStream {
    frames: mpsc::Receiver<Arc<str>>,
    _presence: RosterGuard,
}

impl Stream for FrameStream {
    type Item = Result<Event, Infallible>;

    fn poll_next(mut self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        self.frames
            .poll_recv(context)
            .map(|frame| frame.map(|frame| Ok(Event::default().data(frame))))
    }
}
