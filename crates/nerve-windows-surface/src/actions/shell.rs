//! Handing a target to the OS.
//!
//! `opener` calls `ShellExecuteW` internally rather than shelling out through
//! `cmd /C start`, which matters: `start` splits on `&` and would mangle — or
//! in the wrong hands, extend — a path that contains one.

use std::path::Path;

/// Somewhere a target can be opened. A trait so [`super::open::plan`]'s whole
/// decision table can be driven in a test without opening anything.
pub trait ShellOpener {
    /// A URL whose app resolves it, such as `vscode://file/C:/work`.
    fn open_url(&self, url: &str) -> bool;
    /// Open a directory in the file manager.
    ///
    /// Opened rather than revealed: `reveal` selects an entry inside its
    /// parent, and a job's location is the directory the work is happening in,
    /// not a file to point at.
    fn open_path(&self, path: &Path) -> bool;
}

/// The real OS.
#[derive(Debug, Default)]
pub struct SystemOpener;

impl ShellOpener for SystemOpener {
    fn open_url(&self, url: &str) -> bool {
        opener::open(url).is_ok()
    }

    fn open_path(&self, path: &Path) -> bool {
        opener::open(path).is_ok()
    }
}

/// Records instead of opening.
#[derive(Debug, Default)]
pub struct RecordingOpener {
    pub opened: std::cell::RefCell<Vec<String>>,
}

impl ShellOpener for RecordingOpener {
    fn open_url(&self, url: &str) -> bool {
        self.opened.borrow_mut().push(format!("url:{url}"));
        true
    }

    fn open_path(&self, path: &Path) -> bool {
        self.opened
            .borrow_mut()
            .push(format!("path:{}", path.display()));
        true
    }
}
