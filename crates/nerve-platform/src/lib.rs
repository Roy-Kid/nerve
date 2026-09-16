//! OS-shaped primitives shared by `nerve-hub` and every surface.
//!
//! Two jobs, both too low-level to belong to a surface and too platform-shaped
//! to belong in the hub:
//!
//! - [`path`] — the wire semantics of a filesystem path. A snapshot's `cwd`
//!   arrives from whichever machine produced it, so a macOS surface routinely
//!   renders `C:\work\proj` and a Windows tray renders `/Users/me/proj`. These
//!   helpers classify the *string*, never the host, which is also why every one
//!   of them is testable on any OS.
//! - `pid` — is that process still there? (added alongside the Windows probe)
//!
//! Nothing here knows about jobs, frames or HTTP.

pub mod path;
