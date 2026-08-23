//! Composition root for the Nerve tmux sidebar surface.

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use nerve_tmux_surface::app;
use nerve_tmux_surface::cli;
use nerve_tmux_surface::tmux;

const USAGE: &str = "\
nerve-tmux-surface - the tmux sidebar surface of the Nerve hub

Usage:
  nerve-tmux-surface            Run the sidebar TUI (inside a tmux split pane).
  nerve-tmux-surface toggle     Open or toggle focus on the sidebar in one window.
  nerve-tmux-surface close      Close the sidebar when its pane is focused.
  nerve-tmux-surface auto-close Close a window that only has the sidebar left.

The sidebar reads jobs from nerve-hub on 127.0.0.1:17890.
  j/k        preview selected job in the sibling pane
  Enter      jump to that job's pane (another machine: its ssh pane, and that
             machine's tmux selects the job's own window)
  h/l/Tab    cycle the status filter
  S-Tab      Prompt / Git panel; C-d/C-u scroll, Space folds it
  prefix+e   open (no focus) / toggle focus
  prefix+q   close when sidebar focused (q/Esc unfocus)";

const EXIT_OK: u8 = 0;
const EXIT_USAGE: u8 = 2;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    if let Some(code) = cli::run(&args) {
        return ExitCode::from(code.clamp(0, 255) as u8);
    }
    if args.is_empty() {
        return run_tui();
    }
    eprintln!("{USAGE}");
    ExitCode::from(EXIT_USAGE)
}

fn run_tui() -> ExitCode {
    if env::var_os("TMUX_PANE").is_none() {
        eprintln!("TMUX_PANE not set");
        return ExitCode::from(EXIT_USAGE);
    }
    let bottom_height = bottom_height_from_tmux();
    match app::run(bottom_height, home()) {
        Ok(()) => ExitCode::from(EXIT_OK),
        Err(err) => {
            eprintln!("nerve-tmux-surface: {err}");
            ExitCode::from(EXIT_USAGE)
        }
    }
}

fn bottom_height_from_tmux() -> u16 {
    let raw = tmux::display_message(
        "#{pane_id}",
        &format!("#{{{}}}", tmux::SIDEBAR_BOTTOM_HEIGHT),
    );
    raw.parse::<u16>().unwrap_or(20).clamp(0, 60)
}

fn home() -> PathBuf {
    env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}
