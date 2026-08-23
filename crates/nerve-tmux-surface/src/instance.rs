//! One surface per tmux server.
//!
//! The lock lives in a tmux user option, not in a file: this surface keeps no
//! state on disk (acceptance A11), and an option dies with the server it
//! belongs to — exactly the lock's intended lifetime.
//!
//! What the lock protects is the hub's refcount. A second surface that also
//! opened a stream would hold the hub alive after the first one left, so a
//! process that does not own the option must never open one.

use crate::tmux::{OptionStore, TmuxError};

/// The tmux user option that names the surface process.
pub const PID_OPTION: &str = "@nerve_surface_pid";

/// `kill(pid, 0)` — is that process still there?
pub trait PidProbe {
    fn is_alive(&self, pid: i32) -> bool;
}

/// The answer to "may this process be the surface?".
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Claim {
    /// This process owns the surface; the option now names our pid.
    Owned,
    /// A live surface already holds it: exit 0 having opened nothing.
    Yield { pid: i32 },
}

impl Claim {
    /// Whether the caller may open the SSE connection.
    pub fn may_stream(self) -> bool {
        matches!(self, Self::Owned)
    }
}

/// Takes, or stands down from, the single-surface lock.
pub struct InstanceGuard<O: OptionStore, P: PidProbe> {
    options: O,
    probe: P,
    me: i32,
}

impl<O: OptionStore, P: PidProbe> InstanceGuard<O, P> {
    /// `me` is this process's pid, injected rather than read, so the guard is a
    /// unit test rather than a process.
    pub fn new(options: O, probe: P, me: i32) -> Self {
        Self { options, probe, me }
    }

    /// Read the option and either take it or stand down.
    ///
    /// A yielding surface never rewrites the option: the pid recorded there
    /// belongs to the process that is doing the work.
    pub fn claim(&mut self) -> Result<Claim, TmuxError> {
        let stored = self.options.get(PID_OPTION)?;
        let owner = stored.as_deref().and_then(Self::pid);

        if let Some(pid) = owner {
            if pid != self.me && self.probe.is_alive(pid) {
                return Ok(Claim::Yield { pid });
            }
        }
        self.options.set(PID_OPTION, &self.me.to_string())?;
        Ok(Claim::Owned)
    }

    /// A stored value that could name a running surface.
    ///
    /// `pid <= 1` is never an owner — 0 is "no process" and 1 is init — the
    /// same rule the hub applies to producer pids
    /// (`crates/nerve-hub/src/model/job.rs:136`).
    fn pid(stored: &str) -> Option<i32> {
        stored.trim().parse::<i32>().ok().filter(|pid| *pid > 1)
    }
}

/// The probe the binary injects: `kill(pid, 0)`, the POSIX "does this process
/// exist" question.
///
/// Sends no signal. Anything other than "no such process" counts as alive: a
/// pid we may not signal is still running, and a second surface painting over
/// the first would be worse than a stale option nobody reads.
pub struct SignalProbe;

impl PidProbe for SignalProbe {
    fn is_alive(&self, pid: i32) -> bool {
        let Some(pid) = rustix::process::Pid::from_raw(pid) else {
            return false;
        };
        !matches!(
            rustix::process::test_kill_process(pid),
            Err(rustix::io::Errno::SRCH)
        )
    }
}
