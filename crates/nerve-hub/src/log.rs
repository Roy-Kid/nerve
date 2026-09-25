//! `tracing` for the hub process: stderr plus a daily file.
//!
//! Filter with `RUST_LOG` (standard, not `NERVE_*`). Default is
//! `nerve_hub=info`; `--verbose` raises it to `debug`. Prompt text is never
//! logged — only event names, producer keys, job ids, and counts.

use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{EnvFilter, fmt};

/// Install the global subscriber. Safe to skip in tests (events become no-ops).
pub fn init(verbose: bool) {
    let default = if verbose {
        "nerve_hub=debug"
    } else {
        "nerve_hub=info"
    };
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(default));

    let stderr = fmt::layer().with_writer(std::io::stderr).with_target(true);

    let file_layer = match std::fs::create_dir_all(nerve_platform::logs::dir()) {
        Ok(()) => {
            let file =
                tracing_appender::rolling::daily(nerve_platform::logs::dir(), "nerve-hub.log");
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
        path = %nerve_platform::logs::dir().join("nerve-hub.log").display(),
        verbose,
        "logging"
    );
}
