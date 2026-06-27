import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { InMemoryJobStore } from "./job-store.ts";
import { RobloxNotifier } from "./roblox-notifier.ts";
import { Scheduler, validateRequest } from "./scheduler.ts";

const port = Number(process.env.PORT || 8787);
const sharedSecret = process.env.WORKER_SHARED_SECRET || "";
const store = new InMemoryJobStore();
const scheduler = new Scheduler(
  store,
  new RobloxNotifier(process.env.ROBLOX_OPEN_CLOUD_API_KEY || "", process.env.ROBLOX_UNIVERSE_ID || ""),
);

function json(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

async function body(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16_384) throw new Error("Body too large");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

function authorized(request: IncomingMessage): boolean {
  return sharedSecret.length >= 16 && request.headers.authorization === `Bearer ${sharedSecret}`;
}

const server = createServer(async (request, response) => {
  try {
    if (request.method === "GET" && request.url === "/health") return json(response, 200, { ok: true, durableStore: false });
    if (!authorized(request)) return json(response, 401, { ok: false, error: "Unauthorized" });
    if (request.method === "POST" && request.url === "/v1/jobs") {
      const job = await scheduler.schedule(validateRequest(await body(request)));
      return json(response, 202, { ok: true, id: job.id });
    }
    if (request.method === "POST" && request.url === "/v1/cancel") {
      const input = (await body(request)) as { userId?: unknown };
      await scheduler.cancelUser(Number(input.userId));
      return json(response, 200, { ok: true });
    }
    return json(response, 404, { ok: false, error: "Not found" });
  } catch (error) {
    return json(response, 400, { ok: false, error: error instanceof Error ? error.message : "Bad request" });
  }
});

setInterval(() => scheduler.tick().catch(console.error), 30_000).unref();
server.listen(port, () => console.log(`Notification worker listening on ${port}; in-memory storage is development-only.`));
