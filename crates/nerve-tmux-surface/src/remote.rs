//! Steering the tmux on the *other* machine, over one ssh round trip.
//!
//! A job on another machine has no pane here, and the ssh pane that reaches it
//! is the machine's single viewport (`crate::ssh`) — it shows whatever the
//! remote client is attached to, which is rarely the job you picked. What tmux
//! cannot do is show a foreign server's pane locally; what it *can* do is run
//! the same `pid → tty → pane` resolution **over there** and tell that tmux to
//! select the result. So that is what this does: `Enter` focuses the ssh pane
//! here, and one `ssh <host> sh -s` makes the far side turn to the right window.
//!
//! Deliberately not tmux control mode (`tmux -CC`, what iTerm2 speaks): control
//! mode streams a whole window tree, cursor positions and resize events so a
//! terminal emulator can render remote panes itself. This surface is a TUI
//! *inside* tmux, not an emulator — it needs one imperative "select that
//! window", not a mirror of the remote UI.
//!
//! Everything here is fail-open. The remote may have no tmux, the agent may not
//! be in a pane, ssh may need a password this process must never be asked for
//! (`BatchMode=yes`): each of those is an answer, none is an error the sidebar
//! propagates.

use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::{Arc, Condvar, Mutex, OnceLock};

/// How long ssh may spend getting a connection before giving up.
///
/// A live `ControlMaster` answers in tens of milliseconds; without one this is
/// the whole budget, because the alternative is a TUI blocked on a handshake.
const CONNECT_TIMEOUT_SECS: u32 = 3;

/// Exit codes the remote script uses to say what it found.
mod code {
    pub const NO_TERMINAL: i32 = 3;
    pub const NOT_IN_TMUX: i32 = 4;
    pub const REFUSED: i32 = 5;
    pub const NO_TMUX: i32 = 6;
    /// ssh's own "I could not get there".
    pub const SSH_FAILED: i32 = 255;
}

/// What the far side did.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RemoteJump {
    /// That tmux is now showing the job. `clients` is how many were attached —
    /// the view only followed when there was exactly one to follow.
    Selected { pane: String, clients: usize },
    /// The agent process is on no pane of that tmux (a bare ssh shell, say).
    NotInTmux,
    /// The process is gone there, or has no controlling terminal.
    NoTerminal,
    /// No tmux on that machine — or none on `PATH` in a non-interactive shell.
    NoTmux,
    /// tmux was there and refused the select.
    Refused,
    /// ssh could not get there: no live master and no non-interactive auth.
    Unreachable,
}

impl RemoteJump {
    /// What to flash in the status line, or nothing when the far side simply
    /// did what was asked (the window changing under you says it better).
    pub fn message(&self, host: &str) -> Option<String> {
        match self {
            Self::Selected { clients, .. } if *clients <= 1 => None,
            Self::Selected { clients, .. } => Some(format!(
                "Nerve: selected the window on {host} ({clients} clients attached — none was moved)"
            )),
            Self::NotInTmux => Some(format!("Nerve: that job is not in a tmux pane on {host}")),
            Self::NoTerminal => Some(format!("Nerve: no terminal for that job on {host}")),
            Self::NoTmux => Some(format!("Nerve: no tmux on {host}")),
            Self::Refused => Some(format!("Nerve: tmux on {host} refused the select")),
            Self::Unreachable => Some(format!("Nerve: could not reach {host} without a prompt")),
        }
    }
}

/// One machine and one job — what the far side is asked to show.
#[derive(Clone, Debug, PartialEq, Eq)]
struct Request {
    host: String,
    pid: u32,
}

/// A one-slot inbox where a newer request replaces an older one.
///
/// Selection moves faster than a network: holding `j` across three remote rows
/// asks for three windows, and the only one that matters is the last. Queuing
/// them would make the far side flip through every row the cursor passed and,
/// worse, land wherever the *slowest* call finished.
#[derive(Debug, Default)]
struct Mailbox {
    pending: Option<Request>,
    closed: bool,
}

/// Serialises remote selects: one call in flight, latest request wins.
pub struct RemoteSelector {
    inbox: Arc<(Mutex<Mailbox>, Condvar)>,
    worker: OnceLock<()>,
}

impl RemoteSelector {
    pub fn new() -> Self {
        Self {
            inbox: Arc::new((Mutex::new(Mailbox::default()), Condvar::new())),
            worker: OnceLock::new(),
        }
    }

    /// Ask `host` to show `pid`'s window, without waiting for it.
    ///
    /// The worker thread starts on the first request, so a surface that never
    /// looks at another machine never spawns one.
    pub fn request(&self, host: &str, pid: u32) {
        let inbox = Arc::clone(&self.inbox);
        self.worker.get_or_init(|| {
            std::thread::spawn(move || serve(&inbox));
        });
        let (lock, signal) = &*self.inbox;
        if let Ok(mut mailbox) = lock.lock() {
            mailbox.pending = Some(Request {
                host: host.to_string(),
                pid,
            });
        }
        signal.notify_one();
    }
}

impl Default for RemoteSelector {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for RemoteSelector {
    fn drop(&mut self) {
        let (lock, signal) = &*self.inbox;
        if let Ok(mut mailbox) = lock.lock() {
            mailbox.closed = true;
        }
        signal.notify_one();
    }
}

/// Take the newest request, run it, repeat until the selector is dropped.
fn serve(inbox: &(Mutex<Mailbox>, Condvar)) {
    let (lock, signal) = inbox;
    loop {
        let Ok(mut mailbox) = lock.lock() else {
            return;
        };
        while mailbox.pending.is_none() && !mailbox.closed {
            let Ok(next) = signal.wait(mailbox) else {
                return;
            };
            mailbox = next;
        }
        let request = mailbox.pending.take();
        let closed = mailbox.closed;
        drop(mailbox);

        match request {
            // The call happens outside the lock, so a newer selection can
            // replace what is pending while this one is still on the wire.
            Some(request) => report(&request.host, select_job(&request.host, request.pid)),
            None if closed => return,
            None => {}
        }
    }
}

/// Flash what the far side could not do. A window that simply changed says it
/// better than any message could.
fn report(host: &str, outcome: RemoteJump) {
    if let Some(message) = outcome.message(host) {
        let _ = crate::tmux::run_tmux(&["display-message", "-d", "3000", &message]);
    }
}

/// Ask `host`'s tmux to show the pane the agent `pid` is running on.
///
/// Blocking, and meant to be called off the draw loop: the local jump has
/// already happened by the time this returns.
pub fn select_job(host: &str, pid: u32) -> RemoteJump {
    let mut child = match Command::new("ssh")
        .args([
            "-o",
            "BatchMode=yes",
            "-o",
            &format!("ConnectTimeout={CONNECT_TIMEOUT_SECS}"),
            host,
            // The script arrives on stdin, so the user's remote login shell
            // (fish, csh…) never has to parse it, and nothing is quoted into a
            // command line.
            "sh",
            "-s",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return RemoteJump::Unreachable,
    };

    if let Some(stdin) = child.stdin.as_mut() {
        if stdin.write_all(script(pid).as_bytes()).is_err() {
            return RemoteJump::Unreachable;
        }
    }
    // Dropping stdin is what tells `sh -s` the script is finished.
    drop(child.stdin.take());

    match child.wait_with_output() {
        Ok(output) => outcome(
            output.status.code(),
            &String::from_utf8_lossy(&output.stdout),
        ),
        Err(_) => RemoteJump::Unreachable,
    }
}

/// The script the far side runs.
///
/// The same resolution `crate::preview` does locally — the agent's pid sits on
/// exactly one tty, and one pane has that tty — followed by the same three tmux
/// commands `Enter` runs here. `pid` is a `u32`, so the one value interpolated
/// into this text cannot be anything but digits.
///
/// The client is only moved when exactly one is attached: with several, the one
/// in *this* ssh pane cannot be told from someone else's session, and dragging a
/// stranger's view to another window would be worse than doing nothing.
fn script(pid: u32) -> String {
    format!(
        r#"pid={pid}
tty=$(ps -p $pid -o tty= 2>/dev/null | tr -d ' \t')
[ -n "$tty" ] && [ "$tty" != "?" ] || exit {no_terminal}
command -v tmux >/dev/null 2>&1 || exit {no_tmux}
pane=$(tmux list-panes -a -F '#{{pane_tty}} #{{pane_id}}' 2>/dev/null \
  | awk -v t="/dev/$tty" '$1==t{{print $2; exit}}')
[ -n "$pane" ] || exit {not_in_tmux}
tmux select-window -t "$pane" >/dev/null 2>&1 || exit {refused}
tmux select-pane -t "$pane" >/dev/null 2>&1
clients=$(tmux list-clients -F '#{{client_tty}}' 2>/dev/null)
count=$(printf '%s\n' "$clients" | grep -c .)
if [ "$count" = 1 ]; then
  session=$(tmux display-message -p -t "$pane" '#{{session_name}}' 2>/dev/null)
  [ -n "$session" ] && tmux switch-client -c "$clients" -t "$session" >/dev/null 2>&1
fi
printf '%s %s\n' "$pane" "$count"
"#,
        pid = pid,
        no_terminal = code::NO_TERMINAL,
        no_tmux = code::NO_TMUX,
        not_in_tmux = code::NOT_IN_TMUX,
        refused = code::REFUSED,
    )
}

/// Read the far side's answer. Pure, so every arm is a test rather than a trip.
fn outcome(status: Option<i32>, stdout: &str) -> RemoteJump {
    match status {
        Some(0) => match parse_selection(stdout) {
            Some((pane, clients)) => RemoteJump::Selected { pane, clients },
            // Exit 0 with nothing to say is not a selection anyone can trust.
            None => RemoteJump::Refused,
        },
        Some(code::NO_TERMINAL) => RemoteJump::NoTerminal,
        Some(code::NOT_IN_TMUX) => RemoteJump::NotInTmux,
        Some(code::REFUSED) => RemoteJump::Refused,
        Some(code::NO_TMUX) => RemoteJump::NoTmux,
        Some(code::SSH_FAILED) | None => RemoteJump::Unreachable,
        // The remote shell could not even start the script (127 and friends).
        Some(_) => RemoteJump::NoTmux,
    }
}

/// `"%25 1"` — the pane that was selected, and how many clients were attached.
fn parse_selection(stdout: &str) -> Option<(String, usize)> {
    let line = stdout.lines().last()?.trim();
    let (pane, clients) = line.split_once(char::is_whitespace)?;
    let pane = pane.trim();
    if !pane.starts_with('%') {
        return None;
    }
    Some((pane.to_string(), clients.trim().parse().ok()?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_selected_pane_is_read_back_with_its_client_count() {
        assert_eq!(
            outcome(Some(0), "%25 1\n"),
            RemoteJump::Selected {
                pane: "%25".to_string(),
                clients: 1
            }
        );
    }

    #[test]
    fn every_refusal_the_far_side_can_report_has_its_own_answer() {
        assert_eq!(outcome(Some(code::NO_TERMINAL), ""), RemoteJump::NoTerminal);
        assert_eq!(outcome(Some(code::NOT_IN_TMUX), ""), RemoteJump::NotInTmux);
        assert_eq!(outcome(Some(code::REFUSED), ""), RemoteJump::Refused);
        assert_eq!(outcome(Some(code::NO_TMUX), ""), RemoteJump::NoTmux);
    }

    #[test]
    fn ssh_failing_to_get_there_is_not_a_tmux_answer() {
        assert_eq!(outcome(Some(code::SSH_FAILED), ""), RemoteJump::Unreachable);
        // Killed by a signal — no code at all.
        assert_eq!(outcome(None, ""), RemoteJump::Unreachable);
    }

    #[test]
    fn success_without_a_pane_id_is_not_believed() {
        assert_eq!(outcome(Some(0), ""), RemoteJump::Refused);
        assert_eq!(outcome(Some(0), "ok\n"), RemoteJump::Refused);
        assert_eq!(outcome(Some(0), "%25\n"), RemoteJump::Refused);
    }

    #[test]
    fn only_a_view_that_did_not_follow_is_worth_saying_out_loud() {
        let followed = RemoteJump::Selected {
            pane: "%25".to_string(),
            clients: 1,
        };
        assert_eq!(followed.message("Arrhenius"), None);

        let shared = RemoteJump::Selected {
            pane: "%25".to_string(),
            clients: 3,
        };
        assert!(shared.message("Arrhenius").is_some_and(|m| m.contains("3")));
        assert!(RemoteJump::NotInTmux
            .message("Arrhenius")
            .is_some_and(|m| m.contains("Arrhenius")));
    }

    #[test]
    fn a_newer_request_replaces_the_one_still_waiting() {
        let selector = RemoteSelector::new();
        // No worker is started until something is actually asked for.
        assert!(selector.worker.get().is_none());

        let (lock, _) = &*selector.inbox;
        lock.lock().expect("inbox").pending = Some(Request {
            host: "Arrhenius".to_string(),
            pid: 1,
        });
        lock.lock().expect("inbox").pending = Some(Request {
            host: "Arrhenius".to_string(),
            pid: 2,
        });
        assert_eq!(
            lock.lock().expect("inbox").pending.as_ref().map(|r| r.pid),
            Some(2),
            "the cursor's latest stop is the only one worth asking for"
        );
    }

    #[test]
    fn the_script_carries_the_pid_and_nothing_else_from_here() {
        let script = script(668_866);
        assert!(script.contains("pid=668866"));
        // One interpolation, and it is digits: nothing in this text can be
        // turned into another command by a job's report.
        assert_eq!(script.matches("668866").count(), 1);
        assert!(script.contains("tmux select-window"));
        assert!(script.contains("switch-client"));
    }
}
