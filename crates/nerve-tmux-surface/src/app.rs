//! TUI event loop for the sidebar pane.

use std::io;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyModifiers, MouseButton, MouseEvent, MouseEventKind,
};
use ratatui::{Terminal, backend::CrosstermBackend};

type Tui = Terminal<CrosstermBackend<std::io::Stdout>>;

use crate::cli::toggle;
use crate::preview::JumpResult;
use crate::state::AppState;
use crate::tmux;
use crate::ui;
use nerve_surface_core::frame::JobView;
use nerve_surface_core::store::JobsStore;

const FILTER_ROW: u16 = 0;
const DOUBLE_CLICK_MS: u128 = 400;
/// Rows the detail panel scrolls per wheel notch.
const WHEEL_LINES: i32 = 2;
/// How often an idle sidebar redraws so relative ages (`3s`, `1m`) can move.
///
/// Input and a new hub frame still draw immediately; between those the loop
/// only polls. Five ratatui passes a second was the whole CPU of a quiet pane.
const IDLE_REDRAW: Duration = Duration::from_secs(1);

pub fn run(bottom_height: u16, home: PathBuf) -> io::Result<()> {
    let store = JobsStore::new();
    store.fetch_from_hub();
    let _reader = store.clone().spawn_reader(home, crate::stream::STREAM_PATH);
    let mut state = AppState::new(store, bottom_height);
    let mut stdout = io::stdout();
    crossterm::terminal::enable_raw_mode()?;
    crossterm::execute!(
        stdout,
        crossterm::event::EnableMouseCapture,
        crossterm::terminal::EnterAlternateScreen
    )?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;
    terminal.hide_cursor()?;

    let mut last_click: Option<(usize, Instant)> = None;
    let mut last_draw = Instant::now();
    let mut dirty = true;

    let result = loop {
        if state.refresh_from_hub() {
            dirty = true;
        }
        if dirty || last_draw.elapsed() >= IDLE_REDRAW {
            let size = terminal.size()?;
            state.set_viewport(size.width, size.height);
            terminal.draw(|frame| ui::draw(frame, &state))?;
            last_draw = Instant::now();
            dirty = false;
        }
        if !event::poll(Duration::from_millis(200))? {
            continue;
        }
        let mut quit = false;
        // Mouse capture reports motion per cell crossed. Drain everything the
        // terminal already queued, then refresh and draw once.
        loop {
            match event::read()? {
                Event::Key(key) => {
                    if handle_key(&mut state, &mut terminal, key) {
                        quit = true;
                        break;
                    }
                    dirty = true;
                }
                Event::Mouse(mouse) => {
                    handle_mouse(&mut state, &mut terminal, mouse, &mut last_click)?;
                    dirty = true;
                }
                _ => {}
            }
            if !event::poll(Duration::ZERO)? {
                break;
            }
        }
        if quit {
            break Ok(());
        }
    };

    restore_terminal(&mut terminal)?;
    result
}

/// Leave the alternate screen and hand the terminal back — both on exit and
/// while an external action (IDE open) owns the screen.
fn restore_terminal(terminal: &mut Tui) -> io::Result<()> {
    crossterm::terminal::disable_raw_mode()?;
    crossterm::execute!(
        terminal.backend_mut(),
        crossterm::event::DisableMouseCapture,
        crossterm::terminal::LeaveAlternateScreen
    )?;
    terminal.show_cursor()?;
    Ok(())
}

fn resume_after_external_action(terminal: &mut Tui) -> io::Result<()> {
    crossterm::execute!(
        terminal.backend_mut(),
        crossterm::event::EnableMouseCapture,
        crossterm::terminal::EnterAlternateScreen
    )?;
    crossterm::terminal::enable_raw_mode()?;
    terminal.hide_cursor()?;
    terminal.clear()?;
    Ok(())
}

/// The cursor lives in the job list and nowhere else.
///
/// The detail panel below is a view *of* the selected job, not a second place
/// to stand: it scrolls (`Ctrl-d`/`Ctrl-u`, `PageDown`/`PageUp`) and folds
/// (`Space`), but never takes the selection. `j`/`k` therefore stop at the
/// ends of the list.
fn handle_key(state: &mut AppState, terminal: &mut Tui, key: KeyEvent) -> bool {
    let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
    let page = i32::from(state.bottom_height.saturating_sub(1)).max(1);
    match key.code {
        KeyCode::Esc | KeyCode::Char('q') => toggle::unfocus_from_sidebar_tui(),
        KeyCode::Char('d') if ctrl => state.scroll_bottom(page / 2),
        KeyCode::Char('u') if ctrl => state.scroll_bottom(-page / 2),
        KeyCode::Char('j') | KeyCode::Down => state.move_selection(1),
        KeyCode::Char('k') | KeyCode::Up => state.move_selection(-1),
        KeyCode::Char('h') | KeyCode::Left => state.set_filter(state.status_filter.prev()),
        KeyCode::Char('l') | KeyCode::Right => state.set_filter(state.status_filter.next()),
        KeyCode::PageDown => state.scroll_bottom(page),
        KeyCode::PageUp => state.scroll_bottom(-page),
        KeyCode::Tab => state.set_filter(state.status_filter.next()),
        KeyCode::BackTab => state.toggle_bottom_tab(),
        KeyCode::Char(' ') => state.toggle_bottom_collapsed(),
        KeyCode::Enter | KeyCode::Char('\n') | KeyCode::Char('\r') => {
            if let Some(job) = state.selected_job().cloned() {
                let _ = jump_to_job(state, terminal, &job);
            }
        }
        _ => {}
    }
    false
}

fn handle_mouse(
    state: &mut AppState,
    terminal: &mut Tui,
    event: MouseEvent,
    last_click: &mut Option<(usize, Instant)>,
) -> io::Result<()> {
    // Mouse capture reports every cell the pointer crosses; only three kinds
    // mean anything here, and the rest must not cost a size query.
    if !matches!(
        event.kind,
        MouseEventKind::Down(MouseButton::Left)
            | MouseEventKind::ScrollUp
            | MouseEventKind::ScrollDown
    ) {
        return Ok(());
    }
    let size = terminal.size()?;
    let job_list_end = size.height.saturating_sub(state.bottom_rows(size.height));
    let over_bottom = event.row >= job_list_end;

    match event.kind {
        // The wheel scrolls the panel it is over; over the list it walks the
        // selection, coalesced into one preview swap by the loop tick.
        MouseEventKind::ScrollDown if over_bottom => state.scroll_bottom(WHEEL_LINES),
        MouseEventKind::ScrollUp if over_bottom => state.scroll_bottom(-WHEEL_LINES),
        MouseEventKind::ScrollDown => state.move_selection(1),
        MouseEventKind::ScrollUp => state.move_selection(-1),
        MouseEventKind::Down(MouseButton::Left) => {
            return click(state, terminal, event, last_click, job_list_end);
        }
        _ => {}
    }
    Ok(())
}

/// Click a filter chip, a job row, or the panel's title row to fold it.
/// Clicking the panel body does nothing: it holds no cursor to move there.
fn click(
    state: &mut AppState,
    terminal: &mut Tui,
    event: MouseEvent,
    last_click: &mut Option<(usize, Instant)>,
    job_list_end: u16,
) -> io::Result<()> {
    if event.row == FILTER_ROW {
        state.set_filter(state.status_filter.next());
        return Ok(());
    }
    // The panel's title row is its fold handle; the body below it is inert.
    if event.row == job_list_end {
        state.toggle_bottom_collapsed();
        return Ok(());
    }
    if event.row > job_list_end {
        return Ok(());
    }

    let list_row = (event.row - 1) as usize;
    let Some(global_idx) = state.global_index_at_list_row(list_row) else {
        return Ok(());
    };

    state.select_global_index(global_idx);

    let now = Instant::now();
    let double = last_click.as_ref().is_some_and(|(idx, t)| {
        *idx == global_idx && now.duration_since(*t).as_millis() <= DOUBLE_CLICK_MS
    });
    *last_click = Some((global_idx, now));

    if double && let Some(job) = state.selected_job().cloned() {
        jump_to_job(state, terminal, &job)?;
    }
    Ok(())
}

fn jump_to_job(state: &mut AppState, terminal: &mut Tui, job: &JobView) -> io::Result<()> {
    match state.preview.jump_to_job(job) {
        JumpResult::NeedsIde => {
            restore_terminal(terminal)?;
            if !state.preview.open_ide_for_job(job) {
                let _ = tmux::run_tmux(&[
                    "display-message",
                    "-d",
                    "2500",
                    "Nerve: could not open IDE link",
                ]);
            }
            resume_after_external_action(terminal)?;
        }
        JumpResult::TmuxPane | JumpResult::Failed => {}
    }
    Ok(())
}
