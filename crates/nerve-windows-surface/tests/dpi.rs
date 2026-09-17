//! Icon size per display scale.

use nerve_windows_surface::tray::dpi::icon_px;

#[test]
fn every_windows_rung_maps_to_its_own_size() {
    assert_eq!(icon_px(1.0), 16);
    assert_eq!(icon_px(1.25), 20);
    assert_eq!(icon_px(1.5), 24);
    assert_eq!(icon_px(1.75), 28);
    assert_eq!(icon_px(2.0), 32);
}

#[test]
fn a_factor_between_rungs_takes_the_nearer_one() {
    assert_eq!(icon_px(1.1), 16);
    assert_eq!(icon_px(1.2), 20);
    assert_eq!(icon_px(1.6), 24);
}

#[test]
fn denser_displays_clamp_rather_than_extrapolate() {
    // There is no 48 px tray rung; the shell keeps asking for 32.
    assert_eq!(icon_px(3.0), 32);
    assert_eq!(icon_px(4.0), 32);
}

#[test]
fn a_nonsense_factor_still_answers() {
    // The renderer must always get a size — a surface that cannot draw its own
    // icon has no way back to the flyout.
    for factor in [0.0, -1.0, f64::NAN, f64::INFINITY] {
        assert!(icon_px(factor) >= 16, "factor {factor} gave nothing usable");
    }
}
