//! Finding the `nerve-hub` binary.
//!
//! The order copies the hub binary search: Homebrew on Apple silicon
//! first, Intel Homebrew second, a `cargo install` third, and only then
//! whatever the user's shell would have found. Not finding it is a fail-open
//! state, not an error — the surface paints its offline placeholder and tmux
//! goes on working.

use std::env;
use std::path::{Path, PathBuf};

/// The binary this surface looks for.
pub const BINARY: &str = "nerve-hub";

/// The two fixed directories, ahead of `$HOME` and ahead of `PATH`.
const FIXED_DIRECTORIES: [&str; 2] = ["/opt/homebrew/bin", "/usr/local/bin"];

/// Where a `cargo install` puts it, relative to the injected home.
const CARGO_BIN: &str = ".cargo/bin";

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
}

impl<P: BinaryProbe> HubLocator<P> {
    /// `home` is what `~` expands to. Injected rather than read from the
    /// environment, so the search order is a unit test and not a machine.
    pub fn new(probe: P, home: impl Into<PathBuf>) -> Self {
        Self {
            probe,
            home: home.into(),
        }
    }

    /// The hub binary, or `None` when nothing is installed.
    pub fn locate(&self) -> Option<PathBuf> {
        for directory in FIXED_DIRECTORIES {
            let candidate = Path::new(directory).join(BINARY);
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
    /// A regular file with any execute bit set.
    ///
    /// The permission bits are read rather than `access(2)` called, so no
    /// `unsafe` and no new dependency enters the tree for a check that is
    /// advisory anyway: spawning is what really decides, and a refused spawn is
    /// already a fail-open state (`launch::Launch::Failed`).
    fn is_executable(&self, path: &Path) -> bool {
        use std::os::unix::fs::PermissionsExt as _;

        std::fs::metadata(path)
            .is_ok_and(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
    }

    fn on_path(&self, name: &str) -> Option<PathBuf> {
        let path = env::var_os("PATH")?;
        env::split_paths(&path)
            .map(|directory| directory.join(name))
            .find(|candidate| self.is_executable(candidate))
    }
}
