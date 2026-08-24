/**
 * Which machine this surface is looking at.
 *
 * A foreign pid and a foreign workspace path must never be compared against
 * local terminals or local folders. Same question the hub reaper and the
 * tmux surface ask first.
 *
 * Resolution copies the hub: Bonjour LocalHostName on macOS, else the short
 * hostname. Unlike the hub there is no `local` fallback — a machine that
 * will not name itself treats everything as local (fail-open).
 */

import { execFileSync } from "node:child_process";
import { hostname } from "node:os";

export function sanitizeAlias(raw: string): string {
  return [...raw.trim()]
    .filter((character) => /[0-9A-Za-z._-]/.test(character))
    .join("");
}

export function sameAlias(left: string, right: string): boolean {
  return sanitizeAlias(left).toLowerCase() === sanitizeAlias(right).toLowerCase();
}

export function foreignAlias(
  jobAlias: string,
  local: string | undefined,
): string | undefined {
  const alias = jobAlias.trim();
  if (alias.length === 0) return undefined;
  if (!local) return undefined;
  return sameAlias(alias, local) ? undefined : alias;
}

function firstLine(command: string, args: string[]): string | undefined {
  try {
    const output = execFileSync(command, args, {
      encoding: "utf8",
      timeout: 500,
      stdio: ["ignore", "pipe", "ignore"],
    });
    const line = output.split(/\r?\n/).find((row) => row.trim().length > 0);
    return line?.trim();
  } catch {
    return undefined;
  }
}

function bonjourLocalHostName(): string | undefined {
  if (process.platform !== "darwin") return undefined;
  return firstLine("/usr/sbin/scutil", ["--get", "LocalHostName"]);
}

function shortHostname(): string | undefined {
  const named = firstLine("hostname", []) ?? hostname();
  const short = named.split(".")[0]?.trim();
  return short && short.length > 0 ? short : undefined;
}

let cached: string | undefined;
let resolved = false;

export function localAlias(): string | undefined {
  if (resolved) return cached;
  resolved = true;
  const named = bonjourLocalHostName() ?? shortHostname();
  const sanitised = named ? sanitizeAlias(named) : "";
  cached = sanitised.length > 0 ? sanitised : undefined;
  return cached;
}

/** Test seam: reset the process cache. */
export function resetLocalAliasForTests(): void {
  cached = undefined;
  resolved = false;
}
