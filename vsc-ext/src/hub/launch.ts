/** Bring a hub up, at most once per throttle window. Fail-open. */

export const SPAWN_THROTTLE_MS = 10_000;

export type Launch =
  | "alreadyServing"
  | "spawned"
  | "throttled"
  | "missing"
  | "failed"
  | "disabled";

export interface HealthProbe {
  isServing(): boolean | Promise<boolean>;
}

export interface ProcessSpawner {
  spawn(program: string, args: readonly string[]): void;
}

export interface Clock {
  now(): number;
}

export class HubLauncher {
  private lastAttempt: number | undefined;

  constructor(
    private readonly spawner: ProcessSpawner,
    private readonly clock: Clock,
    private readonly health: HealthProbe,
  ) {}

  async ensure(
    hub: string | undefined,
    spawnEnabled: boolean,
  ): Promise<Launch> {
    if (await this.health.isServing()) return "alreadyServing";
    if (!spawnEnabled) return "disabled";
    if (!hub) return "missing";

    const now = this.clock.now();
    if (
      this.lastAttempt !== undefined &&
      now - this.lastAttempt < SPAWN_THROTTLE_MS
    ) {
      return "throttled";
    }
    this.lastAttempt = now;
    try {
      this.spawner.spawn(hub, ["serve"]);
      return "spawned";
    } catch {
      return "failed";
    }
  }
}

export function isOffline(launch: Launch): boolean {
  return launch !== "alreadyServing" && launch !== "spawned";
}
