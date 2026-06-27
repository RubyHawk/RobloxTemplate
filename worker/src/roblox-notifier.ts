import type { NotificationJob, Notifier } from "./types.ts";

export class RobloxNotifier implements Notifier {
  private readonly apiKey: string;
  private readonly universeId: string;

  constructor(apiKey: string, universeId: string) {
    this.apiKey = apiKey;
    this.universeId = universeId;
  }

  async send(job: NotificationJob): Promise<boolean> {
    if (!this.apiKey || !this.universeId || !job.messageId) return false;
    const response = await fetch(`https://apis.roblox.com/cloud/v2/users/${job.userId}/notifications`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": this.apiKey,
      },
      body: JSON.stringify({
        source: { universe: `universes/${this.universeId}` },
        payload: {
          messageId: job.messageId,
          type: "MOMENT",
          joinExperience: job.launchData ? { launchData: job.launchData } : undefined,
        },
      }),
    });
    return response.ok;
  }
}
