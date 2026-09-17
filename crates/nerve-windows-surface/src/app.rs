//! The event loop: hub snapshots in, shell calls out.
//!
//! Everything that decides *what* the tray says is a pure function elsewhere
//! ([`crate::tray::view`]). This file is only the part that needs a running
//! Windows: it polls the store, and when the drawn result would differ it tells
//! the shell.
//!
//! Polling rather than waking on frames, because the tray has nothing else to
//! do and the redraw gate makes a poll that changes nothing free. The reader
//! thread is what holds the hub's refcount; this loop never touches the socket.

use std::time::Duration;

use nerve_surface_core::store::JobsStore;
use time::OffsetDateTime;
use tray_icon::{Icon, TrayIcon, TrayIconBuilder};
use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, ControlFlow};
use winit::window::WindowId;

use crate::tray::icon::{render, Theme};
use crate::tray::signature::Signature;
use crate::tray::view;

/// How often the tray re-derives what it should say.
///
/// Four times a second is far below what a person notices as lag and far above
/// what the shell is asked to do, because the redraw gate turns all but a
/// handful of these into nothing at all.
const POLL: Duration = Duration::from_millis(250);

/// The tray surface's whole runtime state.
pub struct App {
    store: JobsStore,
    hub_installed: bool,
    icon_px: u32,
    theme: Theme,
    tray: Option<TrayIcon>,
    drawn: Option<Signature>,
}

impl App {
    pub fn new(store: JobsStore, hub_installed: bool, icon_px: u32, theme: Theme) -> Self {
        Self {
            store,
            hub_installed,
            icon_px,
            theme,
            tray: None,
            drawn: None,
        }
    }

    /// Re-derive, and tell the shell only if the pixels would differ.
    fn refresh(&mut self) {
        let snapshot = self.store.snapshot();
        let view = view::of(
            &snapshot,
            self.hub_installed,
            self.theme,
            self.icon_px,
            OffsetDateTime::now_utc(),
        );
        if self.drawn == Some(view.signature) {
            return;
        }

        let Some(tray) = self.tray.as_mut() else {
            return;
        };
        let rgba = render(&view.icon);
        if let Ok(icon) = Icon::from_rgba(rgba, view.icon.size, view.icon.size) {
            // A failed shell call is not fatal: the next poll tries again, and
            // a stale icon beats a surface that gave up.
            let _ = tray.set_icon(Some(icon));
        }
        let _ = tray.set_tooltip(Some(&view.tooltip));
        self.drawn = Some(view.signature);
    }
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.tray.is_none() {
            // Built here rather than in `new`: on Windows the icon needs the
            // loop's message window to exist before it can be registered.
            self.tray = TrayIconBuilder::new().with_tooltip("Nerve").build().ok();
            self.refresh();
        }
        event_loop.set_control_flow(ControlFlow::wait_duration(POLL));
    }

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        self.refresh();
        event_loop.set_control_flow(ControlFlow::wait_duration(POLL));
    }

    fn window_event(&mut self, _: &ActiveEventLoop, _: WindowId, _: WindowEvent) {
        // No window yet — the flyout is the next increment. The tray icon and
        // its tooltip are already a usable surface without one.
    }
}
