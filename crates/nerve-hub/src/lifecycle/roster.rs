//! Named surface connections, and the notify lease they produce.
//!
//! [`super::refcount::Presence`] still owns the *count* the grace timer
//! watches. This type hangs a label on each subscription and rebuilds the
//! [`super::notify::NotifyLease`] from the live set. Presence changes raise
//! the same [`ChangeSignal`] job writes do, so a surface connecting or
//! leaving republishes a frame even when no job moved — otherwise the
//! remaining surface would not learn it had become the notify owner until
//! the next snapshot.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use crate::sse::ChangeSignal;

use super::notify::{NotifyLease, NotifyPolicy, surface_label};
use super::refcount::{Presence, Subscription, Watchers};

/// Live surface connections plus the notify policy.
#[derive(Clone)]
pub struct SurfaceRoster {
    presence: Presence,
    inner: Arc<Mutex<Inner>>,
    next_id: Arc<AtomicU64>,
    changes: ChangeSignal,
}

struct Inner {
    names: HashMap<u64, String>,
    policy: NotifyPolicy,
}

impl SurfaceRoster {
    /// Nobody watching, default [`NotifyPolicy::Single`].
    pub fn new(changes: ChangeSignal) -> Self {
        Self {
            presence: Presence::new(),
            inner: Arc::new(Mutex::new(Inner {
                names: HashMap::new(),
                policy: NotifyPolicy::Single,
            })),
            next_id: Arc::new(AtomicU64::new(1)),
            changes,
        }
    }

    /// The presence count the grace timer already knows how to watch.
    pub fn presence(&self) -> Presence {
        self.presence.clone()
    }

    /// Follow the count — same channel [`Presence::watch`] publishes.
    pub fn watch(&self) -> tokio::sync::watch::Receiver<Watchers> {
        self.presence.watch()
    }

    /// One surface arrives, labelled with `?surface=`.
    pub fn subscribe(&self, surface: impl AsRef<str>) -> RosterGuard {
        let label = surface_label(Some(surface.as_ref()));
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let others = {
            let mut inner = self.lock();
            let others = inner.names.len();
            inner.names.insert(id, label.clone());
            others
        };
        let subscription = self.presence.subscribe();
        // 0→1 has nobody else to tell; the connect frame already carries
        // this surface. Raising here would republish ~150 ms later and
        // steal the next `frame()` from tests (and from surfaces) that
        // expect the next event to be a job write.
        if others > 0 {
            self.changes.raise();
        }
        RosterGuard {
            subscription: Some(subscription),
            id,
            label,
            inner: Arc::clone(&self.inner),
            changes: self.changes.clone(),
        }
    }

    /// The lease the next frame (and `/v1/health`) should carry.
    pub fn lease(&self) -> NotifyLease {
        let inner = self.lock();
        let watchers = inner.names.len();
        let surfaces: Vec<String> = inner.names.values().cloned().collect();
        NotifyLease::from_connections(inner.policy, watchers, surfaces)
    }

    /// Replace the policy. Returns `true` when it actually changed, so the
    /// caller can decide whether to publish a frame.
    pub fn set_policy(&self, policy: NotifyPolicy) -> bool {
        let mut inner = self.lock();
        if inner.policy == policy {
            return false;
        }
        inner.policy = policy;
        drop(inner);
        self.changes.raise();
        true
    }

    pub fn policy(&self) -> NotifyPolicy {
        self.lock().policy
    }

    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// One surface's presence, with its label.
///
/// Dropping it *is* the disconnect: the SSE response body owns one.
pub struct RosterGuard {
    subscription: Option<Subscription>,
    id: u64,
    label: String,
    inner: Arc<Mutex<Inner>>,
    changes: ChangeSignal,
}

impl Drop for RosterGuard {
    fn drop(&mut self) {
        let remaining = {
            let mut inner = self.inner.lock().unwrap_or_else(PoisonError::into_inner);
            inner.names.remove(&self.id);
            inner.names.len()
        };
        tracing::info!(surface = self.label.as_str(), remaining, "surface detached");
        // Count first, then the frame: a surface that just left must not
        // still be the notify owner on the frame this raise schedules.
        drop(self.subscription.take());
        if remaining > 0 {
            self.changes.raise();
        }
    }
}
