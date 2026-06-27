import type { JobStore, NotificationJob } from "./types.ts";

export class InMemoryJobStore implements JobStore {
  readonly jobs = new Map<string, NotificationJob>();

  async upsert(job: NotificationJob): Promise<void> {
    this.jobs.set(job.id, structuredClone(job));
  }

  async cancelUser(userId: number): Promise<void> {
    for (const [id, job] of this.jobs) {
      if (job.userId === userId) this.jobs.delete(id);
    }
  }

  async due(now: number, limit: number): Promise<NotificationJob[]> {
    return [...this.jobs.values()]
      .filter((job) => job.dueAt <= now)
      .sort((a, b) => a.dueAt - b.dueAt)
      .slice(0, limit)
      .map((job) => structuredClone(job));
  }

  async remove(id: string): Promise<void> {
    this.jobs.delete(id);
  }
}
