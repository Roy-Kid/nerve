//! The loopback hub endpoint: blocking HTTP/1.1 over `std::net::TcpStream`.
//!
//! A transport and nothing more — it knows about sockets, status lines and
//! bodies, and nothing about frames, health or jobs. The three modules that
//! speak to the hub ([`crate::launch`] health, [`crate::stream`] SSE, and the
//! popup's one-shot job read) adapt it to their own port, so no module has to
//! own a socket to be unit-testable.
//!
//! Hand-written rather than a client crate: the hub is on loopback, the
//! requests are `GET`s with no body, no redirect, no TLS and no auth, and
//! `crates/nerve-hub/tests/sse_stream.rs` already reads its own SSE the same
//! way. One transport is not worth a dependency tree.
//!
//! The port is fixed at 17890. It is the hub's single-instance lock and is
//! hard-coded by the agent hooks (CLAUDE.md invariant 2), so it is deliberately
//! not configurable here either.

use std::fmt;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpStream};
use std::time::Duration;

/// The one ingest port, shared by every producer and every surface.
pub const PORT: u16 = 17890;

/// `127.0.0.1:17890`.
pub const ADDRESS: SocketAddr = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), PORT);

/// Loopback either answers at once or is not there.
const CONNECT_TIMEOUT: Duration = Duration::from_millis(500);

/// A one-shot `GET` that has not finished by now is not going to.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(2);

/// A stream that has said nothing for this long is dead.
///
/// Comfortably above axum's SSE keep-alive interval (15s), so a quiet hub is
/// never mistaken for a broken one, and low enough that a half-open socket is
/// noticed within a minute.
const STREAM_IDLE_TIMEOUT: Duration = Duration::from_secs(60);

/// The largest one-shot body this surface will read.
const MAX_BODY_BYTES: u64 = 8 * 1024 * 1024;

/// Why a request did not produce a body.
#[derive(Debug)]
pub enum HubError {
    /// Nothing answered on the loopback port.
    Unreachable(String),
    /// The connection was made and then failed, or answered nonsense.
    Broken(String),
    /// The hub answered, with a status this surface cannot use.
    Status(u16),
}

impl fmt::Display for HubError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unreachable(reason) => write!(f, "hub unreachable: {reason}"),
            Self::Broken(reason) => write!(f, "hub connection broken: {reason}"),
            Self::Status(status) => write!(f, "hub answered HTTP {status}"),
        }
    }
}

impl std::error::Error for HubError {}

/// The hub on this machine's loopback.
///
/// Holds no socket: each request opens its own, which is what makes an
/// unreachable hub a per-call answer rather than a lifetime.
pub struct Hub {
    address: SocketAddr,
}

impl Hub {
    /// The hub every producer and surface on this machine talks to.
    pub fn loopback() -> Self {
        Self { address: ADDRESS }
    }

    /// One `GET`, answered as the whole response body.
    pub fn get(&self, path: &str) -> Result<String, HubError> {
        let mut socket = self.connect()?;
        socket
            .set_read_timeout(Some(REQUEST_TIMEOUT))
            .and_then(|()| socket.set_write_timeout(Some(REQUEST_TIMEOUT)))
            .map_err(|err| HubError::Broken(err.to_string()))?;
        self.request(&mut socket, path, "application/json", true)?;

        let mut response = Vec::new();
        socket
            .take(MAX_BODY_BYTES)
            .read_to_end(&mut response)
            .map_err(|err| HubError::Broken(err.to_string()))?;
        let response =
            String::from_utf8(response).map_err(|err| HubError::Broken(err.to_string()))?;

        let (head, body) = response
            .split_once("\r\n\r\n")
            .ok_or_else(|| HubError::Broken("response has no header block".to_string()))?;
        check_status(head.lines().next().unwrap_or_default())?;
        decode_body(head, body)
    }

    /// One long-lived `GET`, answered as a reader over the response body.
    ///
    /// Holding the returned reader open is what keeps the connection — and
    /// therefore the hub's refcount — alive.
    pub fn open(&self, path: &str) -> Result<HubReader, HubError> {
        let mut socket = self.connect()?;
        socket
            .set_read_timeout(Some(STREAM_IDLE_TIMEOUT))
            .and_then(|()| socket.set_write_timeout(Some(REQUEST_TIMEOUT)))
            .map_err(|err| HubError::Broken(err.to_string()))?;
        self.request(&mut socket, path, "text/event-stream", false)?;

        let mut reader = HubReader {
            reader: BufReader::new(socket),
        };
        let status = reader
            .next_line()?
            .ok_or_else(|| HubError::Broken("stream closed before answering".to_string()))?;
        check_status(&status)?;
        // Headers end at the first blank line; the body starts after it.
        while let Some(line) = reader.next_line()? {
            if line.is_empty() {
                return Ok(reader);
            }
        }
        Err(HubError::Broken(
            "stream closed inside its headers".to_string(),
        ))
    }

    fn connect(&self) -> Result<TcpStream, HubError> {
        TcpStream::connect_timeout(&self.address, CONNECT_TIMEOUT)
            .map_err(|err| HubError::Unreachable(err.to_string()))
    }

    fn request(
        &self,
        socket: &mut TcpStream,
        path: &str,
        accept: &str,
        close: bool,
    ) -> Result<(), HubError> {
        let connection = if close { "close" } else { "keep-alive" };
        let request = format!(
            "GET {path} HTTP/1.1\r\nHost: {}\r\nAccept: {accept}\r\nConnection: {connection}\r\n\r\n",
            self.address
        );
        socket
            .write_all(request.as_bytes())
            .and_then(|()| socket.flush())
            .map_err(|err| HubError::Broken(err.to_string()))
    }
}

/// A line reader over one open response body.
pub struct HubReader {
    reader: BufReader<TcpStream>,
}

impl HubReader {
    /// The next line without its terminator, or `None` at end of stream.
    ///
    /// Chunked-encoding size lines are left in: they are hex digits on a line
    /// of their own and can never be mistaken for an SSE `data:` field, which
    /// is the only line the caller acts on. Reading lines rather than decoding
    /// chunks is how `crates/nerve-hub/tests/sse_stream.rs` reads the same
    /// stream.
    pub fn next_line(&mut self) -> Result<Option<String>, HubError> {
        let mut line = String::new();
        match self.reader.read_line(&mut line) {
            Ok(0) => Ok(None),
            Ok(_) => Ok(Some(line.trim_end_matches(['\r', '\n']).to_string())),
            Err(err) => Err(HubError::Broken(err.to_string())),
        }
    }
}

/// Whether a status line says `200`.
fn check_status(status_line: &str) -> Result<(), HubError> {
    let status = status_line
        .split_whitespace()
        .nth(1)
        .and_then(|code| code.parse::<u16>().ok())
        .ok_or_else(|| HubError::Broken(format!("unreadable status line `{status_line}`")))?;
    if status == 200 {
        Ok(())
    } else {
        Err(HubError::Status(status))
    }
}

/// The body of a finished response, chunked encoding undone.
fn decode_body(head: &str, body: &str) -> Result<String, HubError> {
    let chunked = head
        .lines()
        .filter_map(|line| line.split_once(':'))
        .any(|(name, value)| {
            name.eq_ignore_ascii_case("transfer-encoding")
                && value.to_ascii_lowercase().contains("chunked")
        });
    if !chunked {
        return Ok(body.to_string());
    }

    let mut decoded = String::with_capacity(body.len());
    let mut rest = body;
    loop {
        let (size, remainder) = rest
            .split_once("\r\n")
            .ok_or_else(|| HubError::Broken("truncated chunk header".to_string()))?;
        let size = usize::from_str_radix(size.trim().split(';').next().unwrap_or_default(), 16)
            .map_err(|_| HubError::Broken(format!("unreadable chunk size `{size}`")))?;
        if size == 0 {
            return Ok(decoded);
        }
        if remainder.len() < size {
            return Err(HubError::Broken("truncated chunk body".to_string()));
        }
        decoded.push_str(&remainder[..size]);
        rest = remainder[size..].trim_start_matches("\r\n");
    }
}
