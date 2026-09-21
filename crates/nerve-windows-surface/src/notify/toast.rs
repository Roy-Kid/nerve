//! Raising the banner.
//!
//! Behind a trait so the policy that decides *whether* to notify can be tested
//! without an OS, and so a dry run can be watched rather than heard.
//!
//! Toasts here are clickable. The usual reason they are not is that activating
//! an *exited* unpackaged app needs a COM activator — a CLSID under
//! `LocalServer32` plus `INotificationActivationCallback`, which is `unsafe`.
//! That is not this case: the tray surface is by definition running when it
//! raises one, so the WinRT `Activated` event is enough, and it arrives through
//! a safe API. Clicking takes the user to the job, which is the only thing
//! attention has ever meant here (CLAUDE.md invariant 6).

#[cfg(windows)]
use std::sync::mpsc::Sender;
use std::sync::mpsc::{channel, Receiver};

use super::policy::Toast;

/// Somewhere a toast can go.
pub trait Toaster {
    /// Raise it. Returns whether the OS accepted it.
    ///
    /// A refusal is never worth interrupting the user about — they are already
    /// not being notified, and saying so twice does not help.
    fn show(&self, toast: &Toast) -> bool;
}

/// Drops every toast. What a surface uses before the user turns them on, and
/// what the tests use.
#[derive(Debug, Default)]
pub struct SilentToaster;

impl Toaster for SilentToaster {
    fn show(&self, _toast: &Toast) -> bool {
        false
    }
}

/// The real thing, plus the job ids of banners the user clicked.
///
/// The click arrives on a WinRT thread, so it is handed back over a channel
/// rather than run there: opening a location is the event loop's business.
#[cfg(windows)]
#[derive(Debug)]
pub struct WindowsToaster {
    clicked: Sender<String>,
    wake: egui::Context,
}

#[cfg(windows)]
impl WindowsToaster {
    /// The toaster, and the stream of job ids whose banners were clicked.
    pub fn new(wake: egui::Context) -> (Self, Receiver<String>) {
        let (clicked, clicks) = channel();
        (Self { clicked, wake }, clicks)
    }
}

#[cfg(windows)]
impl Toaster for WindowsToaster {
    fn show(&self, toast: &Toast) -> bool {
        use tauri_winrt_notification::{Duration, Sound, Toast as WinToast};

        let clicked = self.clicked.clone();
        let wake = self.wake.clone();
        let job_id = toast.job_id.clone();

        let mut banner = WinToast::new(crate::platform::aumid::AUMID)
            .title(&toast.title)
            .text1(&toast.body)
            // Short: an Ask that is still waiting will be asked again, and a
            // banner that sits there is one that gets dismissed unread.
            .duration(Duration::Short)
            .on_activated(move |_action| {
                // A closed receiver means the surface is shutting down; there
                // is nothing to take the user back to.
                let _ = clicked.send(job_id.clone());
                wake.request_repaint();
                Ok(())
            });

        // `Toast.tag` is not exposed by this crate, so a second banner for the
        // same job stacks rather than replacing the first. The policy's 120 s
        // dedupe is what keeps that from happening in practice.
        banner = if toast.sound {
            banner.sound(Some(Sound::Default))
        } else {
            banner.sound(None)
        };

        banner.show().is_ok()
    }
}

/// Off Windows there is no banner to raise; the macOS app owns that surface.
#[cfg(not(windows))]
#[derive(Debug)]
pub struct WindowsToaster;

#[cfg(not(windows))]
impl WindowsToaster {
    pub fn new(_wake: egui::Context) -> (Self, Receiver<String>) {
        let (_sender, clicks) = channel::<String>();
        (Self, clicks)
    }
}

#[cfg(not(windows))]
impl Toaster for WindowsToaster {
    fn show(&self, _toast: &Toast) -> bool {
        false
    }
}
