import assert from "node:assert/strict";
import test from "node:test";
import { InMemoryJobStore } from "../src/job-store.ts";
import { Scheduler, validateRequest } from "../src/scheduler.ts";
import type { NotificationJob, Notifier } from "../src/types.ts";

class FakeNotifier implements Notifier {
  sent: NotificationJob[] = [];
  succeed = true;

  async send(job: NotificationJob): Promise<boolean> {
    this.sent.push(job);
    return this.succeed;
  }
}

test("upserts one job per user and kind", async () => {
  const store = new InMemoryJobStore();
  const scheduler = new Scheduler(store, new FakeNotifier());
  await scheduler.schedule({ userId: 42, kind: "daily", dueAt: 100, messageId: "a" });
  await scheduler.schedule({ userId: 42, kind: "daily", dueAt: 200, messageId: "b" });
  assert.equal(store.jobs.size, 1);
  assert.equal(store.jobs.get("42:daily")?.messageId, "b");
});

test("delivers due jobs once", async () => {
  const store = new InMemoryJobStore();
  const notifier = new FakeNotifier();
  const scheduler = new Scheduler(store, notifier);
  await scheduler.schedule({ userId: 42, kind: "offline", dueAt: 100, messageId: "message" });
  assert.equal(await scheduler.tick(100), 1);
  assert.equal(await scheduler.tick(100), 0);
  assert.equal(notifier.sent.length, 1);
});

test("backs off failed jobs", async () => {
  const store = new InMemoryJobStore();
  const notifier = new FakeNotifier();
  notifier.succeed = false;
  const scheduler = new Scheduler(store, notifier);
  await scheduler.schedule({ userId: 9, kind: "daily", dueAt: 100, messageId: "message" });
  assert.equal(await scheduler.tick(100), 0);
  assert.equal(store.jobs.get("9:daily")?.attempts, 1);
  assert.ok((store.jobs.get("9:daily")?.dueAt || 0) > 100);
});

test("delivers at most one notification per user per UTC day", async () => {
  const store = new InMemoryJobStore();
  const notifier = new FakeNotifier();
  const scheduler = new Scheduler(store, notifier);
  await scheduler.schedule({ userId: 7, kind: "daily", dueAt: 100, messageId: "daily" });
  await scheduler.schedule({ userId: 7, kind: "offline", dueAt: 100, messageId: "offline" });
  assert.equal(await scheduler.tick(100), 1);
  assert.equal(notifier.sent.length, 1);
  assert.equal(store.jobs.size, 1);
});

test("validates untrusted schedule input", () => {
  assert.throws(() => validateRequest({ userId: -1, kind: "daily", dueAt: 100, messageId: "x" }, 100));
  assert.equal(validateRequest({ userId: 5, kind: "offline", dueAt: 200, messageId: "x" }, 100).userId, 5);
});
