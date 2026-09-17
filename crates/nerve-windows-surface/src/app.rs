//! The running surface: tray icon, flyout, and what connects them to the hub.
//!
//! Everything that decides *what* is on screen is a pure function elsewhere.
//! This file is the part that needs a running desktop — it polls the store,
//! tells the shell when the drawn result would differ, and shows or hides one
//! window.
//!
//! The reader thread is what holds the hub's refcount (CLAUDE.md invariant 4),
//! and it is deliberately not tied to the window: hiding the flyout must never
//! drop the stream, or the hub would exit thirty seconds after the user looked
//! away.

use std::sync::mpsc::Receiver;
use std::time::{Duration, Instant};

use eframe::{App as EframeApp, CreationContext, Frame};
use egui::{Context, ViewportCommand};
use nerve_surface_core::machine;
use nerve_surface_core::store::JobsStore;
use time::OffsetDateTime;
use tray_icon::menu::{CheckMenuItem, Menu, MenuEvent, MenuItem, PredefinedMenuItem};
use tray_icon::{Icon, TrayIcon, TrayIconBuilder, TrayIconEvent};

use crate::actions::clipboard::SystemClipboard;
use crate::actions::shell::SystemOpener;
use crate::actions::{self};
use crate::flyout::anchor::{place, Anchor, Rect};
use crate::flyout::view::{PanelAction, PanelState};
use crate::flyout::{fonts, theme as panel_theme, view as panel};
use crate::notify::policy::{AskPolicy, Settings as NotifySettings};
use crate::notify::toast::{Toaster, WindowsToaster};
use crate::platform::{autostart, theme as system_theme};
use crate::settings::{settings_path, Settings};
use crate::tray::dpi::icon_px;
use crate::tray::icon::render;
use crate::tray::signature::Signature;
use crate::tray::view as tray_view;

/// How often the surface re-derives what it should say.
///
/// Four times a second is below what a person reads as lag and far above what
/// the shell is asked to do, because the redraw gate turns all but a handful of
/// these into nothing at all.
const POLL: Duration = Duration::from_millis(250);

/// How long after hiding the flyout a tray click is ignored.
///
/// Clicking the icon while the panel is open takes focus away from it, which
/// hides it — and then the click itself would reopen it. This is the classic
/// tray-flyout bug, and this is the guard against it.
const REOPEN_DEBOUNCE: Duration = Duration::from_millis(200);

pub struct App {
    store: JobsStore,
    settings: Settings,
    hub_installed: bool,
    local_alias: Option<String>,

    tray: Option<TrayIcon>,
    drawn: Option<Signature>,
    icon_px: u32,
    theme: crate::tray::icon::Theme,

    panel: PanelState,
    visible: bool,
    hidden_at: Option<Instant>,
    tray_rect: Option<Rect>,

    notifier: AskPolicy,
    toaster: WindowsToaster,
    toast_clicks: Receiver<String>,

    /// The last thing an action said, shown under the header briefly.
    note: Option<(String, Instant)>,

    menu: MenuIds,
}

/// The context-menu items whose clicks mean something.
struct MenuIds {
    open: tray_icon::menu::MenuId,
    autostart: tray_icon::menu::MenuId,
    toasts: tray_icon::menu::MenuId,
    quit: tray_icon::menu::MenuId,
}

impl App {
    pub fn new(cc: &CreationContext<'_>, store: JobsStore, hub_installed: bool) -> Self {
        let settings = Settings::load(&settings_path());
        let theme = system_theme::current();

        let mut fonts = egui::FontDefinitions::default();
        fonts::install_cjk(&mut fonts);
        cc.egui_ctx.set_fonts(fonts);
        cc.egui_ctx.set_visuals(panel_theme::visuals(theme));

        let (toaster, toast_clicks) = WindowsToaster::new();
        let (tray, menu) = build_tray(&settings);

        Self {
            store,
            settings,
            hub_installed,
            local_alias: machine::local_alias().map(str::to_string),
            tray,
            drawn: None,
            icon_px: icon_px(cc.egui_ctx.pixels_per_point() as f64),
            theme,
            panel: PanelState::default(),
            visible: false,
            hidden_at: None,
            tray_rect: None,
            notifier: AskPolicy::new(),
            toaster,
            toast_clicks,
            note: None,
            menu,
        }
    }

    /// Re-derive the tray's appearance and tell the shell only on a change.
    fn refresh_tray(&mut self) {
        let snapshot = self.store.snapshot();
        let view = tray_view::of(
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

    /// Ask the policy whether this frame is worth interrupting for.
    fn notify(&mut self) {
        let snapshot = self.store.snapshot();
        let settings = NotifySettings {
            enabled: self.settings.toasts_enabled,
            sound: self.settings.toast_sound,
            floor: self.settings.toast_floor,
        };
        for toast in self
            .notifier
            .evaluate(&snapshot.jobs, settings, Instant::now())
        {
            self.toaster.show(&toast);
        }
    }

    fn show_panel(&mut self, ctx: &Context) {
        if let (Some(tray), Some(monitor)) = (self.tray_rect, monitor_rect(ctx)) {
            let anchor = Anchor {
                tray,
                monitor,
                size: (
                    self.settings.panel_width as i32,
                    self.settings.panel_height as i32,
                ),
            };
            let (x, y) = place(&anchor);
            ctx.send_viewport_cmd(ViewportCommand::OuterPosition(egui::pos2(
                x as f32, y as f32,
            )));
        }
        ctx.send_viewport_cmd(ViewportCommand::InnerSize(egui::vec2(
            self.settings.panel_width,
            self.settings.panel_height,
        )));
        ctx.send_viewport_cmd(ViewportCommand::Visible(true));
        ctx.send_viewport_cmd(ViewportCommand::Focus);
        self.visible = true;
    }

    fn hide_panel(&mut self, ctx: &Context) {
        ctx.send_viewport_cmd(ViewportCommand::Visible(false));
        self.visible = false;
        self.hidden_at = Some(Instant::now());
        self.panel.expanded = None;
    }

    fn toggle_panel(&mut self, ctx: &Context) {
        if self.visible {
            self.hide_panel(ctx);
            return;
        }
        // The click that closed the panel must not immediately reopen it.
        if self
            .hidden_at
            .is_some_and(|at| at.elapsed() < REOPEN_DEBOUNCE)
        {
            return;
        }
        self.show_panel(ctx);
    }

    fn act(&mut self, action: PanelAction, ctx: &Context) {
        match action {
            PanelAction::CycleGroup => {
                self.settings.group_mode = self.settings.group_mode.next();
                self.persist();
            }
            PanelAction::Open(id) => {
                let snapshot = self.store.snapshot();
                if let Some(job) = snapshot.jobs.iter().find(|job| job.id == id) {
                    let outcome = actions::perform(
                        job,
                        self.local_alias.as_deref(),
                        &SystemOpener,
                        &mut SystemClipboard,
                    );
                    self.note = Some((outcome.message, Instant::now()));
                    // Taking the user somewhere means getting out of the way.
                    if outcome.succeeded {
                        self.hide_panel(ctx);
                    }
                }
            }
            PanelAction::Copy(id) => {
                let snapshot = self.store.snapshot();
                if let Some(job) = snapshot.jobs.iter().find(|job| job.id == id) {
                    let outcome = actions::copy(job, &mut SystemClipboard);
                    self.note = Some((outcome.message, Instant::now()));
                }
            }
        }
    }

    /// Not `save`: eframe's `App` trait owns that name for its own storage.
    fn persist(&self) {
        let _ = self.settings.save(&settings_path());
    }

    /// Tray clicks, menu clicks and toast clicks, all of which arrive out of
    /// band from other threads.
    fn drain_events(&mut self, ctx: &Context) {
        while let Ok(event) = TrayIconEvent::receiver().try_recv() {
            if let TrayIconEvent::Click { rect, .. } = event {
                self.tray_rect = Some(Rect::new(
                    rect.position.x as i32,
                    rect.position.y as i32,
                    rect.size.width as i32,
                    rect.size.height as i32,
                ));
                self.toggle_panel(ctx);
            }
        }

        while let Ok(event) = MenuEvent::receiver().try_recv() {
            if event.id == self.menu.open {
                self.show_panel(ctx);
            } else if event.id == self.menu.autostart {
                let wanted = !self.settings.autostart;
                self.settings.autostart = autostart::set(wanted);
                self.persist();
            } else if event.id == self.menu.toasts {
                self.settings.toasts_enabled = !self.settings.toasts_enabled;
                self.persist();
            } else if event.id == self.menu.quit {
                ctx.send_viewport_cmd(ViewportCommand::Close);
            }
        }

        // A clicked banner means "take me there", the same as the row's Open.
        while let Ok(job_id) = self.toast_clicks.try_recv() {
            self.act(PanelAction::Open(job_id), ctx);
        }
    }
}

impl EframeApp for App {
    fn update(&mut self, ctx: &Context, _frame: &mut Frame) {
        self.drain_events(ctx);

        let theme = system_theme::current();
        if theme != self.theme {
            self.theme = theme;
            ctx.set_visuals(panel_theme::visuals(theme));
            self.drawn = None;
        }
        self.icon_px = icon_px(ctx.pixels_per_point() as f64);

        self.refresh_tray();
        self.notify();

        if self.visible {
            // Focus loss dismisses. The panel is a glance, not a window to
            // manage, so it never competes for the taskbar or Alt-Tab.
            let focused = ctx.input(|input| input.viewport().focused.unwrap_or(true));
            if !focused {
                self.hide_panel(ctx);
            }
            if ctx.input(|input| input.key_pressed(egui::Key::Escape)) {
                self.hide_panel(ctx);
            }
        }

        let mut action = None;
        egui::CentralPanel::default().show(ctx, |ui| {
            let snapshot = self.store.snapshot();
            action = panel::show(
                ui,
                &snapshot,
                &mut self.panel,
                self.settings.group_mode,
                self.hub_installed,
                self.theme,
                OffsetDateTime::now_utc(),
            );
            if let Some((note, at)) = &self.note {
                if at.elapsed() < Duration::from_secs(3) {
                    ui.add_space(4.0);
                    ui.label(egui::RichText::new(note).small());
                }
            }
        });
        if let Some(action) = action {
            self.act(action, ctx);
        }

        // Polling rather than waking on frames: the redraw gate makes a poll
        // that changes nothing free, and the reader owns the socket either way.
        ctx.request_repaint_after(POLL);
    }
}

/// Build the tray icon and its context menu.
fn build_tray(settings: &Settings) -> (Option<TrayIcon>, MenuIds) {
    let open = MenuItem::new("Open Nerve", true, None);
    let start = CheckMenuItem::new("Start at login", true, settings.autostart, None);
    let toasts = CheckMenuItem::new("Ask notifications", true, settings.toasts_enabled, None);
    let quit = MenuItem::new("Quit", true, None);

    let ids = MenuIds {
        open: open.id().clone(),
        autostart: start.id().clone(),
        toasts: toasts.id().clone(),
        quit: quit.id().clone(),
    };

    let menu = Menu::new();
    let _ = menu.append_items(&[
        &open,
        &PredefinedMenuItem::separator(),
        &start,
        &toasts,
        &PredefinedMenuItem::separator(),
        &quit,
    ]);

    let tray = TrayIconBuilder::new()
        .with_tooltip("Nerve")
        .with_menu(Box::new(menu))
        .build()
        .ok();
    (tray, ids)
}

/// The monitor the flyout will land on, in physical pixels.
fn monitor_rect(ctx: &Context) -> Option<Rect> {
    let size = ctx.input(|input| input.viewport().monitor_size)?;
    let scale = ctx.pixels_per_point();
    Some(Rect::new(
        0,
        0,
        (size.x * scale) as i32,
        (size.y * scale) as i32,
    ))
}
