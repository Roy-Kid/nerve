//! Wire types: what producers report and what surfaces read back.
//!
//! Pure data plus the predicates that belong to the data (job identity, legacy
//! noise, timeline titles). No storage, no HTTP, no display derivation.

pub mod envelope;
pub mod event;
pub mod facet;
pub mod job;
pub mod time;

pub use envelope::Envelope;
pub use event::{Event, EventKind};
pub use facet::{
    ActionState, Attention, AttentionLevel, ContextInfo, Current, Health, JobAction, Lifecycle,
    LocationInfo, Outcome, ProducerInfo, Progress, ProgressKind, ProgressMetric,
};
pub use job::{Extensions, Job};
pub use time::WireTime;
