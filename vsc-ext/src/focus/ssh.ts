/**
 * `Host` → `HostName` from the user's `~/.ssh/config`, and the same
 * exact > first-label > shared-prefix ranking macOS / tmux use.
 *
 * Patterns, negations and Include are skipped rather than half-implemented.
 */

const MIN_PREFIX = 3;

export interface SshHost {
  alias: string;
  hostName: string;
}

export function parseSshConfig(text: string): SshHost[] {
  const hosts: SshHost[] = [];
  let pending: string[] = [];
  let hostName: string | undefined;

  const flush = (): void => {
    if (pending.length === 0) return;
    const name = hostName ?? pending[0] ?? "";
    for (const alias of pending) {
      if (alias.includes("*") || alias.includes("?") || alias.startsWith("!")) {
        continue;
      }
      hosts.push({ alias, hostName: name });
    }
    pending = [];
    hostName = undefined;
  };

  for (const raw of text.split(/\r?\n/)) {
    const line = raw.replace(/#.*$/, "").trim();
    if (line.length === 0) continue;
    const tokens = line.split(/\s+/);
    const key = tokens[0]?.toLowerCase();
    if (key === "host") {
      flush();
      pending = tokens.slice(1);
    } else if (key === "hostname" && tokens[1]) {
      hostName = tokens[1];
    }
  }
  flush();
  return hosts;
}

export function scoreHost(host: string, alias: string): number | undefined {
  const left = host.trim();
  const right = alias.trim();
  if (left.length === 0 || right.length === 0) return undefined;
  if (left.toLowerCase() === right.toLowerCase()) return 3;
  const label = left.split(".")[0] ?? "";
  if (label.toLowerCase() === right.toLowerCase()) return 2;
  return sharesPrefix(label, right) ? 1 : undefined;
}

function sharesPrefix(left: string, right: string): boolean {
  const overlap = Math.min(left.length, right.length);
  if (overlap < MIN_PREFIX) return false;
  return (
    left.slice(0, overlap).toLowerCase() === right.slice(0, overlap).toLowerCase()
  );
}

export function bestHost(
  alias: string,
  hosts: readonly SshHost[],
): string | undefined {
  let best: { score: number; host: string } | undefined;
  for (const host of hosts) {
    const scores = [
      scoreHost(host.alias, alias),
      scoreHost(host.hostName, alias),
    ].filter((value): value is number => value !== undefined);
    if (scores.length === 0) continue;
    const score = Math.max(...scores);
    if (!best || score > best.score) best = { score, host: host.alias };
  }
  return best?.host;
}
