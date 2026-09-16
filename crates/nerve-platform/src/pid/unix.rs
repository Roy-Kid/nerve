//! `kill(pid, 0)` — the POSIX "does this process exist" question.
//!
//! Sends no signal. It only asks the kernel to validate the pid and our right
//! to signal it.

use super::PidState;

pub fn state(pid: i32) -> PidState {
    // Not a process id at all: 0 means "our own group" and negatives mean a
    // group. Callers already refuse those, but the guard cannot be left to
    // `Pid::from_raw` — it debug-asserts `raw >= 0` rather than answering
    // `None`, so a negative pid panics instead of degrading.
    if pid <= 0 {
        return PidState::Denied;
    }
    let Some(pid) = rustix::process::Pid::from_raw(pid) else {
        return PidState::Denied;
    };
    match rustix::process::test_kill_process(pid) {
        Ok(()) => PidState::Alive,
        Err(rustix::io::Errno::SRCH) => PidState::Dead,
        Err(_) => PidState::Denied,
    }
}
