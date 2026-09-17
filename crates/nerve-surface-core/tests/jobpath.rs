//! Turning a producer's reported location into a path.
//!
//! Every input here is a string from *some* machine, so the suite deliberately
//! mixes POSIX and Windows shapes and runs identically on both.

use std::path::PathBuf;

use nerve_surface_core::jobpath::{
    is_ide_deep_link, path_from_focus_hint, workspace_path_from_url,
};

fn path(s: &str) -> Option<PathBuf> {
    Some(PathBuf::from(s))
}

// ── openURL ─────────────────────────────────────────────────────────────────

#[test]
fn parses_file_uri() {
    assert_eq!(
        workspace_path_from_url("file:///Users/me/proj"),
        path("/Users/me/proj")
    );
}

#[test]
fn parses_cursor_deep_link() {
    assert_eq!(
        workspace_path_from_url("cursor://file/Users/me/proj"),
        path("/Users/me/proj")
    );
}

#[test]
fn parses_vscode_deep_link() {
    assert_eq!(
        workspace_path_from_url("vscode://file/tmp/work"),
        path("/tmp/work")
    );
}

#[test]
fn ide_deep_link_is_not_file_uri() {
    assert!(is_ide_deep_link("cursor://file/Users/me"));
    assert!(!is_ide_deep_link("file:///Users/me"));
}

#[test]
fn ide_deep_link_ignores_scheme_case() {
    assert!(is_ide_deep_link("VSCode://file/Users/me"));
}

#[test]
fn parses_percent_encoded_file_uri() {
    assert_eq!(
        workspace_path_from_url("file:///Users/me/proj%20foo"),
        path("/Users/me/proj foo")
    );
}

#[test]
fn percent_escapes_spell_one_character_together() {
    // Three escapes, one character: decoding them one at a time is what used
    // to hand the Git panel a path that does not exist.
    assert_eq!(
        workspace_path_from_url("file:///Users/me/%E9%A1%B9%E7%9B%AE"),
        path("/Users/me/项目")
    );
}

#[test]
fn a_literal_percent_survives_decoding() {
    assert_eq!(
        workspace_path_from_url("file:///tmp/100%/done"),
        path("/tmp/100%/done")
    );
}

#[test]
fn an_empty_or_unknown_url_yields_nothing() {
    assert_eq!(workspace_path_from_url(""), None);
    assert_eq!(workspace_path_from_url("   "), None);
    assert_eq!(workspace_path_from_url("http://example.com/x"), None);
}

// ── openURL, reported by a Windows producer ─────────────────────────────────

#[test]
fn parses_a_windows_file_uri() {
    assert_eq!(
        workspace_path_from_url("file:///C:/Users/me/work/nerve"),
        path("C:/Users/me/work/nerve")
    );
}

#[test]
fn parses_a_windows_deep_link() {
    // The slash after `file` is the URL's, not the path's.
    assert_eq!(
        workspace_path_from_url("vscode://file/C:/work/nerve"),
        path("C:/work/nerve")
    );
}

#[test]
fn parses_a_unc_file_uri() {
    assert_eq!(
        workspace_path_from_url("file://srv/share/proj"),
        path("\\\\srv\\share\\proj")
    );
}

// ── focus breadcrumb ────────────────────────────────────────────────────────

#[test]
fn path_from_focus_hint_breadcrumb() {
    assert_eq!(
        path_from_focus_hint(Some("Claude · nerve · iTerm · /Users/me/nerve")),
        path("/Users/me/nerve")
    );
}

#[test]
fn a_bare_absolute_hint_is_the_path() {
    assert_eq!(
        path_from_focus_hint(Some("/Users/me/nerve")),
        path("/Users/me/nerve")
    );
}

/// The hub builds this breadcrumb as `{producer} · {project} · {host} · {cwd}`
/// (`crates/nerve-hub/src/hook/build.rs`). Finding the path by searching for
/// the literal `" · /"` meant a Windows producer's cwd was never found at all.
#[test]
fn a_windows_cwd_is_found_in_the_breadcrumb() {
    assert_eq!(
        path_from_focus_hint(Some("Claude · nerve · session · C:\\work\\nerve")),
        path("C:\\work\\nerve")
    );
}

#[test]
fn the_last_absolute_segment_wins() {
    assert_eq!(
        path_from_focus_hint(Some("Claude · /opt/tool · session · /Users/me/nerve")),
        path("/Users/me/nerve")
    );
}

#[test]
fn a_breadcrumb_with_no_path_yields_nothing() {
    assert_eq!(path_from_focus_hint(Some("Claude · nerve · session")), None);
    assert_eq!(path_from_focus_hint(Some("   ")), None);
    assert_eq!(path_from_focus_hint(None), None);
}
