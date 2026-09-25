//! Filesystem paths as they travel on the wire.
//!
//! A snapshot's `cwd` is a string produced by *some* machine, and Nerve shows
//! other machines' jobs by design (CLAUDE.md invariant 5). So a macOS surface
//! has to make sense of `C:\work\proj`, and a Windows tray has to make sense of
//! `/Users/me/proj`. Every function here therefore classifies the string by its
//! own shape and never consults the host — no `Path::is_absolute`, no
//! `MAIN_SEPARATOR`. The happy side effect is that all of it is testable
//! anywhere.
//!
//! [`to_file_uri`] is the encoder half of the `openURL` contract; the surfaces
//! decode it. Its POSIX output is byte-for-byte what `nerve-hub` has always
//! emitted, and `tests/file_uri.rs` pins that — four independent decoders (this
//! crate, the Swift app, the VS Code extension, the site docs) read it.
//!
//! The percent coding itself is `percent-encoding`'s: the encode set is
//! declared rather than hand-matched, and the decoder already knows about
//! multi-byte sequences and malformed escapes.

use percent_encoding::{AsciiSet, NON_ALPHANUMERIC, percent_decode_str, utf8_percent_encode};

/// Which OS's rules a path string is written in.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PathStyle {
    /// Rooted at `/`, and `\` is an ordinary filename character.
    Posix,
    /// `C:\…`, `C:/…`, or a `\\server\share` UNC path.
    Windows,
}

/// The style of an *absolute* path, or `None` when it is not one.
///
/// Relative paths answer `None` on purpose: every caller here wants "is this a
/// location I can hand to something", and `proj` or `~/proj` is not. So is
/// `C:work`, which names a directory relative to the current one on drive C —
/// a drive letter alone does not make a path absolute.
pub fn style_of(path: &str) -> Option<PathStyle> {
    let bytes = path.as_bytes();
    match bytes {
        [b'/', ..] => Some(PathStyle::Posix),
        [b'\\', b'\\', ..] => Some(PathStyle::Windows),
        [drive, b':', b'/' | b'\\', ..] if drive.is_ascii_alphabetic() => Some(PathStyle::Windows),
        _ => None,
    }
}

/// Is this string an absolute path in either OS's rules?
pub fn is_absolute(path: &str) -> bool {
    style_of(path).is_some()
}

/// The last named segment of an absolute path — a project name, usually.
///
/// Separator handling follows the path's own style rather than splitting on
/// both characters always: `/tmp/a\b` is a POSIX file *named* `a\b`, and
/// treating the backslash as a separator there would invent a directory.
///
/// A bare root (`/`, `C:\`) has no name and answers `None`.
pub fn basename(path: &str) -> Option<&str> {
    let style = style_of(path)?;
    let separator = |c: char| match style {
        PathStyle::Posix => c == '/',
        PathStyle::Windows => c == '/' || c == '\\',
    };
    path.rsplit(separator)
        .find(|segment| !segment.is_empty())
        .filter(|segment| !(style == PathStyle::Windows && is_drive_spec(segment)))
}

/// `/Users/me/proj` → `file:///Users/me/proj`, `C:\work` → `file:///C:/work`.
///
/// `None` for anything [`style_of`] does not call absolute, which is what keeps
/// a relative `cwd` from becoming a `file://` URL that resolves nowhere.
pub fn to_file_uri(path: &str) -> Option<String> {
    match style_of(path)? {
        // Historic shape: the leading `/` of the path supplies the third slash.
        PathStyle::Posix => Some(format!("file://{}", percent_encode_path(path))),
        PathStyle::Windows => {
            let slashed = path.replace('\\', "/");
            if let Some(share) = slashed.strip_prefix("//") {
                // UNC: the server is the URL's authority (RFC 8089 appendix E).
                Some(format!("file://{}", percent_encode_path(share)))
            } else {
                // `C:` is not a percent-escapable segment — the colon is part
                // of the drive and every consumer expects to read it verbatim.
                let (drive, rest) = slashed.split_at(2);
                Some(format!("file:///{drive}{}", percent_encode_path(rest)))
            }
        }
    }
}

/// The inverse of [`to_file_uri`], tolerant of the shapes found in the wild.
///
/// Accepts the `localhost` authority both producers and editors sometimes emit,
/// a drive letter with or without the RFC's leading slash, and a drive colon
/// that arrived percent-escaped (`file:///c%3A/work`), which is what some
/// VS Code builds produce.
pub fn from_file_uri(uri: &str) -> Option<String> {
    let rest = uri.trim().strip_prefix("file://")?;
    let rest = rest
        .strip_prefix("localhost")
        .or_else(|| rest.strip_prefix("//localhost"))
        .unwrap_or(rest);
    let decoded = percent_decode(rest);

    if let Some(after_slash) = decoded.strip_prefix('/') {
        // `file:///C:/work` — the slash is the URL's, not the path's.
        if is_drive_rooted(after_slash) {
            return Some(after_slash.to_string());
        }
        return Some(decoded);
    }
    // `file://C:/work` — two slashes, drive straight after.
    if is_drive_rooted(&decoded) {
        return Some(decoded);
    }
    // Anything else left in the authority is a UNC server.
    if decoded.is_empty() {
        return None;
    }
    Some(format!("\\\\{}", decoded.replace('/', "\\")))
}

/// The characters a `file://` path may carry literally.
///
/// Deliberately narrow and deliberately frozen: this is the wire contract, and
/// widening it would change URLs that four decoders and the published docs
/// already agree on. Everything outside it is escaped byte by byte.
const UNRESERVED: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'/')
    .remove(b'-')
    .remove(b'_')
    .remove(b'.')
    .remove(b'~');

/// Percent-escape everything a `file://` path may not carry literally.
pub fn percent_encode_path(input: &str) -> String {
    utf8_percent_encode(input, UNRESERVED).to_string()
}

/// `%20` → space, over the *bytes* of `input`.
///
/// Decoded as bytes and re-read as UTF-8 at the end, because that is what a
/// percent escape encodes: a path with a non-ASCII character in it arrives as
/// several escapes that only mean anything together, and reading each one as a
/// character of its own turned `项目` into mojibake. Anything left that is not
/// UTF-8 degrades per character rather than losing the path, and a malformed
/// escape is left standing so a directory really named `100%` survives.
pub fn percent_decode(input: &str) -> String {
    percent_decode_str(input).decode_utf8_lossy().into_owned()
}

/// `C:` exactly — a drive with no path after it.
fn is_drive_spec(segment: &str) -> bool {
    matches!(segment.as_bytes(), [drive, b':'] if drive.is_ascii_alphabetic())
}

/// `C:`, `C:/…` or `C:\…` — a drive at the head of a rooted path.
fn is_drive_rooted(path: &str) -> bool {
    match path.as_bytes() {
        [drive, b':'] => drive.is_ascii_alphabetic(),
        [drive, b':', b'/' | b'\\', ..] => drive.is_ascii_alphabetic(),
        _ => false,
    }
}
