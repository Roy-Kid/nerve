//! Composition root for the tmux surface.
//!
//! Assembly and process concerns only — every decision this binary appears to
//! make is one line of a module that can be unit tested without it.
//!
//! Two subcommands, both fail-open (CLAUDE.md invariant 2): whatever goes
//! wrong, tmux stays exactly as usable as it was.
//!
//! * `run` — claim the single-surface lock, make sure a hub is up, then hold
//!   one `GET /v1/stream?surface=tmux` open and paint `@nerve_status` on every
//!   frame. That held connection is this surface's refcount presence; dropping
//!   it is how the hub learns the surface left.
//! * `popup` — read `GET /v1/jobs` once, print the rows, exit. No tmux is
//!   touched, so `display-popup -E` works even where `run` could not.
//!
//! **No signal handler.** `unsafe` is forbidden workspace-wide and `std` has no
//! safe way to catch `SIGTERM`, so the default disposition is what ends this
//! process — which closes the socket, which is the only part the hub's refcount
//! cares about. `ServerGone` is the path that exits 0 deliberately.

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;
use std::thread;

use time::OffsetDateTime;

use nerve_tmux_surface::frame::JobView;
use nerve_tmux_surface::hub::Hub;
use nerve_tmux_surface::instance::{Claim, InstanceGuard, SignalProbe};
use nerve_tmux_surface::launch::{DetachedSpawner, HttpHealth, HubLauncher, SystemClock};
use nerve_tmux_surface::locate::{FileProbe, HubLocator};
use nerve_tmux_surface::popup::PopupRenderer;
use nerve_tmux_surface::stream::{Attempt, Backoff, HubFrameSource, StreamSession};
use nerve_tmux_surface::summary::SummaryRenderer;
use nerve_tmux_surface::tmux::{OptionStore, TmuxCommand, TmuxWriter};

const USAGE: &str = "\
nerve-tmux-surface - the tmux surface of the Nerve hub

Usage:
  nerve-tmux-surface run     Hold the status line: claim the single-surface
                             lock, attach to the hub's stream and paint
                             `@nerve_status` on every frame.
  nerve-tmux-surface popup   Print the current jobs once, for `display-popup -E`.

Both talk to the hub on 127.0.0.1:17890 and to nothing else. Neither can act on
a job: this surface displays.";

/// User option holding the `@nerve_status` template.
const FORMAT_OPTION: &str = "@nerve_status_format";
/// User option holding the text shown while no hub is reachable.
const OFFLINE_OPTION: &str = "@nerve_status_offline";
/// The hub's job list.
const JOBS_PATH: &str = "/v1/jobs";
/// What a popup prints when there is no hub to read.
const HUB_OFFLINE: &str = "nerve: hub offline";

/// Nothing here is a failure worth a non-zero status but an unusable command
/// line (`crates/nerve-hub/src/cli.rs` uses the same two codes).
const EXIT_OK: u8 = 0;
const EXIT_USAGE: u8 = 2;

fn main() -> ExitCode {
    match env::args().nth(1).as_deref() {
        Some("run") => run(),
        Some("popup") => popup(),
        Some("-h" | "--help") => {
            println!("{USAGE}");
            ExitCode::from(EXIT_OK)
        }
        _ => {
            eprintln!("{USAGE}");
            ExitCode::from(EXIT_USAGE)
        }
    }
}

/// Hold the status line until tmux goes away.
fn run() -> ExitCode {
    if !claim_surface() {
        return ExitCode::from(EXIT_OK);
    }

    let (template, offline) = surface_options();
    let locator = HubLocator::new(FileProbe, home());
    let mut launcher = HubLauncher::new(
        DetachedSpawner::new(),
        SystemClock,
        HttpHealth::new(Hub::loopback()),
    );
    let mut session = StreamSession::new(
        HubFrameSource::new(Hub::loopback()),
        TmuxWriter::new(TmuxCommand),
        SummaryRenderer::new(template),
        offline,
    );
    let mut backoff = Backoff::new();

    loop {
        // Located every round, not once: a hub installed while this surface is
        // waiting is found on the next attempt, and the launcher's own throttle
        // is what keeps a missing one from being fired at the OS.
        launcher.ensure(locator.locate().as_deref());

        match session.attach() {
            Attempt::ServerGone => return ExitCode::from(EXIT_OK),
            Attempt::Ended { frames } => {
                if frames > 0 {
                    backoff.reset();
                }
                thread::sleep(backoff.fail());
            }
        }
    }
}

/// Print the current jobs once.
fn popup() -> ExitCode {
    match jobs() {
        Ok(jobs) => print!(
            "{}",
            PopupRenderer::at(OffsetDateTime::now_utc()).render(&jobs)
        ),
        // A popup that cannot read the hub says so and still closes cleanly:
        // there is nothing here for a human to retry.
        Err(reason) => println!("{HUB_OFFLINE} ({reason})"),
    }
    ExitCode::from(EXIT_OK)
}

fn jobs() -> Result<Vec<JobView>, String> {
    let body = Hub::loopback()
        .get(JOBS_PATH)
        .map_err(|err| err.to_string())?;
    serde_json::from_str(&body).map_err(|err| err.to_string())
}

/// Whether this process may be the surface for this tmux server.
///
/// A tmux that will not answer is treated exactly like a live owner: stand
/// down, quietly, with nothing opened.
fn claim_surface() -> bool {
    let me = i32::try_from(std::process::id()).unwrap_or_default();
    let mut guard = InstanceGuard::new(TmuxWriter::new(TmuxCommand), SignalProbe, me);

    let claim = match guard.claim() {
        Ok(claim) => claim,
        Err(err) => {
            eprintln!("nerve-tmux-surface: {err}");
            return false;
        }
    };
    if let Claim::Yield { pid } = claim {
        eprintln!("nerve-tmux-surface: surface {pid} already holds this tmux");
    }
    claim.may_stream()
}

/// The two user options `run` reads, each with its published default.
fn surface_options() -> (String, String) {
    let mut options = TmuxWriter::new(TmuxCommand);
    (
        option_or(
            &mut options,
            FORMAT_OPTION,
            SummaryRenderer::DEFAULT_TEMPLATE,
        ),
        option_or(
            &mut options,
            OFFLINE_OPTION,
            SummaryRenderer::DEFAULT_OFFLINE,
        ),
    )
}

/// One user option, falling back on the tmux call failing as well as on the
/// option being unset: a surface with no template still paints.
fn option_or(options: &mut TmuxWriter<TmuxCommand>, name: &str, fallback: &str) -> String {
    options
        .get(name)
        .ok()
        .flatten()
        .unwrap_or_else(|| fallback.to_string())
}

/// What `~` expands to, for the `~/.cargo/bin` candidate.
fn home() -> PathBuf {
    env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}
