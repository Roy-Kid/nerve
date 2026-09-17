import {
  type Job,
  jobPid,
  jobWorkspace,
  pathFromOpenUrl,
} from "../model/job";
import { foreignAlias } from "../model/machine";
import { isAbsolutePath, isInside } from "../model/path";
import { bestHost, type SshHost } from "./ssh";

export interface TerminalHint {
  processId?: number;
}

export interface FocusContext {
  localAlias?: string;
  workspaceFolders: readonly string[];
  terminals: readonly TerminalHint[];
  /** `vscode.env.remoteName`, e.g. `ssh-remote` / `wsl`. */
  remoteName?: string;
  /** Authority for a vscode-remote window (`ssh-remote+Host`). */
  remoteAuthority?: string;
  sshHosts: readonly SshHost[];
}

export type FocusTarget =
  | { kind: "terminal"; processId: number }
  | { kind: "here" }
  | { kind: "folder"; path: string }
  | { kind: "remote"; host: string; cwd?: string; alias: string }
  | { kind: "copy"; text: string; reason: string };

function inFolders(path: string, folders: readonly string[]): boolean {
  return folders.some((folder) => isInside(path, folder));
}

function breadcrumb(job: Job, fallback: string): FocusTarget {
  const hint = job.location?.focusHint?.trim();
  const url = job.location?.openURL?.trim();
  const text = hint || url || "";
  return {
    kind: "copy",
    text: text.length > 0 ? text : fallback,
    reason: fallback,
  };
}

function remoteWindowMatches(
  alias: string,
  ctx: FocusContext,
): boolean {
  if (!ctx.remoteName || !ctx.remoteAuthority) return false;
  const authority = ctx.remoteAuthority;
  const host = authority.includes("+")
    ? authority.slice(authority.indexOf("+") + 1)
    : authority;
  if (host.length === 0) return false;
  return (
    host.toLowerCase() === alias.toLowerCase() ||
    bestHost(alias, [{ alias: host, hostName: host }]) !== undefined ||
    bestHost(alias, ctx.sshHosts)?.toLowerCase() === host.toLowerCase()
  );
}

function rankLocal(job: Job, ctx: FocusContext): FocusTarget {
  const pid = jobPid(job);
  if (pid !== undefined) {
    const terminal = ctx.terminals.find((item) => item.processId === pid);
    if (terminal) return { kind: "terminal", processId: pid };
  }

  const workspace = jobWorkspace(job);
  if (workspace && inFolders(workspace, ctx.workspaceFolders)) {
    return { kind: "here" };
  }

  const path = pathFromOpenUrl(job.location?.openURL) ?? workspace;
  if (path && isAbsolutePath(path)) {
    return { kind: "folder", path };
  }

  return breadcrumb(job, "return to the agent UI");
}

export function rankFocus(job: Job, ctx: FocusContext): FocusTarget {
  const foreign = foreignAlias(job.alias, ctx.localAlias);
  if (!foreign) return rankLocal(job, ctx);

  if (remoteWindowMatches(foreign, ctx)) {
    return rankLocal(job, ctx);
  }

  const host = bestHost(foreign, ctx.sshHosts);
  if (host) {
    return {
      kind: "remote",
      host,
      cwd: jobWorkspace(job),
      alias: foreign,
    };
  }
  return breadcrumb(job, `${foreign} — no ssh host in ~/.ssh/config`);
}

export function focusActionTitle(job: Job, local?: string): string {
  const foreign = foreignAlias(job.alias, local);
  if (foreign) return `Open on ${foreign}`;
  if (job.location?.openURL) return "Open";
  return "Focus";
}
