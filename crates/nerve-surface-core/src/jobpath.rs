//! Where a job is, as a path this machine could open.
//!
//! Producers report a location three ways — an `openURL`, a `context.workspace`
//! and a focus breadcrumb — and every one of them arrives as a string written
//! in the reporting machine's rules. So nothing here asks whether a path is
//! absolute *here*; it asks [`nerve_platform::path`] what shape the string is,
//! which is the same module `nerve-hub` encoded it with.

use std::path::PathBuf;

use nerve_platform::path;

use crate::frame::JobView;

/// The best path a job gives us, or `None` when it gives none.
///
/// `openURL` first because a producer that emitted one meant it; then the
/// workspace it named; then the tail of the focus breadcrumb.
pub fn job_path(job: &JobView) -> Option<PathBuf> {
    if let Some(url) = job.location.as_ref().and_then(|l| l.open_url.as_deref())
        && let Some(path) = workspace_path_from_url(url)
    {
        return Some(path);
    }
    if let Some(path) = job
        .context
        .workspace
        .as_deref()
        .map(str::trim)
        .filter(|workspace| path::is_absolute(workspace))
    {
        return Some(PathBuf::from(path));
    }
    path_from_focus_hint(job.location.as_ref().and_then(|l| l.focus_hint.as_deref()))
}

/// The path out of a focus breadcrumb (`Claude · nerve · session · /Users/…`).
///
/// The last absolute-looking segment wins. It used to be found by searching
/// for the literal `" · /"`, which is a POSIX path and nothing else — a Windows
/// producer's `Claude · nerve · session · C:\work\nerve` never matched, so a
/// job that named its location perfectly well appeared to name none.
pub fn path_from_focus_hint(hint: Option<&str>) -> Option<PathBuf> {
    let hint = hint?.trim();
    if hint.is_empty() {
        return None;
    }
    if path::is_absolute(hint) {
        return Some(PathBuf::from(path::percent_decode(hint)));
    }
    hint.split(" · ")
        .map(str::trim)
        .filter(|segment| path::is_absolute(segment))
        .last()
        .map(|segment| PathBuf::from(path::percent_decode(segment)))
}

/// Extract a filesystem path from producer `openURL` shapes.
///
/// Hooks emit either `file:///path` or an IDE deep link like
/// `cursor://file/Users/…`. A deep link's path carries the URL's own leading
/// slash, which a drive letter has to be lifted out from
/// (`vscode://file/C:/work` is `C:/work`).
pub fn workspace_path_from_url(url: &str) -> Option<PathBuf> {
    let url = url.trim();
    if url.is_empty() {
        return None;
    }
    if url.starts_with("file://") {
        return path::from_file_uri(url).map(PathBuf::from);
    }
    for scheme in ["cursor://file", "vscode://file", "vscode-insiders://file"] {
        let Some(rest) = url.strip_prefix(scheme) else {
            continue;
        };
        let decoded = path::percent_decode(rest);
        if let Some(after_slash) = decoded.strip_prefix('/')
            && path::is_absolute(after_slash)
        {
            return Some(PathBuf::from(after_slash));
        }
        if path::is_absolute(&decoded) {
            return Some(PathBuf::from(decoded));
        }
    }
    None
}

/// A URL its own app resolves (`cursor://`, `vscode://`) rather than a path.
///
/// A `file://` URL is a path on the reporting machine and is never one of
/// these — handing it to a local opener is how a remote job's location gets
/// opened on the wrong machine.
pub fn is_ide_deep_link(url: &str) -> bool {
    let url = url.trim().to_ascii_lowercase();
    url.starts_with("cursor://")
        || url.starts_with("vscode://")
        || url.starts_with("vscode-insiders://")
}
