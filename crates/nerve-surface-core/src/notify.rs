//! Whether this surface may raise an interrupt for a frame.
//!
//! The hub elects an owner when `policy` is `single` (the default a current
//! hub sends). An older hub omits `notify` entirely; that decodes as `All`,
//! which is the historical "every surface decides for itself" rule.

use serde::Deserialize;

/// How the hub is spreading the interrupt channel.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NotifyPolicy {
    /// Every connected surface that has notifications on may fire.
    ///
    /// Default for a *missing* `notify` object, so a surface talking to an
    /// older hub does not go silent.
    #[default]
    All,
    /// Only [`NotifyLease::owner`] may fire.
    Single,
}

/// The lease one SSE frame (or `/v1/health`) carries.
#[derive(Clone, Debug, Default, PartialEq, Eq, Deserialize)]
pub struct NotifyLease {
    #[serde(default)]
    pub policy: NotifyPolicy,
    #[serde(default)]
    pub owner: Option<String>,
    #[serde(default)]
    pub surfaces: Vec<String>,
    #[serde(default)]
    pub watchers: usize,
}

impl NotifyLease {
    /// Whether `surface` may raise an OS (or in-app) interrupt for this frame.
    pub fn may_interrupt(&self, surface: &str) -> bool {
        match self.policy {
            NotifyPolicy::All => true,
            NotifyPolicy::Single => self.owner.as_deref() == Some(surface),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_notify_lets_everyone_fire() {
        let lease = NotifyLease::default();
        assert!(lease.may_interrupt("macos"));
        assert!(lease.may_interrupt("tether"));
    }

    #[test]
    fn single_only_the_owner() {
        let lease = NotifyLease {
            policy: NotifyPolicy::Single,
            owner: Some("macos".into()),
            surfaces: vec!["macos".into(), "tether".into()],
            watchers: 2,
        };
        assert!(lease.may_interrupt("macos"));
        assert!(!lease.may_interrupt("tether"));
    }
}
