import { statSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

const IS_WINDOWS = process.platform === "win32";

/**
 * The binary to look for. Windows needs the suffix for both `PATH` lookup and
 * `statSync` — without it nothing is ever found.
 */
export const HUB_BINARY = IS_WINDOWS ? "nerve-hub.exe" : "nerve-hub";

/**
 * Install directories to try ahead of `~/.cargo/bin` and ahead of `PATH`.
 *
 * The Windows entries are where an installer would put it, and are provisional
 * until that story is settled; `~/.cargo/bin` and `PATH` are what actually find
 * it until then. Mirrors `nerve_surface_core::locate`.
 */
export function platformFixedDirectories(
  env: NodeJS.ProcessEnv = process.env,
): string[] {
  if (!IS_WINDOWS) return ["/opt/homebrew/bin", "/usr/local/bin"];
  return ["LOCALAPPDATA", "ProgramFiles"]
    .map((key) => env[key])
    .filter((root): root is string => Boolean(root))
    .map((root) => join(root, "Programs", "Nerve"));
}

export interface BinaryProbe {
  isExecutable(path: string): boolean;
  onPath(name: string): string | undefined;
}

export function defaultProbe(): BinaryProbe {
  return {
    isExecutable(path: string): boolean {
      try {
        const stat = statSync(path);
        if (!stat.isFile()) return false;
        // NTFS has no execute bit: `mode` reports 0o666 for every real binary,
        // so asking for one would reject them all. Being a file is the honest
        // answer, and `HUB_BINARY` already carries `.exe`.
        if (IS_WINDOWS) return true;
        return (stat.mode & 0o111) !== 0;
      } catch {
        return false;
      }
    },
    onPath(name: string): string | undefined {
      const pathVar = process.env.PATH;
      if (!pathVar) return undefined;
      // `delimiter` is `;` on Windows and `:` elsewhere.
      for (const directory of pathVar.split(delimiter)) {
        if (!directory) continue;
        const candidate = join(directory, name);
        if (this.isExecutable(candidate)) return candidate;
      }
      return undefined;
    },
  };
}

/**
 * Checkout `target/release` first (dev from this repo), then the platform's
 * install directories, cargo install, PATH. Same spirit as the tmux helper.
 */
export function locateHub(
  probe: BinaryProbe,
  home: string = homedir(),
  extensionPath?: string,
  fixedDirectories: string[] = platformFixedDirectories(),
): string | undefined {
  if (extensionPath) {
    const checkout = join(extensionPath, "..", "target", "release", HUB_BINARY);
    if (probe.isExecutable(checkout)) return checkout;
    const debug = join(extensionPath, "..", "target", "debug", HUB_BINARY);
    if (probe.isExecutable(debug)) return debug;
  }
  for (const directory of fixedDirectories) {
    const candidate = join(directory, HUB_BINARY);
    if (probe.isExecutable(candidate)) return candidate;
  }
  const cargo = join(home, ".cargo", "bin", HUB_BINARY);
  if (probe.isExecutable(cargo)) return cargo;
  return probe.onPath(HUB_BINARY);
}
