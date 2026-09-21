//! Only a completed left click toggles the flyout; right click belongs to the menu.

use tray_icon::{MouseButton, MouseButtonState, TrayIconEvent};

pub fn toggles_panel(event: &TrayIconEvent) -> bool {
    matches!(
        event,
        TrayIconEvent::Click {
            button: MouseButton::Left,
            button_state: MouseButtonState::Up,
            ..
        }
    )
}
