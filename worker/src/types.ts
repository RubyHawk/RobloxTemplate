export type NotificationKind = "daily" | "offline";

export interface NotificationJob {
  id: string;
  userId: number;
  kind: NotificationKind;
  dueAt: number;
  messageId: string;
  launchData?: string;
  attempts: number;
}

export interface NotificationRequest {
  userId: number;
  kind: NotificationKind;
  dueAt: number;
  messageId: string;
  launchData?: string;
}

export interface JobStore {
  upsert(job: NotificationJob): Promise<void>;
  cancelUser(userId: number): Promise<void>;
  due(now: number, limit: number): Promise<NotificationJob[]>;
  remove(id: string): Promise<void>;
}

export interface Notifier {
  send(job: NotificationJob): Promise<boolean>;
}
