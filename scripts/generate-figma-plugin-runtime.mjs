import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const DEFAULT_WORKSPACE = "figma/workspaces/rng-defender.json";
const DEFAULT_OUTPUT = "src/plugins/FigmaUiBridge/Runtime.generated.luau";
const CHECK_TOKEN = "00000000000000000000000000000000";

function option(argv, name, fallback) {
  const index = argv.indexOf(name);
  if (index < 0) return fallback;
  if (!argv[index + 1]) throw new Error(`Missing value for ${name}.`);
  return argv[index + 1];
}

const argv = process.argv.slice(2);
const workspacePath = path.resolve(option(argv, "--workspace", DEFAULT_WORKSPACE));
const outputPath = path.resolve(option(argv, "--output", DEFAULT_OUTPUT));
const token = option(argv, "--token", CHECK_TOKEN);
if (!/^[a-f0-9]{32}$/i.test(token)) throw new Error("Runtime token must be 32 hexadecimal characters.");

const workspace = JSON.parse(await readFile(workspacePath, "utf8"));
const bridge = workspace.studioBridge;
if (!bridge || !["127.0.0.1", "localhost"].includes(bridge.host)) {
  throw new Error("Workspace studioBridge must use localhost.");
}
if (!Number.isInteger(bridge.port) || bridge.port <= 1024 || bridge.port > 65535) {
  throw new Error("Workspace studioBridge port must be between 1025 and 65535.");
}

const source = `--!strict

-- Generated locally by scripts/generate-figma-plugin-runtime.mjs. Do not commit.
return {
\tbaseUrl = ${JSON.stringify(`http://${bridge.host}:${bridge.port}`)},
\ttoken = ${JSON.stringify(token)},
}
`;
await mkdir(path.dirname(outputPath), { recursive: true });
await writeFile(outputPath, source, "utf8");
console.log(`Generated Figma UI plugin runtime for http://${bridge.host}:${bridge.port}.`);
