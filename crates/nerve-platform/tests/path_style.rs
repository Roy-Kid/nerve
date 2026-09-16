//! What counts as an absolute path, and whose rules it is written in.

use nerve_platform::path::{basename, is_absolute, style_of, PathStyle};

#[test]
fn a_leading_slash_is_posix() {
    assert_eq!(style_of("/Users/me/proj"), Some(PathStyle::Posix));
    assert_eq!(style_of("/"), Some(PathStyle::Posix));
}

#[test]
fn a_drive_with_either_slash_is_windows() {
    assert_eq!(style_of("C:\\work\\nerve"), Some(PathStyle::Windows));
    assert_eq!(style_of("c:/work/nerve"), Some(PathStyle::Windows));
    assert_eq!(style_of("C:\\"), Some(PathStyle::Windows));
}

#[test]
fn a_unc_share_is_windows() {
    assert_eq!(style_of("\\\\srv\\share\\proj"), Some(PathStyle::Windows));
}

#[test]
fn a_drive_relative_path_is_not_absolute() {
    // `C:work` names a directory relative to the current one on drive C.
    // A drive letter alone does not root a path.
    assert_eq!(style_of("C:work"), None);
    assert!(!is_absolute("C:work"));
}

#[test]
fn relative_and_empty_paths_are_not_absolute() {
    for path in ["proj", "~/proj", "./proj", "", "1:/x"] {
        assert_eq!(style_of(path), None, "{path} should not be absolute");
    }
}

#[test]
fn basename_is_the_last_named_segment() {
    assert_eq!(basename("/Users/me/proj"), Some("proj"));
    assert_eq!(basename("C:\\work\\nerve"), Some("nerve"));
    assert_eq!(basename("c:/work/nerve"), Some("nerve"));
    assert_eq!(basename("\\\\srv\\share\\proj"), Some("proj"));
}

#[test]
fn basename_ignores_a_trailing_separator() {
    assert_eq!(basename("/Users/me/proj/"), Some("proj"));
    assert_eq!(basename("C:\\work\\nerve\\"), Some("nerve"));
}

#[test]
fn a_backslash_is_a_filename_character_on_posix() {
    // `a\b` is one legal POSIX filename, not two segments. Splitting on both
    // separators regardless of style would invent a directory here.
    assert_eq!(basename("/tmp/a\\b"), Some("a\\b"));
}

#[test]
fn a_bare_root_has_no_name() {
    assert_eq!(basename("/"), None);
    assert_eq!(basename("C:\\"), None);
    assert_eq!(basename("c:/"), None);
}

#[test]
fn a_relative_path_has_no_basename() {
    assert_eq!(basename("proj"), None);
}
