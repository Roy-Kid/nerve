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

/** Ask reasons — human should return to the agent UI (interruptible channel). */
export const ASK_REASONS = [
  "input",
  "approval",
  "auth",
  "permission",
  "decision",
  "elicitation",
  "review",
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
  if (job.lifecycle === "active" && names(job.current?.type, BUSY_KINDS)) return undefined;
  if (ATTENTION_RANK[job.attention.level] >= ATTENTION_RANK.informational) {
    if (names(job.attention.reason, WAIT_REASONS)) return "waiting";
    if (names(job.attention.reason, ASK_REASONS) || ATTENTION_RANK[job.attention.level] >= ATTENTION_RANK.suggested) return "attention";
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
    return "waiting";
  }
  if (job.health === "degraded") return "problem";
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
  if (names(kind, ["completed"])) return "success";
  if (names(kind, ["waiting"])) return "waiting";
  if (names(kind, IDLE_KINDS)) return "inactive";
  return undefined;
}

export function statusOf(job: Job): Status {
  if (job.outcome === "failure") return "problem";
  if (job.health === "unresponsive") return "problem";

  if (job.lifecycle === "ended") return fromStage(job)!;
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

export function isAskReason(reason: string | undefined): boolean {
  return names(reason, ASK_REASONS);
}

/** Ask + elevated enough to interrupt (`level ≥ suggested`). */
export function isAskElevated(job: Job): boolean {
  return (
    isAskReason(job.attention.reason) &&
    ATTENTION_RANK[job.attention.level] >= ATTENTION_RANK.suggested
  );
}

/** Whether an Ask interrupt should fire for this transition (upgrade or first sight). */
export function shouldNotifyAsk(previous: Job | undefined, next: Job): boolean {
  if (!isAskElevated(next)) return false;
  if (!previous) return true;
  if (!isAskElevated(previous)) return true;
  return ATTENTION_RANK[next.attention.level] > ATTENTION_RANK[previous.attention.level];
}

export interface AskCopy {
  title: string;
  body: string;
}

/** Gentle toast/banner copy. Prefers producer title/summary; never panics. */
export function askCopy(job: Job, forceUrgentTone = false): AskCopy {
  const reason = (job.attention.reason ?? "input").trim().toLowerCase();
  let fallbackTitle: string;
  switch (reason) {
    case "approval":
    case "permission":
    case "auth":
      fallbackTitle = `Approval needed: ${job.name}`;
      break;
    case "review":
      fallbackTitle = `A review is waiting: ${job.name}`;
      break;
    default:
      fallbackTitle = `Your turn: ${job.name}`;
  }
  let fallbackBody: string;
  if (forceUrgentTone || job.attention.level === "urgent") {
    fallbackBody = "Please return when you can — continue in the agent";
  } else {
    switch (reason) {
      case "approval":
      case "permission":
      case "auth":
        fallbackBody = "Return to the agent to approve";
        break;
      case "review":
        fallbackBody = "Return to the agent when you are ready";
        break;
      default:
        fallbackBody = "Ready when you are — return to the agent to continue";
    }
  }
  const title = job.attention.title?.trim();
  const summary = job.attention.summary?.trim();
  const current = job.current?.summary?.trim();
  return {
    title: title || fallbackTitle,
    body: summary || current || fallbackBody,
  };
}
