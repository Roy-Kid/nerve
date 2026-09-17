//! One SSE attach, and how long to wait before the next one.
//!
//! The connection *is* a surface's refcount presence: the hub counts open
//! streams, so holding one open is what keeps it alive and dropping one is how
//! it learns this surface left (CLAUDE.md invariant 4). Nothing else here has
//! to know that.
//!
//! Blocking and pull-based, with no runtime and no clock: [`Backoff`] only
//! computes a delay and the composition root is what waits. That is what lets a
//! whole reconnect story be a unit test, and what lets a terminal, an editor
//! and a tray share one implementation of it.

use std::time::Duration;

use crate::frame::Frame;
use crate::hub::{Hub, HubError, HubReader};

/// One-shot job list — same rows a connect frame carries, bare array.
pub const JOBS_PATH: &str = "/v1/jobs";

/// The SSE field that carries a frame.
const DATA_FIELD: &str = "data:";

/// The stream to open, labelled with which surface is asking.
///
/// `?surface=` is a log tag and nothing else — the hub sends every frame to
/// every surface, and filtering per surface would break the "frames are the
/// authoritative full set" rule that makes reconnects free
/// (`crates/nerve-hub/src/http/stream.rs`).
pub fn stream_path(surface: &str) -> String {
    format!("/v1/stream?surface={surface}")
}

/// Doubling reconnect delay: 0.5s, capped at 30s, reset by any attach that
/// delivered a frame.
#[derive(Clone, Copy, Debug)]
pub struct Backoff {
    next: Duration,
}

impl Backoff {
    /// What the first failure costs.
    pub const FIRST: Duration = Duration::from_millis(500);
    /// However long the hub stays away, never wait longer than this.
    pub const CAP: Duration = Duration::from_secs(30);

    pub fn new() -> Self {
        Self { next: Self::FIRST }
    }

    /// The delay to wait after this failure; doubles for the next one.
    pub fn fail(&mut self) -> Duration {
        let delay = self.next;
        self.next = (delay * 2).min(Self::CAP);
        delay
    }

    /// What the next [`Backoff::fail`] will return, without consuming it.
    pub fn peek(&self) -> Duration {
        self.next
    }

    /// Back to [`Backoff::FIRST`].
    pub fn reset(&mut self) {
        self.next = Self::FIRST;
    }
}

impl Default for Backoff {
    fn default() -> Self {
        Self::new()
    }
}

/// Why a stream is not delivering frames.
#[derive(Debug)]
pub enum StreamError {
    /// Nothing answered on the loopback port.
    Unreachable,
    /// The connection died, or carried something that would not decode.
    Broken(String),
}

/// One long-lived `GET /v1/stream?surface=tmux`.
pub trait FrameSource {
    /// Open the connection.
    fn open(&mut self) -> Result<(), StreamError>;
    /// Block for the next frame. `Ok(None)` means the hub closed the stream.
    fn next_frame(&mut self) -> Result<Option<Frame>, StreamError>;
}

/// The frame source the binary injects: a real SSE connection to the hub.
pub struct HubFrameSource {
    hub: Hub,
    path: String,
    reader: Option<HubReader>,
}

impl HubFrameSource {
    /// `path` is usually [`stream_path`] for the caller's own surface label.
    pub fn new(hub: Hub, path: impl Into<String>) -> Self {
        Self {
            hub,
            path: path.into(),
            reader: None,
        }
    }
}

impl FrameSource for HubFrameSource {
    fn open(&mut self) -> Result<(), StreamError> {
        self.reader = None;
        self.reader = Some(self.hub.open(&self.path).map_err(StreamError::from)?);
        Ok(())
    }

    fn next_frame(&mut self) -> Result<Option<Frame>, StreamError> {
        let reader = self
            .reader
            .as_mut()
            .ok_or_else(|| StreamError::Broken("stream was never opened".to_string()))?;

        // Everything the transport adds — chunk sizes, `:` keep-alive comments,
        // `event:` and `id:` fields, blank separators — is not a frame.
        while let Some(line) = reader.next_line().map_err(StreamError::from)? {
            let Some(payload) = line.strip_prefix(DATA_FIELD) else {
                continue;
            };
            return Frame::decode(payload.trim_start())
                .map(Some)
                .map_err(|err| StreamError::Broken(err.to_string()));
        }
        Ok(None)
    }
}

impl From<HubError> for StreamError {
    fn from(error: HubError) -> Self {
        match error {
            HubError::Unreachable(_) => Self::Unreachable,
            other => Self::Broken(other.to_string()),
        }
    }
}
