//! `locate.rs` — finding the hub binary (spec T4 · acceptance A3).
//!
//! The rule under test is the *order*: install directories first, then a
//! `cargo install`, then whatever the user's shell would have found. First hit
//! wins, and not finding it is a fail-open state rather than an error (spec
//! Open questions 1).
//!
//! That rule is the same on every platform, so the bulk of this file injects
//! its own directory list through `with_fixed_directories` and never names a
//! real one. Two small tests at the end pin what each platform actually
//! searches; they are the only part that knows an OS.
//!
//! Determinism: a fake probe over a literal path set, an injected home, no
//! filesystem, no `PATH`, no clock, no socket.

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use nerve_surface_core::locate::{BINARY, BinaryProbe, HubLocator, platform_fixed_directories};

const HOME: &str = "/Users/tester";

/// The two injected install directories, standing in for whatever a platform
/// really uses.
fn install_dirs() -> Vec<PathBuf> {
    vec![
        PathBuf::from("/install/first"),
        PathBuf::from("/install/second"),
    ]
}

fn first() -> PathBuf {
    PathBuf::from("/install/first").join(BINARY)
}

fn second() -> PathBuf {
    PathBuf::from("/install/second").join(BINARY)
}

fn cargo() -> PathBuf {
    PathBuf::from(HOME).join(".cargo/bin").join(BINARY)
}

fn from_path() -> PathBuf {
    PathBuf::from("/Users/tester/bin").join(BINARY)
}

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
    fn new(executable: &[PathBuf], on_path: Option<PathBuf>) -> (Self, Asked) {
        let asked: Asked = Rc::new(RefCell::new(Vec::new()));
        let probe = Self {
            executable: executable.to_vec(),
            on_path,
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

fn locate(executable: &[PathBuf], on_path: Option<PathBuf>) -> Option<PathBuf> {
    let (probe, _) = FakeProbe::new(executable, on_path);
    HubLocator::with_fixed_directories(probe, HOME, install_dirs()).locate()
}

fn probed(executable: &[PathBuf], on_path: Option<PathBuf>) -> Vec<PathBuf> {
    let (probe, asked) = FakeProbe::new(executable, on_path);
    let _ = HubLocator::with_fixed_directories(probe, HOME, install_dirs()).locate();

    asked.borrow().clone()
}

// ── Discovery order ─────────────────────────────────────────────────────────

/// Acceptance A3: every candidate directory holds a hub, and the first
/// install directory wins.
#[test]
fn test_the_first_install_directory_wins_when_every_candidate_exists() {
    let found = locate(&[first(), second(), cargo()], Some(from_path()));

    assert_eq!(found, Some(first()));
}

#[test]
fn test_the_second_install_directory_is_next() {
    let found = locate(&[second(), cargo()], Some(from_path()));

    assert_eq!(found, Some(second()));
}

#[test]
fn test_cargo_bin_comes_after_the_install_directories() {
    let found = locate(&[cargo()], Some(from_path()));

    assert_eq!(found, Some(cargo()));
}

/// Acceptance A3: only `PATH` answers, so `PATH` is what the surface uses.
#[test]
fn test_path_is_the_last_resort() {
    let found = locate(&[], Some(from_path()));

    assert_eq!(found, Some(from_path()));
}

#[test]
fn test_nothing_installed_locates_nothing() {
    assert_eq!(locate(&[], None), None);
}

// ── How the search asks ─────────────────────────────────────────────────────

#[test]
fn test_the_candidates_are_probed_in_order() {
    let asked = probed(&[], None);

    assert_eq!(asked, vec![first(), second(), cargo()]);
}

/// A hit short-circuits: a locator that already found the first hub must not
/// go on touching the filesystem.
#[test]
fn test_a_hit_stops_the_search() {
    let asked = probed(&[first(), second(), cargo()], Some(from_path()));

    assert_eq!(asked, vec![first()]);
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

/// A different home moves only the `cargo install` candidate.
#[test]
fn test_the_cargo_candidate_follows_the_injected_home() {
    let expected = PathBuf::from("/var/root").join(".cargo/bin").join(BINARY);
    let (probe, _) = FakeProbe::new(std::slice::from_ref(&expected), None);
    let locator = HubLocator::with_fixed_directories(probe, "/var/root", install_dirs());

    assert_eq!(locator.locate(), Some(expected));
}

// ── What each platform really searches ──────────────────────────────────────

/// The hub ships as `nerve-hub` everywhere but Windows, where `PATH` lookup
/// and `metadata()` both need the suffix.
#[test]
fn test_the_binary_name_carries_the_platform_suffix() {
    if cfg!(windows) {
        assert_eq!(BINARY, "nerve-hub.exe");
    } else {
        assert_eq!(BINARY, "nerve-hub");
    }
}

#[cfg(unix)]
#[test]
fn test_unix_searches_both_homebrew_prefixes_in_order() {
    assert_eq!(
        platform_fixed_directories(),
        vec![
            PathBuf::from("/opt/homebrew/bin"),
            PathBuf::from("/usr/local/bin"),
        ],
        "Apple silicon Homebrew first, Intel Homebrew second"
    );
}

#[cfg(windows)]
#[test]
fn test_windows_searches_the_install_directories_it_can_resolve() {
    // Both entries come from environment variables, so a stripped environment
    // legitimately yields none. What must hold is that nothing bogus is
    // offered and that `~/.cargo/bin` plus `PATH` still carry the search.
    for directory in platform_fixed_directories() {
        assert!(
            directory.ends_with("Programs/Nerve") || directory.ends_with("Programs\\Nerve"),
            "unexpected Windows install directory {}",
            directory.display()
        );
    }
}
