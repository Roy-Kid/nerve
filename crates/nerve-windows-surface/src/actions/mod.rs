//! What this surface may do about a job.
//!
//! Which is very little, on purpose. CLAUDE.md invariant 6: Nerve never
//! reverse-controls an agent. There is no approve, no cancel, no submit_input
//! — a job's `actions` list is something to *classify*, never to perform.
//! Attention means "return to the agent UI", not "type here".
//!
//! So the whole verb list is: take me to where this is happening, or put the
//! location on the clipboard so I can get there myself.

pub mod open;
