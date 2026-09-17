//! Preferences: the only thing this surface writes to disk.

use nerve_surface_core::frame::AttentionLevel;
use nerve_windows_surface::settings::{GroupMode, Settings};

fn temp_path(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("nerve-settings-{name}-{}", std::process::id()));
    dir.join("settings.json")
}

#[test]
fn the_defaults_are_the_quiet_ones() {
    let settings = Settings::default();
    // Both off for the same reason: a Windows user very plausibly runs the VS
    // Code extension too, and autostart makes the hub permanently resident.
    // Either is a fine thing to want and neither should be assumed.
    assert!(!settings.toasts_enabled);
    assert!(!settings.autostart);
    assert_eq!(settings.group_mode, GroupMode::Machine);
}

#[test]
fn settings_round_trip_through_a_file() {
    let path = temp_path("roundtrip");
    let settings = Settings {
        panel_width: 420.0,
        group_mode: GroupMode::Status,
        toasts_enabled: true,
        toast_floor: AttentionLevel::Required,
        ..Settings::default()
    };
    settings.save(&path).expect("save");

    let loaded = Settings::load(&path);
    assert_eq!(loaded, settings);
    let _ = std::fs::remove_dir_all(path.parent().unwrap());
}

#[test]
fn a_missing_file_is_the_defaults_and_not_an_error() {
    let loaded = Settings::load(std::path::Path::new("/nonexistent/nerve/settings.json"));
    assert_eq!(loaded, Settings::default());
}

/// The file is editable, so it will be edited. A surface that refused to start
/// over a stray comma would be worse than one that forgets a window size.
#[test]
fn unreadable_content_falls_back_rather_than_failing() {
    let path = temp_path("garbage");
    std::fs::create_dir_all(path.parent().unwrap()).expect("mkdir");
    std::fs::write(&path, "{ not json at all").expect("write");

    assert_eq!(Settings::load(&path), Settings::default());
    let _ = std::fs::remove_dir_all(path.parent().unwrap());
}

#[test]
fn an_unknown_key_is_ignored_rather_than_fatal() {
    let path = temp_path("unknown");
    std::fs::create_dir_all(path.parent().unwrap()).expect("mkdir");
    std::fs::write(&path, r#"{"panelWidth": 400, "somethingNew": true}"#).expect("write");

    let loaded = Settings::load(&path);
    assert_eq!(loaded.panel_width, 400.0);
    let _ = std::fs::remove_dir_all(path.parent().unwrap());
}

#[test]
fn an_absurd_size_is_clamped_into_something_drawable() {
    let path = temp_path("absurd");
    std::fs::create_dir_all(path.parent().unwrap()).expect("mkdir");
    std::fs::write(&path, r#"{"panelWidth": 0, "panelHeight": 99999}"#).expect("write");

    let loaded = Settings::load(&path);
    assert!(loaded.panel_width >= 320.0, "{}", loaded.panel_width);
    assert!(loaded.panel_height <= 800.0, "{}", loaded.panel_height);
    let _ = std::fs::remove_dir_all(path.parent().unwrap());
}

/// `f32::clamp` propagates NaN rather than replacing it, and a NaN window size
/// is a window that never appears.
#[test]
fn a_non_finite_size_falls_back_to_the_default() {
    let broken = Settings {
        panel_width: f32::NAN,
        panel_height: f32::INFINITY,
        ..Settings::default()
    }
    .clamped();
    assert!(broken.panel_width.is_finite());
    assert!(broken.panel_height.is_finite());
}

#[test]
fn an_attention_floor_survives_the_round_trip_as_its_wire_spelling() {
    let path = temp_path("floor");
    Settings {
        toast_floor: AttentionLevel::Urgent,
        ..Settings::default()
    }
    .save(&path)
    .expect("save");

    let raw = std::fs::read_to_string(&path).expect("read");
    assert!(raw.contains("\"urgent\""), "{raw}");
    assert_eq!(Settings::load(&path).toast_floor, AttentionLevel::Urgent);
    let _ = std::fs::remove_dir_all(path.parent().unwrap());
}
