/**
 * Display derivation, mirrored from Swift (`Subject.swift:38-100`) and the
 * tmux transcription (`crates/nerve-tmux-surface/src/status.rs`).
 *
 * The hub publishes no derived `status`. Surfaces paint facets. Free text
 * never classifies (CLAUDE.md invariant 3).
 */

import type { AttentionLevel, Job, Status } from "./job";
export { STATUS_PRIORITY } from "./job";

const WAIT_REASONS = [
  "resource",
  "dependency",
  "queue",
  "system",
  "lock",
  "throttle",
  "rate",
  "capacity",
  "failure",
] as const;

const ASK_REASONS = [
  "input",
  "approval",
  "auth",
  "permission",
  "decision",
  "elicitation",
] as const;

const BUSY_KINDS = ["subagent", "tool", "thinking", "info"] as const;
const IDLE_KINDS = ["idle", "starting", "booting"] as const;

const ATTENTION_RANK: Record<AttentionLevel, number> = {
  none: 0,
  informational: 1,
  suggested: 2,
  required: 3,
  urgent: 4,
};

function names(value: string | undefined, set: readonly string[]): boolean {
  if (!value) return false;
  const trimmed = value.trim();
  return set.some((known) => known.toLowerCase() === trimmed.toLowerCase());
}

function fromAttention(job: Job): Status | undefined {
  if (ATTENTION_RANK[job.attention.level] >= ATTENTION_RANK.suggested) {
    return "attention";
  }
  if (ATTENTION_RANK[job.attention.level] >= ATTENTION_RANK.informational) {
    const reason = job.attention.reason;
    if (!reason) return undefined;
    if (names(reason, ASK_REASONS) || names(reason, WAIT_REASONS)) {
      return "attention";
    }
  }
  return undefined;
}

function fromStage(job: Job): Status | undefined {
  if (job.lifecycle === "ended") {
    if (job.outcome === "success" || job.outcome === "partial") return "success";
    return "inactive";
  }
  if (job.lifecycle === "suspended" || job.lifecycle === "unknown") {
    return "inactive";
  }
  if (job.lifecycle === "pending" || job.lifecycle === "created") {
    return "attention";
  }
  if (job.health === "degraded") return "attention";
  if (job.lifecycle === "active" && job.outcome === "partial") return "monitor";
  return undefined;
}

function fromActivity(job: Job): Status | undefined {
  const kind = job.current?.type;
  if (!kind) return undefined;
  if (names(kind, BUSY_KINDS)) {
    return job.lifecycle === "active" ? "running" : undefined;
  }
  if (names(kind, ["monitor"])) return "monitor";
  if (names(kind, ["waiting"])) return "attention";
  if (names(kind, IDLE_KINDS)) return "inactive";
  return undefined;
}

export function statusOf(job: Job): Status {
  if (job.outcome === "failure") return "problem";
  if (job.health === "unresponsive") return "problem";

  const attention = fromAttention(job);
  if (attention) return attention;
  const stage = fromStage(job);
  if (stage) return stage;
  const activity = fromActivity(job);
  if (activity) return activity;

  return job.lifecycle === "active" ? "running" : "inactive";
}

export function statusTitle(status: Status): string {
  switch (status) {
    case "problem":
      return "Problem";
    case "attention":
      return "Attention";
    case "waiting":
      return "Waiting";
    case "running":
      return "Running";
    case "monitor":
      return "Monitor";
    case "success":
      return "Success";
    case "inactive":
      return "Inactive";
  }
}

export function statusRank(status: Status): number {
  return ["problem", "attention", "waiting", "running", "monitor", "success", "inactive"].indexOf(
    status,
  );
}

/** Worst (most urgent) painted status in a set. Empty → inactive. */
export function worstStatus(statuses: readonly Status[]): Status {
  if (statuses.length === 0) return "inactive";
  return statuses.reduce((worst, next) =>
    statusRank(next) < statusRank(worst) ? next : worst,
  );
}
