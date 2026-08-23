//! Git summary for the bottom panel — shortstat + file list.

use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Clone, Debug, Default)]
pub struct GitSnapshot {
    pub branch: String,
    pub ahead: u32,
    pub behind: u32,
    pub staged: Vec<String>,
    pub unstaged: Vec<String>,
    pub untracked: Vec<String>,
    pub error: Option<String>,
}

impl GitSnapshot {
    /// Lines [`crate::ui`] renders for this snapshot — the branch row plus one
    /// row per changed file, or the error on its own.
    pub fn line_count(&self) -> usize {
        if self.error.is_some() {
            return 1;
        }
        1 + self.staged.len() + self.unstaged.len() + self.untracked.len()
    }
}

/// Rows the Git panel can show per section. `ls-files --others` on a large
/// worktree is unbounded; nothing past this is ever rendered.
pub const LIST_CAP: usize = 6;

pub fn snapshot_for_path(path: &Path) -> GitSnapshot {
    let Some(repo) = find_git_root(path) else {
        return GitSnapshot {
            error: Some("not a git repo".to_string()),
            ..GitSnapshot::default()
        };
    };
    let (behind, ahead) = git_output(
        &repo,
        &["rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
    )
    .map(|counts| {
        let mut parts = counts.split_whitespace();
        let behind = parts.next().and_then(|v| v.parse().ok()).unwrap_or(0);
        let ahead = parts.next().and_then(|v| v.parse().ok()).unwrap_or(0);
        (behind, ahead)
    })
    .unwrap_or((0, 0));
    GitSnapshot {
        branch: git_output(&repo, &["rev-parse", "--abbrev-ref", "HEAD"])
            .unwrap_or_else(|| "-".into()),
        ahead,
        behind,
        staged: git_lines(&repo, &["diff", "--cached", "--name-status"]),
        unstaged: git_lines(&repo, &["diff", "--name-status"]),
        untracked: git_lines(&repo, &["ls-files", "--others", "--exclude-standard"])
            .into_iter()
            .map(|line| format!("? {line}"))
            .collect(),
        error: None,
    }
}

fn find_git_root(mut path: &Path) -> Option<PathBuf> {
    loop {
        if path.join(".git").exists() {
            return Some(path.to_path_buf());
        }
        path = path.parent()?;
    }
}

fn git_output(repo: &Path, args: &[&str]) -> Option<String> {
    let output = Command::new("git")
        .args(args)
        .current_dir(repo)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    (!text.is_empty()).then_some(text)
}

/// At most [`LIST_CAP`] lines — the panel never renders more.
fn git_lines(repo: &Path, args: &[&str]) -> Vec<String> {
    git_output(repo, args)
        .map(|text| text.lines().take(LIST_CAP).map(str::to_string).collect())
        .unwrap_or_default()
}
