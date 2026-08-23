//! One SSE attach, and how long to wait before the next one.
//!
//! The connection *is* this surface's refcount presence: the hub counts open
//! streams, so holding one open is what keeps it alive and dropping one is how
//! it learns this surface left. Nothing else here has to know that.
//!
//! Blocking and pull-based, with no runtime and no clock: [`StreamSession`]
//! never sleeps, [`Backoff`] only computes a delay, and the composition root is
//! what waits. That is what lets a whole reconnect story be a unit test.
//!
//! ─────────────────────────────────────────────────────────────────────────
//! When the offline placeholder is written: every attach that ends writes it —
//! a failed `open`, a clean close and a connection that died mid-flight alike.
//! In all three there is no hub behind the numbers any more, and a status line
//! that keeps painting stale counts lies. [`Attempt::ServerGone`] writes
//! nothing: there is no tmux left to write to.
//! ─────────────────────────────────────────────────────────────────────────

use std::time::Duration;

use crate::frame::Frame;
use crate::hub::{Hub, HubError, HubReader};
use crate::summary::SummaryRenderer;
use crate::tally::Tally;
use crate::tmux::SegmentWriter;

/// The one stream this surface opens. `?surface=` is a log tag for the hub.
pub const STREAM_PATH: &str = "/v1/stream?surface=tmux";

/// The SSE field that carries a frame.
const DATA_FIELD: &str = "data:";

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

/// How one attach ended.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Attempt {
    /// The attach is over after delivering `frames` frames. Zero means the hub
    /// was never reachable.
    Ended { frames: usize },
    /// tmux itself is gone: the caller exits 0 and drops the connection, which
    /// is how the hub learns this surface left.
    ServerGone,
}

/// One attach, from open to close, painting every frame it is given.
pub struct StreamSession<S: FrameSource, W: SegmentWriter> {
    source: S,
    writer: W,
    summary: SummaryRenderer,
    offline: String,
}

impl<S: FrameSource, W: SegmentWriter> StreamSession<S, W> {
    pub fn new(source: S, writer: W, summary: SummaryRenderer, offline: impl Into<String>) -> Self {
        Self {
            source,
            writer,
            summary,
            offline: offline.into(),
        }
    }

    /// One attach, start to finish. Never sleeps.
    pub fn attach(&mut self) -> Attempt {
        if self.source.open().is_err() {
            return self.go_offline(0);
        }

        let mut frames = 0;
        loop {
            match self.source.next_frame() {
                Ok(Some(frame)) => {
                    frames += 1;
                    let text = self.summary.render(&Tally::of(&frame.jobs));
                    if self.paint(&text) {
                        return Attempt::ServerGone;
                    }
                }
                // A closed stream and a broken one leave the same hole: there
                // is no hub behind the numbers on screen any more.
                Ok(None) | Err(_) => return self.go_offline(frames),
            }
        }
    }

    /// Write the placeholder and report the attach as over.
    fn go_offline(&mut self, frames: usize) -> Attempt {
        let offline = self.offline.clone();
        if self.paint(&offline) {
            return Attempt::ServerGone;
        }
        Attempt::Ended { frames }
    }

    /// Paint one text; `true` when tmux itself has gone away.
    ///
    /// Any other tmux failure costs this repaint and nothing more: the surface
    /// stays fail-open (CLAUDE.md invariant 2).
    fn paint(&mut self, text: &str) -> bool {
        matches!(self.writer.write_segment(text), Err(err) if err.is_server_gone())
    }
}

/// The frame source the binary injects: a real SSE connection to the hub.
pub struct HubFrameSource {
    hub: Hub,
    reader: Option<HubReader>,
}

impl HubFrameSource {
    pub fn new(hub: Hub) -> Self {
        Self { hub, reader: None }
    }
}

impl FrameSource for HubFrameSource {
    fn open(&mut self) -> Result<(), StreamError> {
        self.reader = None;
        self.reader = Some(self.hub.open(STREAM_PATH).map_err(StreamError::from)?);
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
