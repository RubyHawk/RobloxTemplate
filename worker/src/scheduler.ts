import type { JobStore, NotificationJob, NotificationRequest, Notifier } from "./types.ts";

const MAX_DELAY_SECONDS = 366 * 24 * 60 * 60;

export function validateRequest(value: unknown, now = Math.floor(Date.now() / 1000)): NotificationRequest {
  if (!value || typeof value !== "object") throw new Error("Body must be an object");
  const input = value as Record<string, unknown>;
  if (!Number.isSafeInteger(input.userId) || Number(input.userId) <= 0) throw new Error("Invalid userId");
  if (input.kind !== "daily" && input.kind !== "offline") throw new Error("Invalid kind");
  if (!Number.isSafeInteger(input.dueAt) || Number(input.dueAt) < now - 60 || Number(input.dueAt) > now + MAX_DELAY_SECONDS) {
    throw new Error("Invalid dueAt");
  }
  if (typeof input.messageId !== "string" || input.messageId.length < 1 || input.messageId.length > 128) {
    throw new Error("Invalid messageId");
  }
  if (input.launchData !== undefined && (typeof input.launchData !== "string" || input.launchData.length > 200)) {
    throw new Error("Invalid launchData");
  }
  return {
    userId: Number(input.userId),
    kind: input.kind,
    dueAt: Number(input.dueAt),
    messageId: input.messageId,
    launchData: input.launchData as string | undefined,
  };
}

export class Scheduler {
  private readonly store: JobStore;
  private readonly notifier: Notifier;
  private readonly deliveredDay = new Map<number, number>();

  constructor(store: JobStore, notifier: Notifier) {
    this.store = store;
    this.notifier = notifier;
  }

  async schedule(request: NotificationRequest): Promise<NotificationJob> {
    const job: NotificationJob = {
      ...request,
      id: `${request.userId}:${request.kind}`,
      attempts: 0,
    };
    await this.store.upsert(job);
    return job;
  }

  async cancelUser(userId: number): Promise<void> {
    if (!Number.isSafeInteger(userId) || userId <= 0) throw new Error("Invalid userId");
    await this.store.cancelUser(userId);
  }

  async tick(now = Math.floor(Date.now() / 1000)): Promise<number> {
    const jobs = await this.store.due(now, 100);
    let delivered = 0;
    for (const job of jobs) {
      const utcDay = Math.floor(now / 86_400);
      if (this.deliveredDay.get(job.userId) === utcDay) {
        job.dueAt = (utcDay + 1) * 86_400 + 9 * 3_600;
        await this.store.upsert(job);
        continue;
      }
      if (await this.notifier.send(job)) {
        this.deliveredDay.set(job.userId, utcDay);
        await this.store.remove(job.id);
        delivered += 1;
      } else {
        job.attempts += 1;
        job.dueAt = now + Math.min(3600, 60 * 2 ** Math.min(job.attempts, 5));
        await this.store.upsert(job);
      }
    }
    return delivered;
  }
}
