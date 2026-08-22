//! The assembled hub: one store, one frame pump, one surface count, one timer.
//!
//! Everything below is wiring and scheduling. The rules live in the modules
//! being wired — what a frame says is [`crate::sse::Frame`]'s, when a hub stops
//! is [`crate::lifecycle`]'s, what a tick does is the store's — so this file
//! decides only who talks to whom, and how often.

use std::future::Future;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use axum::Router;
use tokio::task::JoinHandle;
use tokio::time::MissedTickBehavior;

use crate::http::{self, HubState, StreamState};
use crate::lifecycle::{ExitSignal, GraceTimer, Presence, Subscription};
use crate::sse::{Broadcaster, ChangeSignal};
use crate::state::JobStore;

/// A hub, running: routes to serve, surfaces to count, frames to push.
///
/// Its background work starts with it, so constructing one requires a tokio
/// runtime, and dropping one stops it.
pub struct HubRuntime {
    store: Arc<Mutex<JobStore>>,
    changes: ChangeSignal,
    frames: Arc<Broadcaster>,
    presence: Presence,
    exit: ExitSignal,
    background: Vec<JoinHandle<()>>,
}

impl HubRuntime {
    /// How often stale requests expire and dead local producers are reaped
    /// (`SubjectStore.swift:1021`).
    const MAINTENANCE_PERIOD: Duration = Duration::from_secs(5);

    /// Assemble a hub around `store` and start its background work.
    ///
    /// The grace timer is armed from here on: a surface may spawn a hub and die
    /// before it ever connects, and that hub must still go away.
    pub fn new(store: JobStore, grace: Duration) -> Self {
        let store = Arc::new(Mutex::new(store));
        let changes = ChangeSignal::new();
        let frames = Arc::new(Broadcaster::new(
            Arc::clone(&store),
            changes.clone(),
            Broadcaster::WINDOW,
        ));
        let presence = Presence::new();
        let exit = ExitSignal::new();

        let background = vec![
            tokio::spawn(Arc::clone(&frames).pump()),
            tokio::spawn(GraceTimer::new(grace, presence.watch(), exit.clone()).run()),
            tokio::spawn(
                Maintenance {
                    store: Arc::clone(&store),
                    changes: changes.clone(),
                    period: Self::MAINTENANCE_PERIOD,
                }
                .run(),
            ),
        ];

        Self {
            store,
            changes,
            frames,
            presence,
            exit,
            background,
        }
    }

    /// The hub's whole HTTP surface: the contract table plus `GET /v1/stream`.
    ///
    /// Callable as often as needed — every router shares this runtime's one
    /// store and one broadcaster, so a write through any of them reaches a
    /// stream served by any other.
    pub fn router(&self) -> Router {
        http::router(HubState::from_shared(
            Arc::clone(&self.store),
            self.changes.clone(),
        ))
        .merge(http::stream_router(StreamState::new(
            Arc::clone(&self.frames),
            self.presence.clone(),
        )))
    }

    /// Count one surface as present until the returned guard drops.
    ///
    /// The SSE route takes one per connection; a caller can take one directly
    /// to hold the hub open for its own reasons.
    pub fn subscribe(&self) -> Subscription {
        self.presence.subscribe()
    }

    /// Resolve when the hub has decided to stop.
    ///
    /// Observation only: asking has no effect on the count or the timer, and
    /// asking after the fact is answered immediately.
    pub fn shutdown(&self) -> impl Future<Output = ()> + Send + 'static {
        self.exit.wait()
    }
}

impl Drop for HubRuntime {
    /// A runtime that is gone has nothing left to pump, count or time.
    fn drop(&mut self) {
        for task in &self.background {
            task.abort();
        }
    }
}

/// The upkeep every hub does on a timer: expire stale requests, close rows
/// whose producer process is gone, and publish a frame when either changed
/// something.
struct Maintenance {
    store: Arc<Mutex<JobStore>>,
    changes: ChangeSignal,
    period: Duration,
}

impl Maintenance {
    async fn run(self) {
        let mut tick = tokio::time::interval(self.period);
        // A hub that was suspended (a laptop lid, a paused test clock) owes no
        // catch-up ticks: the next one re-reads the whole world anyway.
        tick.set_missed_tick_behavior(MissedTickBehavior::Skip);
        loop {
            tick.tick().await;
            let changed = self
                .store
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .expire_and_reap();
            if changed {
                self.changes.raise();
            }
        }
    }
}
