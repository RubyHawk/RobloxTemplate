import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const FORMAT = "figma-studio-delivery-v1";
const DEFAULT_WORKSPACE = "figma/workspaces/rng-defender.json";
const DEFAULT_DELIVERY = "figma/deliveries/rng-defender.json";
const DEFAULT_OUTPUT = "src/plugins/FigmaUiBridge/Manifest.generated.luau";

const CHECKED_PROPERTIES = new Set([
  "Active",
  "AlwaysOnTop",
  "AnchorPoint",
  "ApplyStrokeMode",
  "AspectRatio",
  "AspectType",
  "AutomaticCanvasSize",
  "BackgroundColor3",
  "BackgroundTransparency",
  "BorderColor3",
  "BorderMode",
  "BorderSizePixel",
  "CanvasSize",
  "CellPadding",
  "CellSize",
  "ClipsDescendants",
  "Color",
  "CornerRadius",
  "DominantAxis",
  "Enabled",
  "Face",
  "FillDirection",
  "FillDirectionMaxCells",
  "FontFace",
  "HorizontalAlignment",
  "ImageColor3",
  "ImageTransparency",
  "LayoutOrder",
  "LightInfluence",
  "LineJoinMode",
  "MaxSize",
  "MinSize",
  "Offset",
  "Padding",
  "PixelsPerStud",
  "Position",
  "ResetOnSpawn",
  "Rotation",
  "SafeAreaCompatibility",
  "Scale",
  "ScaleType",
  "ScreenInsets",
  "ScrollingDirection",
  "ScrollBarThickness",
  "Size",
  "SliceCenter",
  "SliceScale",
  "SortOrder",
  "StartCorner",
  "StudsOffset",
  "StudsOffsetWorldSpace",
  "TextColor3",
  "TextSize",
  "TextStrokeColor3",
  "TextStrokeTransparency",
  "TextTransparency",
  "TextWrapped",
  "TextXAlignment",
  "TextYAlignment",
  "Thickness",
  "Transparency",
  "VerticalAlignment",
  "Visible",
  "ZIndex",
  "ZIndexBehavior",
]);

function parseArguments(argv) {
  const options = {
    workspace: DEFAULT_WORKSPACE,
    delivery: DEFAULT_DELIVERY,
    output: DEFAULT_OUTPUT,
    patch: "",
    check: false,
    manifestOnly: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--check") {
      options.check = true;
      continue;
    }
    if (argument === "--manifest-only") {
      options.manifestOnly = true;
      continue;
    }
    const key = argument.startsWith("--") ? argument.slice(2) : "";
    if (!["workspace", "delivery", "output", "patch"].includes(key)) {
      throw new Error(`Unknown argument: ${argument}`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for ${argument}`);
    }
    options[key] = value;
    index += 1;
  }
  return options;
}

function sha256(text) {
  return createHash("sha256").update(text).digest("hex");
}

function stableJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function normalizedProperties(properties = {}) {
  return Object.fromEntries(
    Object.entries(properties)
      .filter(([key]) => CHECKED_PROPERTIES.has(key))
      .sort(([left], [right]) => left.localeCompare(right)),
  );
}

function childIdentity(child, siblings) {
  const name = child.Name || child.ClassName;
  const matching = siblings.filter((candidate) => (candidate.Name || candidate.ClassName) === name);
  return {
    name,
    className: child.ClassName,
    ordinal: Math.max(1, matching.indexOf(child) + 1),
  };
}

function collectEntries(node, segments = [], displayPath = "") {
  const entries = [{
    path: displayPath,
    segments,
    className: node.ClassName,
    properties: normalizedProperties(node.Properties),
  }];
  const children = Array.isArray(node.Children) ? node.Children : [];
  for (const child of children) {
    const identity = childIdentity(child, children);
    const childPath = displayPath ? `${displayPath}/${identity.name}` : identity.name;
    entries.push(...collectEntries(child, [...segments, identity], childPath));
  }
  return entries;
}

function luaString(value) {
  return JSON.stringify(value)
    .replaceAll("\\u2028", "\\226\\128\\168")
    .replaceAll("\\u2029", "\\226\\128\\169");
}

function luaValue(value, indent = 0) {
  if (value === null || value === undefined) return "nil";
  if (typeof value === "string") return luaString(value);
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  const nextIndent = indent + 1;
  const pad = "\t".repeat(nextIndent);
  const closePad = "\t".repeat(indent);
  if (Array.isArray(value)) {
    if (!value.length) return "{}";
    return `{\n${value.map((entry) => `${pad}${luaValue(entry, nextIndent)},`).join("\n")}\n${closePad}}`;
  }
  const keys = Object.keys(value).sort();
  if (!keys.length) return "{}";
  return `{\n${keys.map((key) => `${pad}[${luaString(key)}] = ${luaValue(value[key], nextIndent)},`).join("\n")}\n${closePad}}`;
}

async function readJson(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

async function build(options) {
  const workspacePath = path.resolve(options.workspace);
  const deliveryPath = path.resolve(options.delivery);
  const outputPath = path.resolve(options.output);
  const workspace = await readJson(workspacePath);
  if (workspace.format !== "roblox-ui-workspace-v1") {
    throw new Error(`Unsupported workspace format in ${options.workspace}`);
  }

  let priorDelivery = null;
  try {
    priorDelivery = await readJson(deliveryPath);
  } catch {
    priorDelivery = null;
  }

  let source = priorDelivery?.source || {
    exportedAt: "repository baseline",
    checksum: "",
    fileName: "",
  };
  if (options.patch) {
    const patchText = await readFile(path.resolve(options.patch), "utf8");
    const patch = JSON.parse(patchText);
    if (patch.format !== "roblox-ui-bridge-v1" || patch.mode !== "authoritative") {
      throw new Error("Studio delivery metadata requires an authoritative Roblox UI Bridge patch.");
    }
    if (patch.workspace && patch.workspace !== workspace.id) {
      throw new Error(`Patch workspace '${patch.workspace}' does not match '${workspace.id}'.`);
    }
    source = {
      exportedAt: patch.exportedAt || "not recorded",
      checksum: sha256(patchText),
      fileName: path.basename(options.patch),
    };
  }

  const roots = [];
  const modelDigests = [];
  for (const definition of workspace.models || []) {
    if (!definition.root || !definition.path || !definition.studioPath) {
      throw new Error(`Workspace model requires root, path, and studioPath: ${JSON.stringify(definition)}`);
    }
    const modelText = await readFile(path.resolve(definition.path), "utf8");
    const model = JSON.parse(modelText);
    modelDigests.push({ root: definition.root, checksum: sha256(stableJson(model)) });
    roots.push({
      name: definition.root,
      studioPath: definition.studioPath,
      scope: definition.scope || "production",
      entries: collectEntries(model),
    });
  }

  const delivery = {
    format: FORMAT,
    workspace: { id: workspace.id, name: workspace.name },
    source,
    modelChecksum: sha256(stableJson(modelDigests)),
    rootCount: roots.length,
    entryCount: roots.reduce((total, root) => total + root.entries.length, 0),
  };
  const manifest = {
    format: FORMAT,
    workspace: delivery.workspace,
    source: delivery.source,
    modelChecksum: delivery.modelChecksum,
    rootCount: delivery.rootCount,
    entryCount: delivery.entryCount,
    roots,
  };
  const lua = `--!strict\n\n-- Generated by scripts/generate-figma-studio-manifest.mjs. Do not edit by hand.\nreturn ${luaValue(manifest)}\n`;
  const deliveryText = `${JSON.stringify(delivery, null, 2)}\n`;

  if (options.manifestOnly) {
    if (!priorDelivery || priorDelivery.format !== FORMAT) {
      throw new Error("Tracked Figma delivery metadata is missing or invalid.");
    }
    if (priorDelivery.modelChecksum !== delivery.modelChecksum) {
      throw new Error("Tracked Figma delivery metadata is stale. Apply a Figma export before building the Studio plugin.");
    }
    await writeFile(outputPath, lua, "utf8");
    return delivery;
  }

  if (options.check) {
    const [currentLua, currentDelivery] = await Promise.all([
      readFile(outputPath, "utf8"),
      readFile(deliveryPath, "utf8"),
    ]);
    if (currentLua !== lua || currentDelivery !== deliveryText) {
      throw new Error("Figma Studio delivery manifest is stale. Run FIGMA_UI.cmd or the manifest generator.");
    }
    return delivery;
  }

  await Promise.all([
    writeFile(outputPath, lua, "utf8"),
    writeFile(deliveryPath, deliveryText, "utf8"),
  ]);
  return delivery;
}

const options = parseArguments(process.argv.slice(2));
const delivery = await build(options);
console.log(
  `${options.check ? "Verified" : "Generated"} Figma Studio manifest: `
  + `${delivery.rootCount} roots, ${delivery.entryCount} instances, ${delivery.modelChecksum.slice(0, 12)}.`,
);
