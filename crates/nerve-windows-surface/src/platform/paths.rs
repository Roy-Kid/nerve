//! Where this surface's own files live.

use std::path::PathBuf;

/// The running executable, or `None` if the OS will not say.
///
/// Autostart and the Start Menu shortcut both need it, and both are optional —
/// not knowing costs a feature, never the surface.
pub fn exe_path() -> Option<PathBuf> {
    std::env::current_exe().ok()
}

/// `%LOCALAPPDATA%\Programs\Nerve`, where the installer puts the binaries.
pub fn install_dir() -> Option<PathBuf> {
    std::env::var_os("LOCALAPPDATA").map(|root| PathBuf::from(root).join("Programs").join("Nerve"))
}

/// `%APPDATA%\Microsoft\Windows\Start Menu\Programs`.
///
/// The shortcut that lives here is what carries the AppUserModelID, which is
/// what lets an unpackaged app raise a toast under its own name.
pub fn start_menu_dir() -> Option<PathBuf> {
    std::env::var_os("APPDATA").map(|root| {
        PathBuf::from(root)
            .join("Microsoft")
            .join("Windows")
            .join("Start Menu")
            .join("Programs")
    })
}
