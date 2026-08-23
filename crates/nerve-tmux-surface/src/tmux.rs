//! The only place this crate talks to tmux.
//!
//! Every invocation is an arg array — there is no shell anywhere in this crate,
//! the same rule `plugins/nerve/hooks/nerve_hook.py` follows. A segment holds
//! spaces and `#[…]` markers and must arrive as one argument, which a shell
//! line could never guarantee.
//!
//! Writing the option is not enough: tmux only repaints the status line after
//! `refresh-client -S`. Reading uses `show-options -gqv`, which prints the bare
//! value and stays quiet about options nobody set.
//!
//! tmux user options are also this surface's only persistent state, and they
//! live in tmux rather than on disk (acceptance A11) — an option dies with the
//! server it belongs to, which is exactly the intended lifetime.

use std::fmt;
use std::process::Command;

/// The user option `status-right` interpolates as `#{@nerve_status}`.
pub const STATUS_OPTION: &str = "@nerve_status";

/// What tmux(1) prints once its socket is gone.
const SERVER_GONE_PREFIX: &str = "no server running";

/// One `tmux` invocation.
pub trait TmuxRunner {
    /// Run `tmux <args>`, answering its trimmed stdout.
    fn run(&mut self, args: &[&str]) -> Result<String, TmuxError>;
}

/// Why a tmux invocation produced no answer.
#[derive(Debug)]
pub enum TmuxError {
    /// The tmux this surface painted is gone. Not a failure: the surface's
    /// work is simply over (exit 0).
    ServerGone,
    /// tmux could not be executed at all (missing binary, spawn refused).
    Unavailable(String),
    /// tmux ran and refused the command.
    Refused { status: i32, stderr: String },
}

impl TmuxError {
    /// Classify a finished invocation from its exit status and stderr.
    pub fn from_exit(status: i32, stderr: &str) -> Self {
        let stderr = stderr.trim();
        if stderr.to_ascii_lowercase().starts_with(SERVER_GONE_PREFIX) {
            return Self::ServerGone;
        }
        Self::Refused {
            status,
            stderr: stderr.to_string(),
        }
    }

    /// Whether this is the cue to stop painting and exit 0.
    pub fn is_server_gone(&self) -> bool {
        matches!(self, Self::ServerGone)
    }
}

impl fmt::Display for TmuxError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ServerGone => f.write_str("no server running"),
            Self::Unavailable(reason) => write!(f, "tmux unavailable: {reason}"),
            Self::Refused { status, stderr } => {
                write!(f, "tmux refused the command (exit {status}): {stderr}")
            }
        }
    }
}

impl std::error::Error for TmuxError {}

/// Where a rendered segment goes.
pub trait SegmentWriter {
    fn write_segment(&mut self, text: &str) -> Result<(), TmuxError>;
}

/// Global tmux user options.
pub trait OptionStore {
    fn get(&mut self, name: &str) -> Result<Option<String>, TmuxError>;
    fn set(&mut self, name: &str, value: &str) -> Result<(), TmuxError>;
}

/// Paints the status option, and reads and writes the surface's user options.
pub struct TmuxWriter<R: TmuxRunner> {
    runner: R,
}

impl<R: TmuxRunner> TmuxWriter<R> {
    pub fn new(runner: R) -> Self {
        Self { runner }
    }
}

impl<R: TmuxRunner> SegmentWriter for TmuxWriter<R> {
    /// `set -g @nerve_status <text>`, then `refresh-client -S`.
    ///
    /// An empty segment is still written: the status line has to be told to
    /// drop what it was showing. If the option could not be set there is
    /// nothing to refresh.
    fn write_segment(&mut self, text: &str) -> Result<(), TmuxError> {
        self.runner.run(&["set", "-g", STATUS_OPTION, text])?;
        self.runner.run(&["refresh-client", "-S"])?;
        Ok(())
    }
}

impl<R: TmuxRunner> OptionStore for TmuxWriter<R> {
    /// An unset option, and one set to blanks, read the same: absent.
    fn get(&mut self, name: &str) -> Result<Option<String>, TmuxError> {
        let value = self.runner.run(&["show-options", "-gqv", name])?;
        let value = value.trim();
        Ok((!value.is_empty()).then(|| value.to_string()))
    }

    /// Setting an option repaints nothing on its own, so it does not refresh.
    fn set(&mut self, name: &str, value: &str) -> Result<(), TmuxError> {
        self.runner.run(&["set", "-g", name, value])?;
        Ok(())
    }
}

/// The runner the binary injects: `tmux` itself.
///
/// `$TMUX` is inherited from the process tmux started, so every invocation
/// lands on the server this surface belongs to without naming a socket.
pub struct TmuxCommand;

impl TmuxRunner for TmuxCommand {
    fn run(&mut self, args: &[&str]) -> Result<String, TmuxError> {
        let output = Command::new("tmux")
            .args(args)
            .output()
            .map_err(|err| TmuxError::Unavailable(err.to_string()))?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(TmuxError::from_exit(
                output.status.code().unwrap_or(-1),
                &stderr,
            ));
        }
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    }
}
