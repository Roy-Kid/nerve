//! Percent coding, at the byte level it actually operates on.

use nerve_platform::path::{percent_decode, percent_encode_path};

#[test]
fn a_string_without_escapes_is_returned_as_is() {
    assert_eq!(percent_decode("/Users/me/proj"), "/Users/me/proj");
}

#[test]
fn escapes_spell_one_character_together() {
    // Three escapes, one character: decoding them one at a time is what used
    // to hand the Git panel a path that does not exist.
    assert_eq!(
        percent_decode("/Users/me/%E9%A1%B9%E7%9B%AE"),
        "/Users/me/项目"
    );
}

#[test]
fn a_literal_percent_survives_decoding() {
    // `%/d` is not an escape; leaving it alone is what keeps a real directory
    // named `100%` readable.
    assert_eq!(percent_decode("/tmp/100%/done"), "/tmp/100%/done");
}

#[test]
fn a_truncated_escape_survives_decoding() {
    assert_eq!(percent_decode("/tmp/a%2"), "/tmp/a%2");
    assert_eq!(percent_decode("/tmp/a%"), "/tmp/a%");
}

#[test]
fn either_hex_case_decodes() {
    assert_eq!(percent_decode("%2f%2F"), "//");
}

#[test]
fn encoding_then_decoding_is_the_identity() {
    for path in [
        "/Users/me/proj",
        "/Users/me/proj foo",
        "/Users/me/项目",
        "/tmp/100%/done",
        "/tmp/a\\b",
        "/a-b_c.d~e/9Z",
        "/tmp/quote'and\"double",
    ] {
        assert_eq!(percent_decode(&percent_encode_path(path)), path, "{path}");
    }
}

#[test]
fn invalid_utf8_degrades_rather_than_losing_the_path() {
    // A lone continuation byte cannot be part of any character. The path is
    // still more useful with a replacement character in it than dropped.
    let decoded = percent_decode("/tmp/%FF");
    assert!(decoded.starts_with("/tmp/"), "{decoded}");
}
