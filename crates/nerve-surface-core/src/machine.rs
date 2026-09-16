//! Which machine this surface is looking at.
//!
//! A surface can only reach the panes of the machine it runs on, and the hub's
//! job list is not that narrow: a producer on another host reaches the same
//! loopback port through its RemoteForward tunnel, so its jobs arrive here
//! carrying *its* alias. Every pane-matching decision therefore starts with the
//! question `crates/nerve-hub/src/state/reaper.rs` asks before it trusts a pid —
//! "is this job even on my machine?" — because a foreign pid and a foreign
//! workspace path can both collide with a local pane by accident.
//!
//! Resolution copies the hub
//! (`crates/nerve-hub/src/state/machine.rs`) — Bonjour LocalHostName on macOS,
//! else the short hostname. Unlike the hub there is no `local` fallback: a
//! machine that will not name itself answers `None`, and nothing is foreign to
//! a surface that does not know its own name. That is fail-open on purpose —
//! the worst an unnamed machine gets is the pane matching it had before.

use std::process::Command;
use std::sync::OnceLock;

/// This machine's alias, resolved once per process.
///
/// A subprocess answers it, so it is cached exactly like the hub caches its own
/// (resolved at assembly, never asked again). `None` means the OS would not say.
pub fn local_alias() -> Option<&'static str> {
    static ALIAS: OnceLock<Option<String>> = OnceLock::new();
    ALIAS.get_or_init(resolve).as_deref()
}

/// The alias of the machine a job runs on, when that is not `local`.
///
/// `None` covers all three "treat it as mine" cases: the job named no machine,
/// it named this one, or this machine has no name to compare against. The
/// comparison is a pure function of two names — callers pass [`local_alias`],
/// which is what makes every decision built on it testable without a hostname.
pub fn foreign_alias<'a>(job_alias: &'a str, local: Option<&str>) -> Option<&'a str> {
    let alias = job_alias.trim();
    if alias.is_empty() {
        return None;
    }
    let local = local?;
    (!same_alias(alias, local)).then_some(alias)
}

/// Whether two aliases name the same machine.
///
/// Compared the way they are produced: case-insensitively, and only over the
/// characters an alias may contain — the hub sanitises what it fills in
/// (`state/machine.rs`) while the hook posts the raw name, so the same machine
/// can be spelled two ways on the wire.
pub fn same_alias(left: &str, right: &str) -> bool {
    sanitize(left).eq_ignore_ascii_case(&sanitize(right))
}

/// Alphanumerics plus `.`, `-` and `_` (`MachineConfig.swift:76`).
fn sanitize(raw: &str) -> String {
    raw.trim()
        .chars()
        .filter(|character| character.is_alphanumeric() || matches!(character, '.' | '-' | '_'))
        .collect()
}

fn resolve() -> Option<String> {
    bonjour_local_host_name()
        .or_else(short_hostname)
        .map(|name| sanitize(&name))
        .filter(|alias| !alias.is_empty())
}

/// macOS's stable Bonjour name, which survives DHCP renaming — the same source
/// the hook prefers, so a job's alias and this answer agree.
#[cfg(target_os = "macos")]
fn bonjour_local_host_name() -> Option<String> {
    first_line(Command::new("/usr/sbin/scutil").args(["--get", "LocalHostName"]))
}

#[cfg(not(target_os = "macos"))]
fn bonjour_local_host_name() -> Option<String> {
    None
}

/// The hostname up to its first dot.
fn short_hostname() -> Option<String> {
    let host = first_line(&mut Command::new("hostname"))?;
    host.split('.')
        .next()
        .filter(|short| !short.is_empty())
        .map(str::to_string)
}

/// First non-empty line of a command's output, or nothing if it could not run.
fn first_line(command: &mut Command) -> Option<String> {
    let output = command.output().ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8(output.stdout).ok()?;
    let line = text.lines().next()?.trim().to_string();
    (!line.is_empty()).then_some(line)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_same_machine_spelled_two_ways_is_one_machine() {
        assert!(same_alias("RoydeMacBook-Air", "roydemacbook-air"));
        assert!(same_alias(" arrhenius1 ", "arrhenius1"));
        // The hub strips what an alias may not contain; the hook does not.
        assert!(same_alias("Roy's-Air", "Roys-Air"));
    }

    #[test]
    fn different_machines_stay_different() {
        assert!(!same_alias("arrhenius1", "arrhenius2"));
        assert!(!same_alias("RoydeMacBook-Air", "arrhenius1"));
    }

    #[test]
    fn a_job_that_named_no_machine_is_never_foreign() {
        assert_eq!(foreign_alias("", Some("RoydeMacBook-Air")), None);
        assert_eq!(foreign_alias("   ", Some("RoydeMacBook-Air")), None);
    }

    #[test]
    fn nothing_is_foreign_to_a_machine_that_cannot_name_itself() {
        assert_eq!(foreign_alias("arrhenius1", None), None);
    }

    #[test]
    fn another_machine_is_reported_under_its_own_name() {
        assert_eq!(
            foreign_alias(" arrhenius1 ", Some("RoydeMacBook-Air")),
            Some("arrhenius1")
        );
        assert_eq!(
            foreign_alias("RoydeMacBook-Air", Some("roydemacbook-air")),
            None
        );
    }
}
