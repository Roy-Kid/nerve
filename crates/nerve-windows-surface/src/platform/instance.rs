//! One tray surface per machine.
//!
//! What the lock protects is the hub's refcount. The hub exits about thirty
//! seconds after its last consumer disconnects (CLAUDE.md invariant 4), so a
//! second surface holding a second stream would keep it alive after the first
//! one left — and the user would have no way to tell.
//!
//! The lock is a bound loopback port, which is the idiom invariant 2 already
//! blesses for the hub itself. It needs no `unsafe` (a named mutex means
//! `CreateMutexW`), it cannot go stale — the OS releases it when the process
//! dies, however it dies — and binding `127.0.0.1` specifically, rather than
//! `0.0.0.0`, raises no Windows Defender Firewall prompt.
//!
//! Nothing ever connects to it. Holding the listener *is* the lock.

use std::io;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, TcpListener};

/// One above the hub's own port, and deliberately adjacent to it: the two
/// locks are the same idea and should be findable together.
pub const LOCK_PORT: u16 = 17_891;

/// The answer to "may this process be the tray surface?".
#[derive(Debug)]
pub enum Claim {
    /// This process owns it. Hold the listener for as long as it runs.
    Owned(TcpListener),
    /// Another surface already has it: exit 0 having opened nothing.
    Yield,
}

impl Claim {
    /// Whether the caller may open the SSE stream.
    pub fn may_stream(&self) -> bool {
        matches!(self, Self::Owned(_))
    }
}

/// Take the lock, or stand down.
///
/// A port already in use is the expected second-instance answer, not an error.
/// Anything else — a sandbox that forbids binding, say — is returned so the
/// caller can decide; the composition root treats it as fail-open and carries
/// on, because a surface that cannot lock is still better than no surface.
pub fn claim(port: u16) -> io::Result<Claim> {
    let address = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::LOCALHOST, port));
    match TcpListener::bind(address) {
        Ok(listener) => Ok(Claim::Owned(listener)),
        Err(error) if error.kind() == io::ErrorKind::AddrInUse => Ok(Claim::Yield),
        Err(error) => Err(error),
    }
}
