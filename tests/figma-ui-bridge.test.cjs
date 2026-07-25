"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const bridge = require("../figma/roblox-ui-bridge/code.js");

const repo = path.resolve(__dirname, "..");
const readJson = (relativePath) => JSON.parse(fs.readFileSync(path.join(repo, relativePath), "utf8"));

assert.deepEqual(
  bridge.displayCanvasSize({ ClassName: "ScreenGui", Properties: {} }),
  { width: 1600, height: 900 },
  "ScreenGui uses the 16:9 editable HUD viewport"
);

assert.deepEqual(
  bridge.displayCanvasSize({
    ClassName: "SurfaceGui",
    Properties: { CanvasSize: [1024, 512], SizingMode: "FixedSize" }
  }),
  { width: 1024, height: 512 },
  "SurfaceGui preserves an authored fixed canvas"
);

const nestedWorldModel = {
  ClassName: "Model",
  Children: [{
    Name: "Console",
    ClassName: "Part",
    Properties: { Size: [12, 2, 8] },
    Children: [{
      Name: "Display",
      ClassName: "SurfaceGui",
      Properties: {
        CanvasSize: [800, 600],
        Face: "Top",
        PixelsPerStud: 20,
        SizingMode: "PixelsPerStud"
      },
      Children: [{
        Name: "Panel",
        ClassName: "Frame",
        Properties: { Size: { UDim2: [[1, 0], [1, 0]] } },
        Children: [{
          Name: "Folder",
          ClassName: "Folder",
          Children: [{
            Name: "Title",
            ClassName: "TextLabel",
            Properties: { Size: { UDim2: [[1, 0], [0, 40]] } },
            Children: []
          }]
        }]
      }]
    }]
  }]
};
const surfaceContainers = bridge.collectDisplayContainers(nestedWorldModel, "WorldConsole");
assert.equal(surfaceContainers.length, 1, "nested SurfaceGui is discovered through a non-visual world tree");
assert.equal(surfaceContainers[0].path, "WorldConsole/Console/Display");
assert.deepEqual(surfaceContainers[0].size, { width: 240, height: 160 });
assert.deepEqual(
  bridge.collectVisualPaths(surfaceContainers[0].node, surfaceContainers[0].path),
  [
    "WorldConsole/Console/Display/Panel",
    "WorldConsole/Console/Display/Panel/Folder/Title"
  ],
  "visual descendants remain mapped through named non-visual folders"
);

const ownerModel = readJson("src/ui/StagePlatformOwners.model.json");
const ownerContainers = bridge.collectDisplayContainers(ownerModel, "StagePlatformOwners");
assert.equal(ownerContainers.length, 6, "all six stage owner BillboardGuis become editable artboards");
for (const [index, container] of ownerContainers.entries()) {
  assert.equal(container.node.ClassName, "BillboardGui");
  assert.deepEqual(container.size, { width: 320, height: 88 });
  assert.equal(container.path, `StagePlatformOwners/Slot_0${index + 1}`);
  assert.ok(bridge.collectVisualPaths(container.node, container.path).length > 0);
}

const runeSign = readJson("src/ui/RuneCircleSign.model.json");
assert.deepEqual(
  bridge.collectDisplayContainers(runeSign, "RuneCircleSign")[0].size,
  { width: 492, height: 184 },
  "BillboardGui offset size becomes the Figma artboard size"
);

const workspaceBoard = {
  parent: null,
  getSharedPluginData(_namespace, key) {
    return key === "workspaceId" ? "rng-defender" : "";
  }
};
assert.deepEqual(
  bridge.workspaceIdsForNodes([{ parent: workspaceBoard }]),
  ["rng-defender"],
  "a partial child selection keeps its imported workspace identity"
);
assert.equal(bridge.singleWorkspaceId([{ parent: workspaceBoard }]), "rng-defender");
assert.throws(
  () => bridge.singleWorkspaceId([
    { parent: workspaceBoard },
    {
      getSharedPluginData(_namespace, key) {
        return key === "workspaceId" ? "other-workspace" : "";
      }
    }
  ]),
  /Selection spans multiple workspaces/,
  "mixed-workspace selections are rejected before patch export"
);

const workspace = readJson("figma/workspaces/rng-defender.json");
assert.equal(workspace.models.length, 12, "RNG Defender workspace includes every authored StarterGui root");
for (const definition of workspace.models) {
  const modelPath = path.join(repo, definition.path);
  assert.ok(fs.existsSync(modelPath), `workspace model exists: ${definition.path}`);
  assert.equal(
    path.basename(modelPath).replace(/\.model\.json$/i, ""),
    definition.root,
    `workspace root matches filename: ${definition.root}`
  );
  const model = JSON.parse(fs.readFileSync(modelPath, "utf8"));
  const containers = bridge.collectDisplayContainers(model, definition.root);
  assert.ok(containers.length > 0, `workspace model has a display container: ${definition.root}`);
  assert.ok(
    containers.some((container) => bridge.collectVisualPaths(container.node, container.path).length > 0),
    `workspace model has editable visual descendants: ${definition.root}`
  );
}

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "roblox-figma-bridge-"));
try {
  const bundlePath = path.join(temporary, "rng-defender-workspace.json");
  const bundleResult = spawnSync(process.execPath, [
    "scripts/figma-ui-bridge.mjs",
    "bundle",
    "--workspace",
    "figma/workspaces/rng-defender.json",
    "--out",
    bundlePath
  ], { cwd: repo, encoding: "utf8" });
  assert.equal(bundleResult.status, 0, bundleResult.stderr || bundleResult.stdout);
  const bundle = JSON.parse(fs.readFileSync(bundlePath, "utf8"));
  assert.equal(bundle.format, "roblox-ui-workspace-v1");
  assert.equal(bundle.preset, "incremental");
  assert.equal(bundle.project, "patches/rng-defender-grid-demo.project.json");
  assert.equal(bundle.output, "build/RNGDefenderSafePatch.rbxlx");
  const expandedBundle = bridge.expandImportFiles([{ name: "workspace.json", text: JSON.stringify(bundle) }]);
  assert.equal(expandedBundle.length, 12);
  assert.ok(expandedBundle.every((item) => item.workspaceId === "rng-defender"));

  const duplicateWorkspacePath = path.join(temporary, "duplicate-workspace.json");
  fs.writeFileSync(duplicateWorkspacePath, JSON.stringify({
    ...workspace,
    models: [workspace.models[0], workspace.models[0]]
  }));
  const duplicateResult = spawnSync(process.execPath, [
    "scripts/figma-ui-bridge.mjs",
    "bundle",
    "--workspace",
    duplicateWorkspacePath,
    "--out",
    path.join(temporary, "duplicate-bundle.json")
  ], { cwd: repo, encoding: "utf8" });
  assert.notEqual(duplicateResult.status, 0);
  assert.match(duplicateResult.stderr, /Duplicate workspace root/);

  const traversalWorkspacePath = path.join(temporary, "traversal-workspace.json");
  fs.writeFileSync(traversalWorkspacePath, JSON.stringify({
    ...workspace,
    models: [{
      root: "Outside",
      path: "../outside.model.json",
      scope: "production"
    }]
  }));
  const traversalResult = spawnSync(process.execPath, [
    "scripts/figma-ui-bridge.mjs",
    "bundle",
    "--workspace",
    traversalWorkspacePath,
    "--out",
    path.join(temporary, "traversal-bundle.json")
  ], { cwd: repo, encoding: "utf8" });
  assert.notEqual(traversalResult.status, 0);
  assert.match(traversalResult.stderr, /leaves the repository/);

  const modelPath = path.join(temporary, "SurfaceTest.model.json");
  const patchPath = path.join(temporary, "surface-test.figma-patch.json");
  fs.writeFileSync(modelPath, JSON.stringify({
    ClassName: "SurfaceGui",
    Properties: { CanvasSize: [600, 300] },
    Children: [{
      Name: "Panel",
      ClassName: "Frame",
      Properties: {
        Size: { UDim2: [[1, 0], [1, 0]] },
        Position: { UDim2: [[0, 0], [0, 0]] },
        BackgroundColor3: [1, 1, 1]
      },
      Children: []
    }]
  }));
  fs.writeFileSync(patchPath, JSON.stringify({
    format: "roblox-ui-bridge-v1",
    roots: ["SurfaceTest"],
    entries: [{
      path: "SurfaceTest/Panel",
      className: "Frame",
      visible: true,
      x: 20,
      y: 10,
      width: 560,
      height: 280,
      fill: { color: [0.1, 0.2, 0.3], opacity: 0.75 },
      layout: {
        size: { sx: 1, ox: 0, sy: 1, oy: 0 },
        pos: { sx: 0, ox: 0, sy: 0, oy: 0 },
        anchor: { x: 0, y: 0 },
        parentWidth: 600,
        parentHeight: 300,
        managedByLayout: false
      }
    }]
  }));
  const applyResult = spawnSync(process.execPath, [
    "scripts/figma-ui-bridge.mjs",
    "apply",
    "--model",
    modelPath,
    "--patch",
    patchPath
  ], { cwd: repo, encoding: "utf8" });
  assert.equal(applyResult.status, 0, applyResult.stderr || applyResult.stdout);
  const applied = JSON.parse(fs.readFileSync(modelPath, "utf8"));
  assert.deepEqual(applied.Children[0].Properties.BackgroundColor3, [0.1, 0.2, 0.3]);
  assert.equal(applied.Children[0].Properties.BackgroundTransparency, 0.25);
  assert.deepEqual(applied.Children[0].Properties.Size, { UDim2: [[1, -40], [1, -20]] });
  assert.deepEqual(applied.Children[0].Properties.Position, { UDim2: [[0, 20], [0, 10]] });
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}

const pluginUi = fs.readFileSync(path.join(repo, "figma/roblox-ui-bridge/ui.html"), "utf8");
assert.match(pluginUi, /<button class="file" id="import" type="button">/);
assert.match(pluginUi, /<input id="models"[^>]*tabindex="-1">/);
assert.match(pluginUi, /<div id="status" role="status">/);
assert.doesNotMatch(pluginUi, /input\[type=file\]\s*\{\s*display:\s*none/);

console.log("Figma UI bridge world-space tests passed.");
