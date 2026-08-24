//! `locate.rs` — finding the hub binary (spec T4 · acceptance A3).
//!
//! ─────────────────────────────────────────────────────────────────────────
//! API CONTRACT — the implementer fills `src/locate.rs` to satisfy this file.
//! Tests are never edited to fit an implementation.
//! ─────────────────────────────────────────────────────────────────────────
//!
//! ```ignore
//! // nerve_tmux_surface::locate
//!
//! /// The binary this surface looks for.
//! pub const BINARY: &str = "nerve-hub";
//!
//! /// The only thing the search asks the filesystem.
//! pub trait BinaryProbe {
//!     /// Whether `path` names a file this process may execute.
//!     fn is_executable(&self, path: &Path) -> bool;
//!     /// The first `PATH` hit for `name`, as `which(1)` would answer it.
//!     fn on_path(&self, name: &str) -> Option<PathBuf>;
//! }
//!
//! pub struct HubLocator<P: BinaryProbe> { /* probe, home */ }
//!
//! impl<P: BinaryProbe> HubLocator<P> {
//!     /// `home` is what `~` expands to. Injected rather than read from the
//!     /// environment, so the search order is a unit test and not a machine.
//!     pub fn new(probe: P, home: impl Into<PathBuf>) -> Self;
//!
//!     /// First hit wins, in this order (spec Design, `locate.rs`):
//!     ///   1. `/opt/homebrew/bin/nerve-hub`
//!     ///   2. `/usr/local/bin/nerve-hub`
//!     ///   3. `{home}/.cargo/bin/nerve-hub`
//!     ///   4. whatever `PATH` answers
//!     /// `None` means "not installed" — a fail-open state, not an error
//!     /// (spec Open questions 1).
//!     pub fn locate(&self) -> Option<PathBuf>;
//! }
//! ```
//!
//! The order copies `plugins/nerve/hooks/run.sh` (spec Reuse decision,
//! "自定位 + 候选序列 + fail-open"): Homebrew on Apple silicon first, Intel
//! Homebrew second, a `cargo install` third, and only then whatever the user's
//! shell would have found.
//!
//! Determinism: a fake probe over a literal path set, an injected home, no
//! filesystem, no `PATH`, no clock, no socket.

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use nerve_tmux_surface::locate::{BinaryProbe, HubLocator, BINARY};

const HOME: &str = "/Users/tester";

const BREW: &str = "/opt/homebrew/bin/nerve-hub";
const LOCAL: &str = "/usr/local/bin/nerve-hub";
const CARGO: &str = "/Users/tester/.cargo/bin/nerve-hub";
const FROM_PATH: &str = "/Users/tester/bin/nerve-hub";

/// Every path the locator probed, in order — shared with the test after the
/// probe has been moved into the locator.
type Asked = Rc<RefCell<Vec<PathBuf>>>;

/// A filesystem that exists only in this file.
struct FakeProbe {
    executable: Vec<PathBuf>,
    on_path: Option<PathBuf>,
    asked: Asked,
}

impl FakeProbe {
    fn new(executable: &[&str], on_path: Option<&str>) -> (Self, Asked) {
        let asked: Asked = Rc::new(RefCell::new(Vec::new()));
        let probe = Self {
            executable: executable.iter().map(PathBuf::from).collect(),
            on_path: on_path.map(PathBuf::from),
            asked: Rc::clone(&asked),
        };
        (probe, asked)
    }
}

impl BinaryProbe for FakeProbe {
    fn is_executable(&self, path: &Path) -> bool {
        self.asked.borrow_mut().push(path.to_path_buf());
        self.executable.iter().any(|known| known == path)
    }

    fn on_path(&self, name: &str) -> Option<PathBuf> {
        assert_eq!(name, BINARY, "PATH is searched for the hub binary only");
        self.on_path.clone()
    }
}

fn locate(executable: &[&str], on_path: Option<&str>) -> Option<PathBuf> {
    let (probe, _) = FakeProbe::new(executable, on_path);
    HubLocator::new(probe, HOME).locate()
}

fn probed(executable: &[&str], on_path: Option<&str>) -> Vec<PathBuf> {
    let (probe, asked) = FakeProbe::new(executable, on_path);
    let _ = HubLocator::new(probe, HOME).locate();
    let paths = asked.borrow().clone();
    paths
}

// ── Discovery order ─────────────────────────────────────────────────────────

#[test]
fn test_the_binary_looked_for_is_nerve_hub() {
    assert_eq!(BINARY, "nerve-hub");
}

/// Acceptance A3: all three candidate directories hold a hub, and Homebrew on
/// Apple silicon wins.
#[test]
fn test_homebrew_wins_when_every_candidate_exists() {
    let found = locate(&[BREW, LOCAL, CARGO], Some(FROM_PATH));

    assert_eq!(found, Some(PathBuf::from(BREW)));
}

#[test]
fn test_usr_local_is_second() {
    let found = locate(&[LOCAL, CARGO], Some(FROM_PATH));

    assert_eq!(found, Some(PathBuf::from(LOCAL)));
}

#[test]
fn test_cargo_bin_is_third_and_expands_the_injected_home() {
    let found = locate(&[CARGO], Some(FROM_PATH));

    assert_eq!(found, Some(PathBuf::from(CARGO)));
}

/// Acceptance A3: only `PATH` answers, so `PATH` is what the surface uses.
#[test]
fn test_path_is_the_last_resort() {
    let found = locate(&[], Some(FROM_PATH));

    assert_eq!(found, Some(PathBuf::from(FROM_PATH)));
}

#[test]
fn test_nothing_installed_locates_nothing() {
    assert_eq!(locate(&[], None), None);
}

// ── How the search asks ─────────────────────────────────────────────────────

#[test]
fn test_the_fixed_directories_are_probed_in_order() {
    let asked = probed(&[], None);

    assert_eq!(
        asked,
        vec![
            PathBuf::from(BREW),
            PathBuf::from(LOCAL),
            PathBuf::from(CARGO),
        ]
    );
}

/// A hit short-circuits: a locator that already found Homebrew's hub must not
/// go on touching the filesystem.
#[test]
fn test_a_hit_stops_the_search() {
    let asked = probed(&[BREW, LOCAL, CARGO], Some(FROM_PATH));

    assert_eq!(asked, vec![PathBuf::from(BREW)]);
}

/// `~` is a shell convenience, never a path: the tilde must be expanded before
/// anything is probed.
#[test]
fn test_no_probed_path_ever_contains_a_tilde() {
    for path in probed(&[], None) {
        assert!(
            !path.to_string_lossy().contains('~'),
            "unexpanded tilde in {}",
            path.display()
        );
    }
}

/// A different home moves only the third candidate.
#[test]
fn test_the_cargo_candidate_follows_the_injected_home() {
    let (probe, _) = FakeProbe::new(&["/var/root/.cargo/bin/nerve-hub"], None);
    let locator = HubLocator::new(probe, "/var/root");

    assert_eq!(
        locator.locate(),
        Some(PathBuf::from("/var/root/.cargo/bin/nerve-hub"))
    );
}
