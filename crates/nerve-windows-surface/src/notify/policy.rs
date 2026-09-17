//! Whether to raise a toast, and what it says.
//!
//! Pure: a frame in, at most one toast per job out. The OS call is elsewhere,
//! so every rule below — the Ask gate, the dedupe window, the mute list — is a
//! test rather than something discovered by being interrupted.
//!
//! Default off. A Windows user very plausibly runs the VS Code extension on
//! the same machine, and peers do not know about each other (invariant 7), so
//! two toasts for one Ask is a worse first impression than none. The user
//! turns this on.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use nerve_surface_core::ask::{copy, should_notify};
use nerve_surface_core::frame::{AttentionLevel, JobView};

/// How long the same job and level stays quiet after firing.
pub const DEDUPE: Duration = Duration::from_secs(120);

/// What the surface hands the OS.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Toast {
    pub title: String,
    pub body: String,
    /// The job to open if the user acts on it.
    pub job_id: String,
    /// Replace-on-update key, also the dedupe key.
    pub tag: String,
    /// Whether this one may make a sound.
    pub sound: bool,
}

/// User choices this policy honours.
#[derive(Clone, Copy, Debug)]
pub struct Settings {
    /// Master switch. Off by default — see the module note.
    pub enabled: bool,
    /// Whether `required` and `urgent` may play the OS sound.
    pub sound: bool,
    /// Lowest level worth interrupting for.
    pub floor: AttentionLevel,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            enabled: false,
            sound: false,
            floor: AttentionLevel::Suggested,
        }
    }
}

/// Remembers what it has already said, so it does not say it again.
#[derive(Debug, Default)]
pub struct AskPolicy {
    previous: HashMap<String, JobView>,
    last_fired: HashMap<String, Instant>,
}

impl AskPolicy {
    pub fn new() -> Self {
        Self::default()
    }

    /// Feed one frame; get the toasts to raise.
    ///
    /// The previous snapshot is replaced whether or not anything fires — a
    /// disabled policy must still track state, or turning it on would toast
    /// every open Ask at once.
    pub fn evaluate(&mut self, jobs: &[JobView], settings: Settings, now: Instant) -> Vec<Toast> {
        let mut toasts = Vec::new();
        if settings.enabled {
            for job in jobs {
                if let Some(toast) = self.consider(job, settings, now) {
                    toasts.push(toast);
                }
            }
        }
        self.previous = jobs
            .iter()
            .map(|job| (job.id.clone(), job.clone()))
            .collect();
        // A job that left takes its dedupe entry with it, so the same id
        // returning later is heard rather than swallowed.
        self.last_fired
            .retain(|tag, _| jobs.iter().any(|job| tag.starts_with(&job.id)));
        toasts
    }

    fn consider(&mut self, job: &JobView, settings: Settings, now: Instant) -> Option<Toast> {
        if job.attention.level < settings.floor {
            return None;
        }
        if !should_notify(self.previous.get(&job.id), job) {
            return None;
        }
        // `wire()` is the level's one spelling; a second mapping here would be
        // a second thing to keep in step.
        let tag = format!("{}|{}", job.id, job.attention.level.wire());
        if let Some(last) = self.last_fired.get(&tag) {
            if now.duration_since(*last) < DEDUPE {
                return None;
            }
        }
        self.last_fired.insert(tag.clone(), now);

        let words = copy(job);
        Some(Toast {
            title: words.title,
            body: words.body,
            job_id: job.id.clone(),
            tag,
            sound: settings.sound && job.attention.level >= AttentionLevel::Required,
        })
    }
}
