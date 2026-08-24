import { existsSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

export const HUB_BINARY = "nerve-hub";

const FIXED_DIRECTORIES = ["/opt/homebrew/bin", "/usr/local/bin"] as const;

export interface BinaryProbe {
  isExecutable(path: string): boolean;
  onPath(name: string): string | undefined;
}

export function defaultProbe(): BinaryProbe {
  return {
    isExecutable(path: string): boolean {
      try {
        const stat = statSync(path);
        return stat.isFile() && (stat.mode & 0o111) !== 0;
      } catch {
        return false;
      }
    },
    onPath(name: string): string | undefined {
      const pathVar = process.env.PATH;
      if (!pathVar) return undefined;
      for (const directory of pathVar.split(delimiter)) {
        const candidate = join(directory, name);
        if (this.isExecutable(candidate) || existsSync(candidate)) {
          return candidate;
        }
      }
      return undefined;
    },
  };
}

/**
 * Checkout `target/release` first (dev from this repo), then Homebrew,
 * cargo install, PATH. Same spirit as the tmux helper.
 */
export function locateHub(
  probe: BinaryProbe,
  home: string = homedir(),
  extensionPath?: string,
): string | undefined {
  if (extensionPath) {
    const checkout = join(extensionPath, "..", "target", "release", HUB_BINARY);
    if (probe.isExecutable(checkout)) return checkout;
    const debug = join(extensionPath, "..", "target", "debug", HUB_BINARY);
    if (probe.isExecutable(debug)) return debug;
  }
  for (const directory of FIXED_DIRECTORIES) {
    const candidate = join(directory, HUB_BINARY);
    if (probe.isExecutable(candidate)) return candidate;
  }
  const cargo = join(home, ".cargo", "bin", HUB_BINARY);
  if (probe.isExecutable(cargo)) return cargo;
  return probe.onPath(HUB_BINARY);
}
