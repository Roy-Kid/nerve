//! The identity a toast is raised under.
//!
//! An unpackaged Win32 app cannot raise a toast until Windows can resolve an
//! AppUserModelID to a display name and an icon. Without one the banner either
//! does not appear or arrives labelled as whatever process sent it.
//!
//! Two registrations exist, and only one of them can be done from here:
//!
//! 1. `HKCU\Software\Classes\AppUserModelId\<AUMID>` with `DisplayName` and
//!    `IconUri` — plain registry, which is what [`register`] writes.
//! 2. A Start Menu shortcut carrying `System.AppUserModel.ID` as a property.
//!    That needs a shell link's property store, which means COM and `unsafe`,
//!    so it belongs to a future installer integration rather than to the
//!    running surface. The PowerShell launcher creates a plain shortcut only.
//!
//! Whether (1) alone is enough has drifted across Windows builds, which is why
//! [`shortcut_path`] exists for the installer to fill in and why toasts ship
//! default off. This is the part of the plan that wants a real machine before
//! it is trusted.

use std::path::PathBuf;

/// Dot-separated, no spaces, under 128 characters — the shape Windows wants.
pub const AUMID: &str = "Nerve.Surface";

/// The display name a toast is labelled with.
pub const DISPLAY_NAME: &str = "Nerve";

#[cfg(windows)]
const CLASSES_KEY: &str = r"Software\Classes\AppUserModelId";

/// Where the installer should put the shortcut that carries [`AUMID`].
pub fn shortcut_path() -> Option<PathBuf> {
    super::paths::start_menu_dir().map(|dir| dir.join(format!("{DISPLAY_NAME}.lnk")))
}

/// Register the display name and icon for [`AUMID`].
///
/// Idempotent, and total: a failed write costs toasts, not the surface.
#[cfg(windows)]
pub fn register(icon: Option<&std::path::Path>) -> bool {
    let path = format!(r"{CLASSES_KEY}\{AUMID}");
    let Ok(key) = windows_registry::CURRENT_USER.create(&path) else {
        return false;
    };
    if key.set_string("DisplayName", DISPLAY_NAME).is_err() {
        return false;
    }
    if let Some(icon) = icon {
        let _ = key.set_string("IconUri", icon.display().to_string());
    }
    true
}

/// Whether the surface has an identity to toast under.
#[cfg(windows)]
pub fn is_registered() -> bool {
    windows_registry::CURRENT_USER
        .open(format!(r"{CLASSES_KEY}\{AUMID}"))
        .and_then(|key| key.get_string("DisplayName"))
        .is_ok()
}

#[cfg(not(windows))]
pub fn register(_icon: Option<&std::path::Path>) -> bool {
    false
}

#[cfg(not(windows))]
pub fn is_registered() -> bool {
    false
}
