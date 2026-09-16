/**
 * Gentle Ask toasts for the VS Code surface.
 * OS banners stay on macOS; this is in-editor reachability only.
 */

import * as vscode from "vscode";
import type { Job } from "../model/job";
import { askCopy, shouldNotifyAsk } from "../model/status";
import { performFocus } from "../ui/focus";

const DEDUPE_MS = 120_000;

export class AskToast {
  private readonly lastFire = new Map<string, number>();
  private previous = new Map<string, Job>();

  /** Diff the latest snapshot against the previous one; toast on Ask upgrades. */
  evaluate(jobs: readonly Job[]): void {
    const askOn = vscode.workspace
      .getConfiguration("nerve")
      .get("notifications.ask", true);
    if (!askOn) {
      this.previous = new Map(jobs.map((job) => [job.id, job]));
      return;
    }

    const now = Date.now();
    for (const next of jobs) {
      const prev = this.previous.get(next.id);
      if (!shouldNotifyAsk(prev, next)) continue;

      const level = next.attention.level;
      const kind =
        level === "urgent"
          ? "attention.urgent"
          : level === "required"
            ? "attention.required"
            : "attention.suggested";
      const key = `${next.id}|${kind}`;
      const last = this.lastFire.get(key);
      if (last !== undefined && now - last < DEDUPE_MS) continue;
      this.lastFire.set(key, now);

      const copy = askCopy(next, level === "urgent");
      void this.present(next, copy.title, copy.body, level);
    }

    this.previous = new Map(jobs.map((job) => [job.id, job]));
  }

  private async present(
    job: Job,
    title: string,
    body: string,
    level: string,
  ): Promise<void> {
    const open = "Open";
    const message = body ? `${title} — ${body}` : title;
    const pick =
      level === "required" || level === "urgent"
        ? await vscode.window.showWarningMessage(message, open)
        : await vscode.window.showInformationMessage(message, open);
    if (pick !== open) return;
    const note = await performFocus(job);
    vscode.window.setStatusBarMessage(`Nerve: ${note}`, 2500);
  }
}
