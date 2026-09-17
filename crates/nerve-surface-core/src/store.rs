//! Hub job store — one SSE reader thread, many TUI readers.

use std::path::PathBuf;
use std::sync::{Arc, RwLock};
use std::thread;

use crate::frame::{Frame, JobView};
use crate::hub::Hub;
use crate::launch::{DetachedSpawner, HttpHealth, HubLauncher, SystemClock};
use crate::locate::{FileProbe, HubLocator};
use crate::stream::{Backoff, FrameSource, HubFrameSource, JOBS_PATH};

#[derive(Clone, Debug, Default)]
pub struct JobsSnapshot {
    pub jobs: Vec<JobView>,
    pub offline: bool,
}

#[derive(Clone)]
pub struct JobsStore {
    inner: Arc<RwLock<Arc<JobsSnapshot>>>,
}

impl JobsStore {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(RwLock::new(Arc::new(JobsSnapshot::default()))),
        }
    }

    /// Share the current snapshot. Readers get an `Arc`, not a deep copy of
    /// every job's timeline — the TUI reads this on every loop wake.
    pub fn snapshot(&self) -> Arc<JobsSnapshot> {
        self.inner
            .read()
            .map(|guard| Arc::clone(&guard))
            .unwrap_or_default()
    }

    /// Pull the hub's current job list before subscribing to SSE.
    ///
    /// Fail-open: a bad read leaves whatever the store already held.
    pub fn fetch_from_hub(&self) {
        let Ok(raw) = Hub::loopback().get(JOBS_PATH) else {
            return;
        };
        let Ok(jobs) = Frame::decode_jobs_list(&raw) else {
            return;
        };
        self.set_jobs(jobs);
    }

    /// Replace the whole set, wholesale.
    ///
    /// Never merged: a frame is the authoritative full list, which is exactly
    /// what makes a dropped connection cost nothing. Also how a surface's tests
    /// seed a store without a hub.
    pub fn set_jobs(&self, jobs: Vec<JobView>) {
        if let Ok(mut guard) = self.inner.write() {
            *guard = Arc::new(JobsSnapshot {
                jobs,
                offline: false,
            });
        }
    }

    fn set_offline(&self) {
        if let Ok(mut guard) = self.inner.write() {
            if guard.offline {
                return;
            }
            *guard = Arc::new(JobsSnapshot {
                jobs: guard.jobs.clone(),
                offline: true,
            });
        }
    }

    /// Attach to the hub forever, on a thread of its own.
    ///
    /// `stream_path` names which surface is asking; the hub treats it as a log
    /// tag (`crates/nerve-hub/src/http/stream.rs`). Holding this stream open is
    /// what keeps the hub alive, so the thread outlives any window.
    pub fn spawn_reader(
        self,
        home: PathBuf,
        stream_path: impl Into<String>,
    ) -> thread::JoinHandle<()> {
        let stream_path = stream_path.into();
        thread::spawn(move || {
            let locator = HubLocator::new(FileProbe, home);
            let mut launcher = HubLauncher::new(
                DetachedSpawner::new(),
                SystemClock,
                HttpHealth::new(Hub::loopback()),
            );
            let mut source = HubFrameSource::new(Hub::loopback(), stream_path);
            let mut backoff = Backoff::new();
            loop {
                launcher.ensure(locator.locate().as_deref());
                self.fetch_from_hub();
                if source.open().is_err() {
                    self.set_offline();
                    thread::sleep(backoff.fail());
                    continue;
                }
                let mut frames = 0usize;
                while let Ok(Some(frame)) = source.next_frame() {
                    frames += 1;
                    self.set_jobs(frame.jobs);
                }
                self.set_offline();
                if frames > 0 {
                    backoff.reset();
                }
                thread::sleep(backoff.fail());
            }
        })
    }
}

impl Default for JobsStore {
    fn default() -> Self {
        Self::new()
    }
}
