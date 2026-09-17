import { spawn } from "node:child_process";
import type { ClientRequest } from "node:http";
import { homedir } from "node:os";
import { parseFrame, parseJobsList } from "../model/job";
import type { JobStore } from "../store/jobStore";
import { HEALTH_PATH, JOBS_PATH, STREAM_PATH } from "./endpoint";
import { getStream, getText } from "./http";
import { HubLauncher, type Launch } from "./launch";
import { defaultProbe, locateHub } from "./locate";
import { SseParser } from "./sse";

const HEALTH_TIMEOUT_MS = 1_000;
const JOBS_TIMEOUT_MS = 5_000;
const STREAM_IDLE_MS = 60_000;
const MIN_RETRY_MS = 1_000;
const MAX_RETRY_MS = 30_000;

class HttpHealth {
  async isServing(): Promise<boolean> {
    try {
      await getText(HEALTH_PATH, HEALTH_TIMEOUT_MS);
      return true;
    } catch {
      return false;
    }
  }
}

class DetachedSpawner {
  spawn(program: string, args: readonly string[]): void {
    const child = spawn(program, [...args], {
      detached: true,
      stdio: "ignore",
      // Without this, Windows gives the hub a console window of its own and
      // one flashes on screen every time the extension starts it.
      windowsHide: true,
    });
    child.unref();
  }
}

export interface HubClientOptions {
  extensionPath?: string;
  spawnEnabled: () => boolean;
}

/**
 * One SSE subscription for this extension host. Fail-open: never throws
 * into the editor, never kills a hub.
 */
export class HubClient {
  private request: ClientRequest | undefined;
  private retryTimer: ReturnType<typeof setTimeout> | undefined;
  private idleTimer: ReturnType<typeof setTimeout> | undefined;
  private retryMs = MIN_RETRY_MS;
  private stopped = false;
  private readonly launcher = new HubLauncher(
    new DetachedSpawner(),
    { now: () => Date.now() },
    new HttpHealth(),
  );
  lastLaunch: Launch | undefined;

  constructor(
    private readonly store: JobStore,
    private readonly options: HubClientOptions,
  ) {}

  start(): void {
    this.stopped = false;
    void this.loop();
  }

  stop(): void {
    this.stopped = true;
    if (this.retryTimer) clearTimeout(this.retryTimer);
    if (this.idleTimer) clearTimeout(this.idleTimer);
    this.request?.destroy();
    this.request = undefined;
  }

  reconnect(): void {
    this.stop();
    this.retryMs = MIN_RETRY_MS;
    this.start();
  }

  private async loop(): Promise<void> {
    if (this.stopped) return;
    const hub = locateHub(defaultProbe(), homedir(), this.options.extensionPath);
    this.lastLaunch = await this.launcher.ensure(hub, this.options.spawnEnabled());
    try {
      const body = await getText(JOBS_PATH, JOBS_TIMEOUT_MS);
      this.store.applyJobs(parseJobsList(body));
      this.retryMs = MIN_RETRY_MS;
    } catch {
      this.store.setOffline();
    }
    if (this.stopped) return;
    this.attachStream();
  }

  private attachStream(): void {
    if (this.stopped) return;
    const parser = new SseParser();
    const bumpIdle = (): void => {
      if (this.idleTimer) clearTimeout(this.idleTimer);
      this.idleTimer = setTimeout(() => {
        this.request?.destroy();
      }, STREAM_IDLE_MS);
    };
    bumpIdle();
    this.request = getStream(
      STREAM_PATH,
      (chunk) => {
        bumpIdle();
        for (const payload of parser.push(chunk)) {
          try {
            this.store.applyFrame(parseFrame(payload));
            this.retryMs = MIN_RETRY_MS;
          } catch {
            // Keep the last good frame. A bad payload is not an empty hub.
          }
        }
      },
      () => {
        this.request = undefined;
        if (this.idleTimer) clearTimeout(this.idleTimer);
        this.store.setOffline();
        this.scheduleRetry();
      },
    );
  }

  private scheduleRetry(): void {
    if (this.stopped) return;
    const wait = this.retryMs;
    this.retryMs = Math.min(this.retryMs * 2, MAX_RETRY_MS);
    this.retryTimer = setTimeout(() => {
      void this.loop();
    }, wait);
  }
}
