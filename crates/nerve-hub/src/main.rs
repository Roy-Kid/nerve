//! Binary entry point: parse the command line, assemble, run, map exit codes.

use std::process::ExitCode;

use nerve_hub::cli::{Command, ServeArgs, EXIT_FAILURE, EXIT_OK, EXIT_USAGE, USAGE};
use nerve_hub::{Hub, ServeError};

fn main() -> ExitCode {
    match Command::parse(std::env::args().skip(1)) {
        Ok(Command::Help) => {
            println!("{USAGE}");
            ExitCode::from(EXIT_OK)
        }
        Ok(Command::Hook) => ExitCode::from(nerve_hub::hook::forward_stdin() as u8),
        Ok(Command::Serve(args)) => {
            nerve_hub::log::init(args.verbose());
            serve(args)
        }
        Err(err) => {
            eprintln!("nerve-hub: {err}\n\n{USAGE}");
            ExitCode::from(EXIT_USAGE)
        }
    }
}

#[tokio::main(flavor = "current_thread")]
async fn serve(args: ServeArgs) -> ExitCode {
    match Hub::new(args.grace()).serve().await {
        Ok(()) => ExitCode::from(EXIT_OK),
        Err(err) => {
            eprintln!("nerve-hub: {err}");
            match err {
                // Surfaces spawn-and-forget: "a hub owns 17890" already holds,
                // so a bind conflict must not look like a failure.
                ServeError::AlreadyRunning => ExitCode::from(EXIT_OK),
                ServeError::Io(_) => ExitCode::from(EXIT_FAILURE),
            }
        }
    }
}
