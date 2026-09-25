//! `tracing` for Rust surfaces: stderr plus a daily file.
//!
//! Filter with `RUST_LOG`. Default is `nerve_surface_core=info`. Prompt text
//! is never logged.

use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{EnvFilter, fmt};

/// Install the global subscriber. `component` names the file (`nerve-tmux.log`).
pub fn init(component: &str) {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("nerve_surface_core=info"));

    let stderr = fmt::layer().with_writer(std::io::stderr).with_target(true);

    let file_layer = match std::fs::create_dir_all(nerve_platform::logs::dir()) {
        Ok(()) => {
            let file = tracing_appender::rolling::daily(
                nerve_platform::logs::dir(),
                format!("{component}.log"),
            );
            Some(
                fmt::layer()
                    .with_writer(file)
                    .with_ansi(false)
                    .with_target(true),
            )
        }
        Err(_) => None,
    };

    let _ = tracing_subscriber::registry()
        .with(filter)
        .with(stderr)
        .with(file_layer)
        .try_init();

    tracing::info!(
        path = %nerve_platform::logs::dir().join(format!("{component}.log")).display(),
        "logging"
    );
}
