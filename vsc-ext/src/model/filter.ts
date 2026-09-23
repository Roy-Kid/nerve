import type { Job, Status } from "./job";
import { jobWorkspace } from "./job";
import { isInside } from "./path";
import { statusOf, statusRank } from "./status";

export type JobFilter = "all" | "attention" | "running" | "folder";

const ATTENTION_STATUSES = new Set<Status>(["problem", "attention"]);
const RUNNING_STATUSES = new Set<Status>(["running", "monitor"]);

export function jobInFolder(job: Job, folders: readonly string[]): boolean {
  const workspace = jobWorkspace(job);
  if (!workspace || folders.length === 0) return false;
  return folders.some((folder) => isInside(workspace, folder));
}

export function matchesFilter(
  job: Job,
  filter: JobFilter,
  folders: readonly string[],
): boolean {
  switch (filter) {
    case "all":
      return true;
    case "attention":
      return ATTENTION_STATUSES.has(statusOf(job));
    case "running":
      return RUNNING_STATUSES.has(statusOf(job));
    case "folder":
      return jobInFolder(job, folders);
  }
}

export function compareJobs(left: Job, right: Job): number {
  const status = statusRank(statusOf(left)) - statusRank(statusOf(right));
  if (status !== 0) return status;
  const updated = (right.updatedAt ?? "").localeCompare(left.updatedAt ?? "");
  if (updated !== 0) return updated;
  return left.id.localeCompare(right.id);
}
