import * as vscode from "vscode";
import type { JobFilter } from "../model/filter";
import { compareJobs, jobInFolder, matchesFilter } from "../model/filter";
import {
  type Job,
  groupId,
  isGroupJob,
  isMemberJob,
  lastPrompt,
  paintedColor,
} from "../model/job";
import { focusActionTitle } from "../focus/rank";
import { foreignAlias, localAlias } from "../model/machine";
import { statusOf, statusTitle, worstStatus } from "../model/status";
import type { JobStore } from "../store/jobStore";

export type ConnectionKind = "offline" | "empty" | "emptyFolder" | "ready";

export class AliasItem extends vscode.TreeItem {
  constructor(
    readonly alias: string,
    readonly jobs: Job[],
  ) {
    const local = localAlias();
    const label = foreignAlias(alias, local) ? alias : alias || "this machine";
    super(label, vscode.TreeItemCollapsibleState.Expanded);
    this.contextValue = "nerve.alias";
    const worst = worstStatus(jobs.map(statusOf));
    this.iconPath = statusIcon(worst);
    this.description = String(jobs.length);
  }
}

export class JobItem extends vscode.TreeItem {
  constructor(readonly job: Job) {
    super(job.name || job.id, vscode.TreeItemCollapsibleState.None);
    const status = statusOf(job);
    this.iconPath = statusIcon(status);
    this.description = rowDescription(job);
    this.tooltip = rowTooltip(job);
    this.contextValue = "nerve.job";
    this.id = job.id;
    if (isGroupJob(job)) {
      this.collapsibleState = vscode.TreeItemCollapsibleState.Collapsed;
    }
  }
}

function rowDescription(job: Job): string {
  const summary = job.current?.summary ?? job.attention.title ?? statusTitle(statusOf(job));
  const folders = workspaceFolders();
  const here = jobInFolder(job, folders) ? "here · " : "";
  return `${here}${summary}`;
}

function rowTooltip(job: Job): vscode.MarkdownString {
  const bits = [
    job.producer.name ?? job.producer.id,
    job.alias,
    lastPrompt(job),
  ].filter((value): value is string => Boolean(value));
  const markdown = new vscode.MarkdownString();
  markdown.appendMarkdown(`**${job.name || job.id}** · ${statusTitle(statusOf(job))}\n\n`);
  markdown.appendMarkdown(`${focusActionTitle(job, localAlias())}\n\n`);
  if (bits.length > 0) markdown.appendMarkdown(`${bits.join(" · ")}\n\n`);
  const prompt = lastPrompt(job);
  if (prompt) markdown.appendMarkdown(`Prompt: ${prompt}`);
  markdown.isTrusted = false;
  return markdown;
}

function workspaceFolders(): string[] {
  return (vscode.workspace.workspaceFolders ?? []).map((folder) => folder.uri.fsPath);
}

const iconCache = new Map<string, vscode.Uri>();

function statusIcon(status: ReturnType<typeof statusOf>): vscode.Uri {
  const color = paintedColor(status);
  const cached = iconCache.get(color);
  if (cached) return cached;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><circle cx="8" cy="8" r="5" fill="${color}"/></svg>`;
  const uri = vscode.Uri.parse(`data:image/svg+xml;utf8,${encodeURIComponent(svg)}`);
  iconCache.set(color, uri);
  return uri;
}

export class JobsTreeProvider
  implements vscode.TreeDataProvider<vscode.TreeItem>
{
  private readonly emitter = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.emitter.event;
  filter: JobFilter = "all";
  connection: ConnectionKind = "offline";

  constructor(private readonly store: JobStore) {
    store.onChange(() => this.refresh());
  }

  refresh(): void {
    this.emitter.fire();
  }

  getTreeItem(element: vscode.TreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(element?: vscode.TreeItem): vscode.TreeItem[] {
    const snapshot = this.store.snapshot();
    const folders = workspaceFolders();
    const visible = snapshot.jobs
      .filter((job) => matchesFilter(job, this.filter, folders))
      .slice()
      .sort(compareJobs);

    if (!element) {
      this.connection = connectionKind(snapshot.connected, snapshot.jobs.length, visible.length);
      if (visible.length === 0) return [];
      const groups = new Map<string, Job[]>();
      for (const job of visible) {
        if (isMemberJob(job) && groupId(job) && visible.some((item) => item.id === groupId(job))) {
          continue;
        }
        const alias = job.alias || "local";
        const list = groups.get(alias) ?? [];
        list.push(job);
        groups.set(alias, list);
      }
      const local = localAlias();
      const aliases = [...groups.keys()].sort((left, right) => {
        const leftLocal = !foreignAlias(left, local);
        const rightLocal = !foreignAlias(right, local);
        if (leftLocal !== rightLocal) return leftLocal ? -1 : 1;
        return left.localeCompare(right);
      });
      if (aliases.length === 1) {
        return (groups.get(aliases[0]) ?? []).map((job) => new JobItem(job));
      }
      return aliases.map((alias) => new AliasItem(alias, groups.get(alias) ?? []));
    }

    if (element instanceof AliasItem) {
      return element.jobs.map((job) => new JobItem(job));
    }
    if (element instanceof JobItem && isGroupJob(element.job)) {
      const members = snapshot.jobs
        .filter((job) => isMemberJob(job) && groupId(job) === element.job.id)
        .sort(compareJobs);
      return members.map((job) => new JobItem(job));
    }
    return [];
  }
}

function connectionKind(
  connected: boolean,
  total: number,
  visible: number,
): ConnectionKind {
  if (!connected && total === 0) return "offline";
  if (connected && total === 0) return "empty";
  if (visible === 0) return "emptyFolder";
  return "ready";
}
