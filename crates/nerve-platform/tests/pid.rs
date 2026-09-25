//! Liveness, asked on whichever OS is running the suite.
//!
//! Every case here is written to mean the same thing on unix and on Windows, so
//! the Windows CI job exercises the Win32 probe with no separate suite.

use std::process::Command;

use nerve_platform::pid::{PidState, is_alive, state};

/// A child that has been waited on. On Windows the handle is only released by
/// the `wait`, which is the one place the two OSes differ in observable timing
/// — so the wait is the assertion, not an implementation detail.
fn reaped_child_pid() -> i32 {
    let mut command = if cfg!(windows) {
        let mut c = Command::new("cmd");
        c.args(["/C", "exit"]);
        c
    } else {
        Command::new("true")
    };
    let mut child = command.spawn().expect("spawn a process that exits at once");
    let pid = child.id() as i32;
    child.wait().expect("wait for it");
    pid
}

#[test]
fn our_own_process_is_alive() {
    let me = std::process::id() as i32;
    assert_eq!(state(me), PidState::Alive);
    assert!(is_alive(me));
}

#[test]
fn a_reaped_child_is_dead() {
    let pid = reaped_child_pid();
    assert_eq!(state(pid), PidState::Dead);
    assert!(!is_alive(pid));
}

#[test]
fn a_pid_that_names_no_process_is_never_alive() {
    // 0 means "our own group" on POSIX and nothing here; negatives name a
    // group. Callers already refuse these, so this pins the defensive answer.
    for pid in [0, -1, -12345] {
        assert_ne!(state(pid), PidState::Alive, "pid {pid}");
    }
}

#[test]
fn an_absurd_pid_answers_without_panicking() {
    // The contract is that a probe always answers. Which answer depends on the
    // OS's pid space, so this asserts only that asking is safe.
    let _ = state(i32::MAX);
}

#[cfg(unix)]
#[test]
fn init_exists_even_when_we_may_not_signal_it() {
    // pid 1 is always running and usually not ours to signal — exactly the
    // case the `Denied` state exists for.
    assert_ne!(state(1), PidState::Dead);
}
