//! nerve-tmux-surface: the tmux peer of the macOS menu-bar surface.
//!
//! The two surfaces are peers that do not know about each other. Both consume
//! the `nerve-hub` contract and nothing else: this crate never reads the macOS
//! app's state, never assumes it is running, and never sends a system
//! notification (those belong to the macOS surface, so a job cannot ring twice).
//!
//! Every module is a unit test away from a fake — no module needs a real tmux,
//! a real hub or a real socket to be exercised:
//!
//! | module | owns |
//! |--------|------|
//! | [`frame`] | decoding one `GET /v1/stream` frame |
//! | [`status`] | the six-state derivation, mirrored from `Subject.swift:38` |
//! | [`tally`] | counting a frame's jobs by class |
//! | [`summary`] | rendering `@nerve_status` from a tally |
//! | [`popup`] | the read-only job list behind `prefix + N` |
//! | [`locate`] | finding the `nerve-hub` binary |
//! | [`launch`] | starting one, at most once per window |
//! | [`stream`] | one SSE attach, and the delay before the next |
//! | [`tmux`] | the only place this crate talks to tmux |
//! | [`instance`] | one surface per tmux server |
//! | [`hub`] | blocking HTTP/1.1 on loopback, the transport the above adapt |
//!
//! `hub` is the one module the spec's Design table does not name: the three
//! callers that speak to 127.0.0.1:17890 need a transport, and the composition
//! root is where it must *not* live (spec Design: "main.rs — 组合根:只做装配
//! 与信号处理,无业务逻辑").

pub mod frame;
pub mod hub;
pub mod instance;
pub mod launch;
pub mod locate;
pub mod popup;
pub mod status;
pub mod stream;
pub mod summary;
pub mod tally;
pub mod tmux;
