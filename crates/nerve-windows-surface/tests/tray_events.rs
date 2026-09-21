use nerve_windows_surface::tray::events::toggles_panel;
use tray_icon::{MouseButton, MouseButtonState, TrayIconEvent};

#[test]
fn one_mouse_click_toggles_once_and_right_click_only_opens_the_menu() {
    for button in [MouseButton::Left, MouseButton::Right, MouseButton::Middle] {
        for button_state in [MouseButtonState::Down, MouseButtonState::Up] {
            let event = TrayIconEvent::Click {
                id: "nerve".into(),
                position: Default::default(),
                rect: Default::default(),
                button,
                button_state,
            };
            assert_eq!(
                toggles_panel(&event),
                button == MouseButton::Left && button_state == MouseButtonState::Up
            );
        }
    }
}
