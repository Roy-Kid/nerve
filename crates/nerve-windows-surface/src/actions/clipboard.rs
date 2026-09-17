//! Putting text where the user can paste it.

/// A clipboard. A trait so a copy can be asserted rather than performed.
pub trait Clipboard {
    fn set_text(&mut self, text: &str) -> bool;
}

/// The system clipboard.
///
/// The handle is opened per call rather than held: on Windows the clipboard is
/// a shared, lockable resource, and a tray process that kept it open would
/// block every other application's copy for as long as it ran.
#[derive(Debug, Default)]
pub struct SystemClipboard;

impl Clipboard for SystemClipboard {
    fn set_text(&mut self, text: &str) -> bool {
        arboard::Clipboard::new()
            .and_then(|mut clipboard| clipboard.set_text(text.to_string()))
            .is_ok()
    }
}

/// Remembers instead of copying.
#[derive(Debug, Default)]
pub struct RecordingClipboard {
    pub copied: Vec<String>,
}

impl Clipboard for RecordingClipboard {
    fn set_text(&mut self, text: &str) -> bool {
        self.copied.push(text.to_string());
        true
    }
}
