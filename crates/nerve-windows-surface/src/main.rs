//! The Windows tray surface's composition root.
//!
//! Assembly only: claim the lock, find a hub, start the reader, run the loop.
//! Every decision it makes is a function somewhere else.
//!
//! Fail-open throughout. A surface that cannot lock, cannot find a hub, or
//! cannot bind anything still starts and paints its offline state — the one
//! outcome that must never happen is a tray icon that is simply not there,
//! because then the user has no way back in.

use std::path::PathBuf;

use nerve_surface_core::locate::{FileProbe, HubLocator};
use nerve_surface_core::store::JobsStore;
use nerve_surface_core::stream::stream_path;
use nerve_windows_surface::app::App;
use nerve_windows_surface::platform::instance::{claim, Claim, LOCK_PORT};
use nerve_windows_surface::tray::dpi::icon_px;
use nerve_windows_surface::tray::icon::Theme;
use winit::event_loop::EventLoop;

/// The label this surface attaches under. The hub treats it as a log tag.
const SURFACE: &str = "windows";

/// Scale factor until a window exists to ask.
///
/// The tray icon is built before any window is, so the first draw uses the
/// 100% rung and is corrected on the first `ScaleFactorChanged`.
const ASSUMED_SCALE: f64 = 1.0;

fn main() {
    let lock = match claim(LOCK_PORT) {
        Ok(Claim::Yield) => {
            eprintln!("nerve: another tray surface already has this machine");
            return;
        }
        Ok(owned) => Some(owned),
        // Could not bind at all — a sandbox, most likely. Running unlocked is
        // worse than running locked and better than not running.
        Err(error) => {
            eprintln!("nerve: could not take the surface lock ({error}); carrying on");
            None
        }
    };

    let home = home_dir();
    let hub_installed = HubLocator::new(FileProbe, home.clone()).locate().is_some();

    let store = JobsStore::new();
    // Holding this stream open is what keeps the hub alive, so the reader
    // outlives any window and is never tied to one.
    let _reader = store.clone().spawn_reader(home, stream_path(SURFACE));

    let event_loop = match EventLoop::new() {
        Ok(loop_) => loop_,
        Err(error) => {
            eprintln!("nerve: no event loop ({error})");
            return;
        }
    };
    let mut app = App::new(store, hub_installed, icon_px(ASSUMED_SCALE), Theme::Dark);
    if let Err(error) = event_loop.run_app(&mut app) {
        eprintln!("nerve: event loop ended ({error})");
    }

    drop(lock);
}

/// `%USERPROFILE%` on Windows, `$HOME` elsewhere.
fn home_dir() -> PathBuf {
    std::env::var_os("USERPROFILE")
        .or_else(|| std::env::var_os("HOME"))
        .map(PathBuf::from)
        .unwrap_or_default()
}
