import fs from "node:fs";
import path from "node:path";

const [, , command, ...args] = process.argv;

function option(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function writeJson(file, value) {
  fs.writeFileSync(file, `${JSON.stringify(value)}\n`, "utf8");
}

function childrenOf(node) {
  return Array.isArray(node?.Children) ? node.Children : [];
}

function indexNamedNodes(model, rootName) {
  const byPath = new Map();
  const duplicates = new Set();
  const visit = (node, currentPath) => {
    if (node?.Name) {
      if (byPath.has(currentPath)) duplicates.add(currentPath);
      byPath.set(currentPath, node);
    }
    for (const child of childrenOf(node)) {
      if (child?.Name) visit(child, `${currentPath}/${child.Name}`);
    }
  };

  const root = childrenOf(model).find((child) => child.Name === "Root");
  if (root) visit(root, `${rootName}/Root`);
  else {
    for (const child of childrenOf(model)) if (child?.Name) visit(child, `${rootName}/${child.Name}`);
  }
  return { byPath, duplicates };
}

function ensureProperties(node) {
  node.Properties ||= {};
  return node.Properties;
}

function effectChild(node, className) {
  return childrenOf(node).find((child) => child.ClassName === className);
}

function setUdim2(props, key, sx, ox, sy, oy) {
  props[key] = { UDim2: [[sx, Math.round(ox)], [sy, Math.round(oy)]] };
}

function applyEntry(node, entry) {
  const props = ensureProperties(node);
  const layout = entry.layout;
  if (layout?.size && layout?.pos && layout?.anchor) {
    const parentWidth = Number(layout.parentWidth) || 1440;
    const parentHeight = Number(layout.parentHeight) || 900;
    const sizeSx = Number(layout.size.sx) || 0;
    const sizeSy = Number(layout.size.sy) || 0;
    const posSx = Number(layout.pos.sx) || 0;
    const posSy = Number(layout.pos.sy) || 0;
    const anchorX = Number(layout.anchor.x) || 0;
    const anchorY = Number(layout.anchor.y) || 0;
    const width = Math.max(1, Number(entry.width));
    const height = Math.max(1, Number(entry.height));
    setUdim2(props, "Size", sizeSx, width - parentWidth * sizeSx, sizeSy, height - parentHeight * sizeSy);
    if (!layout.managedByLayout) {
      setUdim2(props, "Position", posSx, Number(entry.x) + anchorX * width - parentWidth * posSx, posSy, Number(entry.y) + anchorY * height - parentHeight * posSy);
    }
  }

  if (typeof entry.visible === "boolean") props.Visible = entry.visible;
  if (entry.fill?.color && !String(node.ClassName).startsWith("Text")) {
    props.BackgroundColor3 = entry.fill.color.map(Number);
    props.BackgroundTransparency = 1 - Number(entry.fill.opacity ?? 1);
  }
  if (entry.text !== undefined && String(node.ClassName).startsWith("Text")) props.Text = String(entry.text);
  if (Number.isFinite(entry.fontSize) && String(node.ClassName).startsWith("Text")) props.TextSize = Number(entry.fontSize);
  if (entry.textColor && String(node.ClassName).startsWith("Text")) props.TextColor3 = entry.textColor.map(Number);

  if (Number.isFinite(entry.cornerRadius)) {
    const corner = effectChild(node, "UICorner");
    if (corner) ensureProperties(corner).CornerRadius = { UDim: [0, Math.round(entry.cornerRadius)] };
  }
  if (entry.stroke?.color) {
    const stroke = effectChild(node, "UIStroke");
    if (stroke) {
      const strokeProps = ensureProperties(stroke);
      strokeProps.Color = entry.stroke.color.map(Number);
      if (Number.isFinite(entry.stroke.thickness)) strokeProps.Thickness = Number(entry.stroke.thickness);
    }
  }
}

function verifyModel(modelFile) {
  const model = readJson(modelFile);
  const rootName = path.basename(modelFile).replace(/\.model\.json$/i, "").replace(/\.json$/i, "");
  const { byPath, duplicates } = indexNamedNodes(model, rootName);
  if (!byPath.size) fail(`No named UI objects found in ${modelFile}`);
  if (duplicates.size) fail(`Duplicate bridge paths: ${[...duplicates].join(", ")}`);
  console.log(`Verified ${byPath.size} named UI objects in ${modelFile}`);
}

if (command === "verify") {
  const modelFile = option("--model");
  if (!modelFile) fail("Usage: node scripts/figma-ui-bridge.mjs verify --model <TemplateUI.model.json>");
  verifyModel(modelFile);
} else if (command === "self-test") {
  const modelFile = option("--model");
  if (!modelFile) fail("Usage: node scripts/figma-ui-bridge.mjs self-test --model <TemplateUI.model.json>");
  const model = readJson(modelFile);
  const rootName = path.basename(modelFile).replace(/\.model\.json$/i, "").replace(/\.json$/i, "");
  const { byPath } = indexNamedNodes(model, rootName);
  const targetPath = `${rootName}/Root/CurrencyTray`;
  const target = byPath.get(targetPath);
  if (!target) fail(`Self-test target missing: ${targetPath}`);
  applyEntry(target, {
    path: targetPath,
    className: target.ClassName,
    visible: false,
    fill: { color: [0.1, 0.2, 0.3], opacity: 0.75 }
  });
  if (target.Properties.Visible !== false) fail("Figma bridge self-test did not apply visibility.");
  if (target.Properties.BackgroundTransparency !== 0.25) fail("Figma bridge self-test did not apply opacity.");
  console.log(`Figma bridge self-test passed for ${modelFile}`);
} else if (command === "apply") {
  const modelFile = option("--model");
  const patchFile = option("--patch");
  const outFile = option("--out") || modelFile;
  if (!modelFile || !patchFile) fail("Usage: node scripts/figma-ui-bridge.mjs apply --model <model> --patch <patch> [--out <model>]");

  const model = readJson(modelFile);
  const patch = readJson(patchFile);
  if (patch.format !== "roblox-ui-bridge-v1" || !Array.isArray(patch.entries)) fail("Unsupported or invalid Figma patch.");
  const rootName = path.basename(modelFile).replace(/\.model\.json$/i, "").replace(/\.json$/i, "");
  const { byPath, duplicates } = indexNamedNodes(model, rootName);
  if (duplicates.size) fail(`Model contains duplicate bridge paths: ${[...duplicates].join(", ")}`);

  let applied = 0;
  const missing = [];
  for (const entry of patch.entries) {
    if (!entry?.path?.startsWith(`${rootName}/`)) continue;
    const node = byPath.get(entry.path);
    if (!node) {
      missing.push(entry.path);
      continue;
    }
    if (entry.className && entry.className !== node.ClassName) fail(`Class mismatch at ${entry.path}: patch ${entry.className}, model ${node.ClassName}`);
    applyEntry(node, entry);
    applied += 1;
  }
  if (!applied) fail(`Patch contained no entries for ${rootName}.`);
  if (missing.length) fail(`Patch refers to missing model paths:\n${missing.join("\n")}`);
  writeJson(outFile, model);
  console.log(`Applied ${applied} Figma visual edits to ${outFile}`);
} else {
  fail("Commands: verify, apply");
}
