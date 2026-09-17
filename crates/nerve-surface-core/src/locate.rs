//! Finding the `nerve-hub` binary.
//!
//! The order copies the hub binary search: the platform's own install
//! directories first, a `cargo install` next, and only then whatever the user's
//! shell would have found. Not finding it is a fail-open state, not an error —
//! the surface paints its offline placeholder and the terminal, editor or
//! taskbar it lives in goes on working.

use std::env;
use std::path::{Path, PathBuf};

/// The binary this surface looks for.
#[cfg(windows)]
pub const BINARY: &str = "nerve-hub.exe";
/// The binary this surface looks for.
#[cfg(not(windows))]
pub const BINARY: &str = "nerve-hub";

/// Where a `cargo install` puts it, relative to the injected home.
const CARGO_BIN: &str = ".cargo/bin";

/// The install directories to try ahead of `~/.cargo/bin` and ahead of `PATH`.
///
/// On unix these are the two Homebrew prefixes. On Windows they are where an
/// installer would put it — **provisional** until the distribution story is
/// settled; until then `~/.cargo/bin` and `PATH` are what actually find it.
pub fn platform_fixed_directories() -> Vec<PathBuf> {
    #[cfg(windows)]
    {
        ["LOCALAPPDATA", "ProgramFiles"]
            .iter()
            .filter_map(|key| env::var_os(key))
            .map(|root| Path::new(&root).join("Programs").join("Nerve"))
            .collect()
    }
    #[cfg(not(windows))]
    {
        vec![
            PathBuf::from("/opt/homebrew/bin"),
            PathBuf::from("/usr/local/bin"),
        ]
    }
}

/// The only thing the search asks the filesystem.
pub trait BinaryProbe {
    /// Whether `path` names a file this process may execute.
    fn is_executable(&self, path: &Path) -> bool;
    /// The first `PATH` hit for `name`, as `which(1)` would answer it.
    fn on_path(&self, name: &str) -> Option<PathBuf>;
}

/// Searches the candidate directories in order, first hit wins.
pub struct HubLocator<P: BinaryProbe> {
    probe: P,
    home: PathBuf,
    fixed: Vec<PathBuf>,
}

impl<P: BinaryProbe> HubLocator<P> {
    /// `home` is what `~` expands to. Injected rather than read from the
    /// environment, so the search order is a unit test and not a machine.
    pub fn new(probe: P, home: impl Into<PathBuf>) -> Self {
        Self::with_fixed_directories(probe, home, platform_fixed_directories())
    }

    /// The same search against a caller-supplied install list.
    ///
    /// This is what lets the *ordering rule* be tested on any OS, instead of
    /// the test pinning one platform's directory names.
    pub fn with_fixed_directories(probe: P, home: impl Into<PathBuf>, fixed: Vec<PathBuf>) -> Self {
        Self {
            probe,
            home: home.into(),
            fixed,
        }
    }

    /// The hub binary, or `None` when nothing is installed.
    pub fn locate(&self) -> Option<PathBuf> {
        for directory in &self.fixed {
            let candidate = directory.join(BINARY);
            if self.probe.is_executable(&candidate) {
                return Some(candidate);
            }
        }
        let cargo = self.home.join(CARGO_BIN).join(BINARY);
        if self.probe.is_executable(&cargo) {
            return Some(cargo);
        }
        self.probe.on_path(BINARY)
    }
}

/// The probe the binary injects: the real filesystem and the real `PATH`.
pub struct FileProbe;

impl BinaryProbe for FileProbe {
    /// A regular file this process could plausibly run.
    ///
    /// The check is advisory either way — spawning is what really decides, and
    /// a refused spawn is already a fail-open state
    /// (`launch::Launch::Failed`) — so it asks the cheapest question each
    /// platform can answer honestly.
    fn is_executable(&self, path: &Path) -> bool {
        // Unix: the permission bits, read rather than `access(2)` called, so no
        // `unsafe` and no new dependency for an advisory check.
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;

            std::fs::metadata(path).is_ok_and(|metadata| {
                metadata.is_file() && metadata.permissions().mode() & 0o111 != 0
            })
        }
        // Windows: NTFS has no execute bit — `metadata().mode()` reports 0o666
        // for every real binary, so asking for one would reject them all.
        // Being a file is the honest answer; `BINARY` already carries `.exe`.
        #[cfg(not(unix))]
        {
            std::fs::metadata(path).is_ok_and(|metadata| metadata.is_file())
        }
    }

    fn on_path(&self, name: &str) -> Option<PathBuf> {
        let path = env::var_os("PATH")?;
        env::split_paths(&path)
            .map(|directory| directory.join(name))
            .find(|candidate| self.is_executable(candidate))
    }
}
