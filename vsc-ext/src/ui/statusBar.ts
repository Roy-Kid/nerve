import * as vscode from "vscode";
import type { Job } from "../model/job";
import { statusOf, statusTitle, worstStatus } from "../model/status";
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
      this.item.show();
      return;
    }
    if (snapshot.jobs.length === 0) {
      this.item.text = "Nerve";
      this.item.tooltip = "No jobs";
      this.item.backgroundColor = undefined;
      this.item.show();
      return;
    }
    const statuses = snapshot.jobs.map(statusOf);
    const worst = worstStatus(statuses);
    const attention = snapshot.jobs.filter((job) => {
      const status = statusOf(job);
      return status === "attention" || status === "problem" || status === "waiting";
    });
    this.item.text =
      attention.length > 0
        ? `Nerve ${attention.length}↑`
        : `Nerve · ${statusTitle(worst).toLowerCase()}`;
    this.item.tooltip = tooltip(snapshot.jobs, worst);
    if (worst === "problem") {
      this.item.backgroundColor = new vscode.ThemeColor(
        "statusBarItem.errorBackground",
      );
    } else if (worst === "attention" || worst === "waiting") {
      this.item.backgroundColor = new vscode.ThemeColor(
        "statusBarItem.warningBackground",
      );
    } else {
      this.item.backgroundColor = undefined;
    }
    this.item.show();
  }
}

function tooltip(jobs: readonly Job[], worst: ReturnType<typeof worstStatus>): string {
  const counts = new Map<string, number>();
  for (const job of jobs) {
    const status = statusOf(job);
    counts.set(status, (counts.get(status) ?? 0) + 1);
  }
  const lines = [`Nerve · ${statusTitle(worst)}`];
  for (const [status, count] of counts) {
    lines.push(`${statusTitle(status as ReturnType<typeof statusOf>)} ${count}`);
  }
  const urgent = jobs
    .slice()
    .sort((left, right) => {
      const delta =
        ["problem", "attention", "waiting", "running", "monitor", "success", "inactive"].indexOf(
          statusOf(left),
        ) -
        ["problem", "attention", "waiting", "running", "monitor", "success", "inactive"].indexOf(
          statusOf(right),
        );
      return delta;
    })[0];
  if (urgent) {
    lines.push("", `${urgent.name} — ${urgent.current?.summary ?? statusTitle(statusOf(urgent))}`);
  }
  return lines.join("\n");
}
