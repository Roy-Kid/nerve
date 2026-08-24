pub mod install;
pub mod toggle;

/// Run a CLI subcommand. `None` means launch the sidebar TUI.
pub fn run(args: &[String]) -> Option<i32> {
    let cmd = args.first().map(String::as_str)?;
    let rest = &args[1..];
    let code = match cmd {
        "install" => install::cmd_install(rest),
        "toggle" => toggle::cmd_toggle(rest),
        "close" => toggle::cmd_close(rest),
        "auto-close" => toggle::cmd_auto_close(rest),
        "--version" | "version" => {
            println!("{}", env!("CARGO_PKG_VERSION"));
            0
        }
        _ => return None,
    };
    Some(code)
}
