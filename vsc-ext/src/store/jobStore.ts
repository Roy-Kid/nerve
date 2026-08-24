import type { Frame, Job } from "../model/job";

export interface StoreSnapshot {
  jobs: readonly Job[];
  connected: boolean;
}

type Listener = () => void;

/** Frame-fed read-only cache. Writes leave only by replacing the frame. */
export class JobStore {
  private jobs: Job[] = [];
  private connected = false;
  private readonly listeners = new Set<Listener>();

  snapshot(): StoreSnapshot {
    return { jobs: this.jobs, connected: this.connected };
  }

  applyFrame(frame: Frame): void {
    this.jobs = frame.jobs;
    this.connected = true;
    this.emit();
  }

  applyJobs(jobs: Job[]): void {
    this.jobs = jobs;
    this.connected = true;
    this.emit();
  }

  setOffline(): void {
    if (!this.connected && this.jobs.length === 0) return;
    this.connected = false;
    this.emit();
  }

  onChange(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(): void {
    for (const listener of this.listeners) listener();
  }
}
