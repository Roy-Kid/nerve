import * as vscode from "vscode";
import type { Job } from "../model/job";
import {
  isAskElevated,
  statusOf,
  statusTitle,
  worstStatus,
} from "../model/status";
import type { JobStore } from "../store/jobStore";

export class NerveStatusBar {
  private readonly item: vscode.StatusBarItem;

  constructor(
    private readonly store: JobStore,
    private readonly enabled: () => boolean,
  ) {
    this.item = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Right,
      10,
    );
    this.item.command = "nerve.showJobs";
    this.item.name = "Nerve";
    store.onChange(() => this.render());
    this.render();
  }

  dispose(): void {
    this.item.dispose();
  }

  render(): void {
    if (!this.enabled()) {
      this.item.hide();
      return;
    }
    const snapshot = this.store.snapshot();
    if (!snapshot.connected) {
      this.item.text = "Nerve · offline";
      this.item.tooltip = "nerve-hub is not reachable on 127.0.0.1:17890";
      this.item.backgroundColor = undefined;
      this.item.accessibilityInformation = {
        label: "Nerve offline",
        role: "button",
      };
      this.item.show();
      return;
    }
    if (snapshot.jobs.length === 0) {
      this.item.text = "Nerve";
      this.item.tooltip = "No jobs";
      this.item.backgroundColor = undefined;
      this.item.accessibilityInformation = {
        label: "Nerve, no jobs",
        role: "button",
      };
      this.item.show();
      return;
    }

    const asks = snapshot.jobs.filter(isAskElevated);
    const problems = snapshot.jobs.filter((job) => statusOf(job) === "problem");
    const statuses = snapshot.jobs.map(statusOf);
    const worst = worstStatus(statuses);
    const hardAsk = asks.some(
      (job) =>
        job.attention.level === "required" || job.attention.level === "urgent",
    );

    if (asks.length > 0) {
      this.item.text =
        asks.length === 1 ? "Nerve · your turn" : `Nerve · ${asks.length} waiting`;
    } else {
      this.item.text = `Nerve · ${statusTitle(worst).toLowerCase()}`;
    }

    this.item.tooltip = tooltip(snapshot.jobs, worst, asks.length);
    this.item.accessibilityInformation = {
      label:
        asks.length > 0
          ? `Nerve, ${asks.length} ready for you`
          : `Nerve, ${statusTitle(worst)}`,
      role: "button",
    };

    // Soft chrome: yellow only for hard Ask or real problems — not every suggested turn.
    if (problems.length > 0) {
      this.item.backgroundColor = new vscode.ThemeColor(
        "statusBarItem.errorBackground",
      );
    } else if (hardAsk) {
      this.item.backgroundColor = new vscode.ThemeColor(
        "statusBarItem.warningBackground",
      );
    } else {
      this.item.backgroundColor = undefined;
    }
    this.item.show();
  }
}

function tooltip(
  jobs: readonly Job[],
  worst: ReturnType<typeof worstStatus>,
  askCount: number,
): string {
  const counts = new Map<string, number>();
  for (const job of jobs) {
    const status = statusOf(job);
    counts.set(status, (counts.get(status) ?? 0) + 1);
  }
  const lines =
    askCount > 0
      ? [`Nerve · ${askCount} ready for you`]
      : [`Nerve · ${statusTitle(worst)}`];
  for (const [status, count] of counts) {
    lines.push(`${statusTitle(status as ReturnType<typeof statusOf>)} ${count}`);
  }
  const lead =
    jobs.find(isAskElevated) ??
    jobs.slice().sort((left, right) => {
      const delta =
        [
          "problem",
          "attention",
          "waiting",
          "running",
          "monitor",
          "success",
          "inactive",
        ].indexOf(statusOf(left)) -
        [
          "problem",
          "attention",
          "waiting",
          "running",
          "monitor",
          "success",
          "inactive",
        ].indexOf(statusOf(right));
      return delta;
    })[0];
  if (lead) {
    lines.push("", `${lead.name} — ${lead.current?.summary ?? statusTitle(statusOf(lead))}`);
  }
  return lines.join("\n");
}
