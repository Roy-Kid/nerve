//! Render the tray icon at every DPI rung and every state, as one PNG sheet.
//!
//! `cargo run -p nerve-windows-surface --example icon_sheet -- <out.png>`
//!
//! The point is to look at it at real size before building a surface around
//! it: a 16 px icon either reads at a glance or the whole design is wrong, and
//! that is not a question a unit test answers.

use nerve_surface_core::status::StatusClass;
use nerve_surface_core::tally::Tally;
use nerve_windows_surface::tray::bands::stack;
use nerve_windows_surface::tray::icon::{render, IconSpec, Theme};
use tiny_skia::Pixmap;

const RUNGS: [u32; 5] = [16, 20, 24, 28, 32];
const SCALE: u32 = 6;
const PAD: u32 = 6;

fn tally(pairs: &[(StatusClass, usize)]) -> Tally {
    let mut tally = Tally::default();
    for (class, count) in pairs {
        match class {
            StatusClass::Problem => tally.problem = *count,
            StatusClass::Attention => tally.attention = *count,
            StatusClass::Waiting => tally.waiting = *count,
            StatusClass::Running => tally.running = *count,
            StatusClass::Monitor => tally.monitor = *count,
            StatusClass::Success => tally.success = *count,
            StatusClass::Inactive => tally.inactive = *count,
        }
    }
    tally
}

fn main() {
    let out = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "icons.png".into());

    let cases: Vec<(&str, Tally, bool)> = vec![
        ("idle", Tally::default(), false),
        ("one running", tally(&[(StatusClass::Running, 1)]), false),
        ("four running", tally(&[(StatusClass::Running, 4)]), false),
        (
            "one problem, forty running",
            tally(&[(StatusClass::Problem, 1), (StatusClass::Running, 40)]),
            false,
        ),
        (
            "needs you + running",
            tally(&[(StatusClass::Attention, 2), (StatusClass::Running, 3)]),
            false,
        ),
        (
            "all three slots",
            tally(&[
                (StatusClass::Problem, 1),
                (StatusClass::Running, 3),
                (StatusClass::Success, 2),
            ]),
            false,
        ),
        ("offline", tally(&[(StatusClass::Running, 3)]), true),
    ];

    let themes = [Theme::Dark, Theme::Light];
    let cell = RUNGS.iter().max().unwrap() * SCALE + PAD * 2;
    let width = cell * RUNGS.len() as u32;
    let height = cell * (cases.len() * themes.len()) as u32;
    let mut sheet = Pixmap::new(width, height).expect("sheet");

    for (row, (label, tally, offline)) in cases.iter().enumerate() {
        for (theme_index, theme) in themes.iter().enumerate() {
            let y_cell = (row * themes.len() + theme_index) as u32 * cell;
            // A dark taskbar behind the dark-theme row, light behind the other.
            let bg = if *theme == Theme::Dark { 0x1C } else { 0xF2 };
            for y in y_cell..(y_cell + cell).min(height) {
                for x in 0..width {
                    let index = ((y * width + x) * 4) as usize;
                    let data = sheet.data_mut();
                    data[index] = bg;
                    data[index + 1] = bg;
                    data[index + 2] = bg;
                    data[index + 3] = 0xFF;
                }
            }
            for (column, size) in RUNGS.iter().enumerate() {
                let spec = IconSpec {
                    size: *size,
                    bands: stack(tally),
                    offline: *offline,
                    theme: *theme,
                };
                let rgba = render(&spec);
                let origin_x = column as u32 * cell + PAD;
                let origin_y = y_cell + PAD;
                // Nearest-neighbour by hand: the point of the sheet is to see
                // the exact pixels the tray will get, so nothing may resample.
                for sy in 0..*size {
                    for sx in 0..*size {
                        let src = ((sy * size + sx) * 4) as usize;
                        let (r, g, b, a) = (
                            rgba[src] as f32,
                            rgba[src + 1] as f32,
                            rgba[src + 2] as f32,
                            rgba[src + 3] as f32 / 255.0,
                        );
                        for dy in 0..SCALE {
                            for dx in 0..SCALE {
                                let x = origin_x + sx * SCALE + dx;
                                let y = origin_y + sy * SCALE + dy;
                                if x >= width || y >= height {
                                    continue;
                                }
                                let dst = ((y * width + x) * 4) as usize;
                                let data = sheet.data_mut();
                                let over =
                                    |s: f32, d: u8| (s * a + d as f32 * (1.0 - a)).round() as u8;
                                data[dst] = over(r, data[dst]);
                                data[dst + 1] = over(g, data[dst + 1]);
                                data[dst + 2] = over(b, data[dst + 2]);
                                data[dst + 3] = 0xFF;
                            }
                        }
                    }
                }
            }
            println!(
                "row {:>2}  {label} ({theme:?})",
                row * themes.len() + theme_index
            );
        }
    }

    sheet.save_png(&out).expect("write png");
    println!("\nwrote {out} — columns are {RUNGS:?} px, scaled {SCALE}x");
}
