import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createServer } from "node:http";
import { readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import process from "node:process";

const SESSION_FORMAT = "figma-ui-bridge-session-v1";
const PATCH_FORMAT = "roblox-ui-bridge-v1";

function parseJson(text) {
  return JSON.parse(text.replace(/^\uFEFF/, ""));
}

function parseArguments(argv) {
  const sessionIndex = argv.indexOf("--session");
  if (sessionIndex < 0 || !argv[sessionIndex + 1]) {
    throw new Error("Usage: node scripts/figma-studio-bridge-server.mjs --session <session.json>");
  }
  return { session: path.resolve(argv[sessionIndex + 1]) };
}

export async function findNewestPatch(downloadsPath) {
  const candidates = [];
  for (const name of await readdir(downloadsPath)) {
    if (!/\.figma-patch(?:\.json)?$/i.test(name)) continue;
    const filePath = path.join(downloadsPath, name);
    const details = await stat(filePath);
    if (details.isFile()) candidates.push({ filePath, modified: details.mtimeMs });
  }
  candidates.sort((left, right) => right.modified - left.modified);
  return candidates[0]?.filePath || null;
}

export function validatePatch(patch, workspace) {
  if (!patch || patch.format !== PATCH_FORMAT || patch.mode !== "authoritative") {
    throw new Error("The newest Figma file is not an authoritative Roblox UI Bridge export.");
  }
  if (patch.workspace !== workspace.id) {
    throw new Error(`The newest export targets '${patch.workspace || "no workspace"}', not '${workspace.id}'.`);
  }
  const actualRoots = [...new Set(Array.isArray(patch.roots) ? patch.roots.map(String) : [])];
  const expectedRoots = [...new Set((workspace.models || []).map((model) => String(model.root)))];
  const missing = expectedRoots.filter((root) => !actualRoots.includes(root));
  const unexpected = actualRoots.filter((root) => !expectedRoots.includes(root));
  if (missing.length || unexpected.length) {
    const details = [
      missing.length ? `missing ${missing.join(", ")}` : "",
      unexpected.length ? `unexpected ${unexpected.join(", ")}` : "",
    ].filter(Boolean).join("; ");
    throw new Error(`The newest Figma export is incomplete: ${details}.`);
  }
}

export function tailOutput(output, maximumLines = 12) {
  return String(output || "").trim().split(/\r?\n/).slice(-maximumLines).join("\n");
}

function sendJson(response, statusCode, body) {
  const text = JSON.stringify(body);
  response.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(text),
    "Cache-Control": "no-store",
  });
  response.end(text);
}

async function loadJson(filePath) {
  return parseJson(await readFile(filePath, "utf8"));
}

export async function startServer(sessionPath) {
  const session = await loadJson(sessionPath);
  if (session.format !== SESSION_FORMAT) throw new Error("Unsupported Figma UI bridge session.");
  if (!["127.0.0.1", "localhost"].includes(session.host)) {
    throw new Error("The Figma UI bridge must bind only to localhost.");
  }
  if (!Number.isInteger(session.port) || session.port <= 1024 || session.port > 65535) {
    throw new Error("Invalid Figma UI bridge port.");
  }
  if (!/^[a-f0-9]{32}$/i.test(session.token || "")) {
    throw new Error("Invalid Figma UI bridge session token.");
  }

  const repository = path.resolve(session.repository);
  const workspacePath = path.join(repository, "figma", "workspaces", `${session.workspace}.json`);
  const applyScript = path.join(repository, "scripts", "figma-ui.ps1");
  const deliveryPath = path.join(repository, "figma", "deliveries", `${session.workspace}.json`);
  const pidPath = path.join(repository, "build", "figma-ui-bridge-server.pid");
  const workspace = await loadJson(workspacePath);
  let applying = false;
  let activeChild = null;
  let activeJob = null;

  function startApplyJob(patchPath, patch) {
    const job = {
      id: randomUUID(),
      state: "running",
      patchName: path.basename(patchPath),
      startedAt: new Date().toISOString(),
    };
    activeJob = job;
    applying = true;

    const child = spawn("powershell.exe", [
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      applyScript,
      "-PatchPath",
      patchPath,
      "-Workspace",
      session.workspace,
    ], {
      cwd: repository,
      windowsHide: true,
      timeout: 120_000,
    });
    activeChild = child;
    let stdout = "";
    let stderr = "";
    const append = (current, chunk) => `${current}${chunk}`.slice(-(16 * 1024 * 1024));
    child.stdout.on("data", (chunk) => {
      stdout = append(stdout, chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr = append(stderr, chunk);
    });
    child.once("error", (error) => {
      activeChild = null;
      applying = false;
      job.state = "failed";
      job.error = error.message;
      job.details = tailOutput(`${stdout}\n${stderr}`);
      job.finishedAt = new Date().toISOString();
    });
    child.once("close", async (code, signal) => {
      activeChild = null;
      applying = false;
      if (job.state === "failed") return;
      if (code !== 0) {
        job.state = "failed";
        job.error = signal
          ? `Repository import was stopped by ${signal}.`
          : `Repository import failed with exit code ${code}.`;
        job.details = tailOutput(`${stdout}\n${stderr}`);
        job.finishedAt = new Date().toISOString();
        return;
      }
      try {
        const delivery = await loadJson(deliveryPath);
        job.state = "succeeded";
        job.result = {
          patchName: path.basename(patchPath),
          exportedAt: delivery.source?.exportedAt || patch.exportedAt || "not recorded",
          checksum: delivery.source?.checksum || "",
          modelChecksum: delivery.modelChecksum,
          rootCount: delivery.rootCount,
          entryCount: delivery.entryCount,
          details: tailOutput(stdout),
        };
      } catch (error) {
        job.state = "failed";
        job.error = error instanceof Error ? error.message : String(error);
        job.details = tailOutput(`${stdout}\n${stderr}`);
      }
      job.finishedAt = new Date().toISOString();
    });
    return job;
  }

  const server = createServer(async (request, response) => {
    try {
      if (request.headers["x-figma-ui-token"] !== session.token) {
        sendJson(response, 401, { ok: false, error: "Unauthorized local bridge request." });
        return;
      }
      if (request.method === "GET" && request.url === "/health") {
        const latestPatch = await findNewestPatch(session.downloads);
        sendJson(response, 200, {
          ok: true,
          workspace: workspace.name,
          latestPatch: latestPatch ? path.basename(latestPatch) : null,
          applying,
        });
        return;
      }
      if (request.method === "GET" && request.url === "/manifest") {
        const manifest = await loadJson(session.manifest);
        sendJson(response, 200, { ok: true, manifest });
        return;
      }
      if (request.method === "GET" && request.url === "/status") {
        if (!activeJob) {
          sendJson(response, 404, { ok: false, error: "No Figma import has been started." });
          return;
        }
        sendJson(response, 200, { ok: true, job: activeJob });
        return;
      }
      if (request.method === "POST" && request.url === "/apply") {
        if (applying) {
          sendJson(response, 409, { ok: false, error: "A Figma import is already running." });
          return;
        }
        const patchPath = await findNewestPatch(session.downloads);
        if (!patchPath) {
          sendJson(response, 404, {
            ok: false,
            error: "No *.figma-patch or *.figma-patch.json export exists in Downloads.",
          });
          return;
        }
        const patch = await loadJson(patchPath);
        validatePatch(patch, workspace);
        const job = startApplyJob(patchPath, patch);
        sendJson(response, 202, {
          ok: true,
          job: {
            id: job.id,
            state: job.state,
            patchName: job.patchName,
          },
        });
        return;
      }
      sendJson(response, 404, { ok: false, error: "Unknown local bridge route." });
    } catch (error) {
      sendJson(response, 500, {
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(session.port, session.host, resolve);
  });
  await writeFile(pidPath, `${process.pid}\n`, "utf8");
  console.log(`Figma UI Studio bridge ready at http://${session.host}:${session.port}`);

  const close = async () => {
    if (activeChild && activeChild.exitCode === null) {
      activeChild.kill();
    }
    await new Promise((resolve) => server.close(resolve));
    await rm(pidPath, { force: true });
  };
  process.once("SIGINT", async () => {
    await close();
    process.exit(0);
  });
  process.once("SIGTERM", async () => {
    await close();
    process.exit(0);
  });
  return { server, close };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const options = parseArguments(process.argv.slice(2));
  await startServer(options.session);
}
