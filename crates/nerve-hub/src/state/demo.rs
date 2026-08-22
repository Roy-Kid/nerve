//! The rows `POST /v1/demo` seeds.
//!
//! Ported value for value from `SubjectStore.swift:1039`: four open jobs on this
//! machine, from a producer called `demo`, anchored to the store's clock. Ended
//! rows are deliberately not demo'd — a closed session evicts immediately, so a
//! demo one would vanish as fast as it appeared.

use crate::model::{
    Attention, AttentionLevel, Current, Extensions, Health, Job, Lifecycle, LocationInfo,
    ProducerInfo, Progress, ProgressKind, WireTime,
};

/// The four demo rows, as data.
///
/// Holds what the rows are made of — this machine's alias and the instant they
/// are anchored to — so the store can ask for them without knowing any of it.
pub struct DemoRows {
    alias: String,
    now: WireTime,
}

impl DemoRows {
    pub fn new(alias: String, now: WireTime) -> Self {
        Self { alias, now }
    }

    /// The rows, in the order the app seeds them.
    pub fn jobs(&self) -> Vec<Job> {
        vec![
            self.editing_session(),
            self.running_build(),
            self.waiting_session(),
            self.stalled_process(),
        ]
    }

    /// An agent mid-edit, with somewhere to send the human back to.
    fn editing_session(&self) -> Job {
        let mut job = self.row("demo-1", "session", "nerve", -3600);
        job.current = Some(Current {
            kind: "editing".to_string(),
            name: Some("Implement ribbon".to_string()),
            summary: Some("Drawing menu-bar ribbon".to_string()),
            detail: None,
            started_at: Some(self.at(-120)),
        });
        job.location = Some(LocationInfo {
            open_url: Some("file:///tmp".to_string()),
            focus_hint: Some("Demo · nerve · session · /tmp".to_string()),
            log_path: None,
        });
        job
    }

    /// A build with progress it cannot quantify.
    fn running_build(&self) -> Job {
        let mut job = self.row("demo-2", "build", "xcodebuild Nerve", -600);
        job.current = Some(Current {
            kind: "building".to_string(),
            name: None,
            summary: Some("Compiling 42 files".to_string()),
            detail: None,
            started_at: Some(self.at(-90)),
        });
        job.progress = Progress {
            kind: ProgressKind::Indeterminate,
            ratio: None,
            label: Some("Building".to_string()),
            metrics: None,
        };
        job
    }

    /// Your turn — attention that means "return to the agent UI", never "type
    /// here": the hub does not reverse-control an agent.
    fn waiting_session(&self) -> Job {
        let mut job = self.row("demo-3", "session", "nerve", -300);
        job.current = Some(Current {
            kind: "idle".to_string(),
            name: None,
            summary: Some("Your turn — continue in the agent UI".to_string()),
            detail: None,
            started_at: Some(self.at(-60)),
        });
        job.attention = Attention {
            level: AttentionLevel::Suggested,
            reason: Some("input".to_string()),
            title: Some("Your turn in agent".to_string()),
            summary: Some("Return to the agent to continue".to_string()),
            deferrable: None,
            deadline: None,
        };
        job.location = Some(LocationInfo {
            open_url: Some("file:///tmp".to_string()),
            focus_hint: Some("Demo · nerve · Terminal · /tmp".to_string()),
            log_path: None,
        });
        job
    }

    /// Long-running work that stopped reporting.
    fn stalled_process(&self) -> Job {
        let mut job = self.row("demo-4", "process", "long-job", -900);
        job.current = Some(Current {
            kind: "computing".to_string(),
            name: None,
            summary: Some("No heartbeat".to_string()),
            detail: None,
            started_at: Some(self.at(-900)),
        });
        job.health = Health::Unresponsive;
        job.attention = Attention {
            level: AttentionLevel::Suggested,
            reason: Some("stale".to_string()),
            title: Some("Possibly stuck".to_string()),
            summary: Some("No update for 15m".to_string()),
            deferrable: None,
            deadline: None,
        };
        job
    }

    /// A row as `Job.make` would build it (`Subject.swift:154`): open, healthy,
    /// unremarkable, with every date anchored `age_secs` before now.
    fn row(&self, id: &str, kind: &str, name: &str, age_secs: i64) -> Job {
        let born = self.at(age_secs);
        Job {
            id: id.to_string(),
            kind: kind.to_string(),
            name: name.to_string(),
            alias: self.alias.clone(),
            lifecycle: Lifecycle::Active,
            current: None,
            attention: Attention::default(),
            health: Health::Ok,
            outcome: None,
            progress: Progress::default(),
            producer: ProducerInfo {
                id: "demo".to_string(),
                name: Some("Demo".to_string()),
                kind: Some("demo".to_string()),
            },
            context: None,
            location: None,
            capabilities: Vec::new(),
            actions: Vec::new(),
            created_at: born,
            started_at: Some(born),
            ended_at: None,
            updated_at: born,
            version: 1,
            extensions: Extensions::new(),
        }
    }

    fn at(&self, offset_secs: i64) -> WireTime {
        self.now.plus_seconds(offset_secs)
    }
}
