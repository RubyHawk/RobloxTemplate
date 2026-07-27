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
assert.equal(
  workspace.models.length,
  14,
  "RNG Defender workspace includes every StarterGui root plus world-space rune and enemy UI"
);
const rngProject = readJson("patches/rng-defender-grid-demo.project.json");
const workspaceRoots = new Set(workspace.models.map((definition) => definition.root));
const starterGuiRoots = Object.keys(rngProject.tree.StarterGui)
  .filter((name) => !name.startsWith("$"));
for (const rootName of starterGuiRoots) {
  assert.ok(workspaceRoots.has(rootName), `Figma workspace owns StarterGui.${rootName}`);
}
assert.ok(workspaceRoots.has("RuneCircle"), "Figma workspace owns both rune SurfaceGuis");
assert.ok(workspaceRoots.has("EnemyRigs"), "Figma workspace owns every enemy health-bar BillboardGui");
assert.deepEqual(
  [...workspaceRoots].sort(),
  [...new Set([...starterGuiRoots, "RuneCircle", "EnemyRigs"])].sort(),
  "the authoritative workspace has no missing or unrelated RNG Defender UI roots"
);
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
  assert.equal(expandedBundle.length, 14);
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
      Children: [{
        Name: "Label",
        ClassName: "TextLabel",
        Properties: {
          AnchorPoint: [0, 0],
          Position: { UDim2: [[0, 0], [0, 0]] },
          Size: { UDim2: [[0, 120], [0, 32]] },
          Text: "0",
          TextXAlignment: "Left"
        },
        Children: []
      }, {
        Name: "CompactTab",
        ClassName: "Frame",
        Properties: {
          Position: { UDim2: [[0, 18], [0, 12]] },
          Size: { UDim2: [[1, 0], [0, 48]] }
        },
        Children: [{
          ClassName: "UISizeConstraint",
          Properties: {
            MinSize: [200, 60],
            MaxSize: [200, 60]
          }
        }]
      }, {
        Name: "Row",
        ClassName: "Frame",
        Properties: {
          Position: { UDim2: [[0, 20], [0, 80]] },
          Size: { UDim2: [[0, 300], [0, 80]] }
        },
        Children: [{
          ClassName: "UIGridLayout",
          Properties: {
            CellSize: { UDim2: [[0, 40], [0, 40]] },
            CellPadding: { UDim2: [[0, 4], [0, 0]] }
          }
        }, {
          Name: "Primary",
          ClassName: "TextButton",
          Properties: { Size: { UDim2: [[0, 40], [0, 40]] } },
          Children: []
        }, {
          Name: "Secondary",
          ClassName: "TextButton",
          Properties: { Size: { UDim2: [[0, 40], [0, 40]] } },
          Children: []
        }]
      }, {
        Name: "Freeform",
        ClassName: "Frame",
        Properties: {
          Position: { UDim2: [[0, 340], [0, 80]] },
          Size: { UDim2: [[0, 160], [0, 100]] }
        },
        Children: [{
          ClassName: "UIListLayout",
          Properties: { FillDirection: "Horizontal" }
        }, {
          Name: "Top",
          ClassName: "TextButton",
          Properties: { Size: { UDim2: [[0, 100], [0, 30]] } },
          Children: []
        }, {
          Name: "Bottom",
          ClassName: "TextButton",
          Properties: { Size: { UDim2: [[0, 100], [0, 30]] } },
          Children: []
        }]
      }, {
        Name: "LegacyOverlay",
        ClassName: "Frame",
        Properties: { Visible: true },
        Children: []
      }, {
        Name: "LegacyExcluded",
        ClassName: "Frame",
        Properties: { Visible: true },
        Children: []
      }, {
        Name: "Reclassed",
        ClassName: "Frame",
        Properties: { Visible: true },
        Children: []
      }]
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
    }, {
      path: "SurfaceTest/Panel/Label",
      className: "TextLabel",
      visible: true,
      x: 450,
      y: 240,
      width: 120,
      height: 32,
      text: "12.4K",
      textAlignHorizontal: "Right",
      fontFamily: "Luckiest Guy",
      fontStyle: "Regular",
      layout: {
        size: { sx: 0, ox: 120, sy: 0, oy: 32 },
        pos: { sx: 1, ox: -30, sy: 1, oy: -28 },
        anchor: { x: 1, y: 1 },
        parentWidth: 600,
        parentHeight: 300,
        managedByLayout: false
      }
    }, {
      path: "SurfaceTest/Panel/CompactTab",
      className: "Frame",
      visible: true,
      x: 18,
      y: 12,
      width: 140,
      height: 48,
      layout: {
        size: { sx: 1, ox: 0, sy: 0, oy: 48 },
        pos: { sx: 0, ox: 18, sy: 0, oy: 12 },
        anchor: { x: 0, y: 0 },
        parentWidth: 600,
        parentHeight: 300,
        managedByLayout: false
      }
    }, {
      path: "SurfaceTest/Panel/Row",
      className: "Frame",
      visible: true,
      x: 20,
      y: 80,
      width: 300,
      height: 80,
      layout: {
        size: { sx: 0, ox: 300, sy: 0, oy: 80 },
        pos: { sx: 0, ox: 20, sy: 0, oy: 80 },
        anchor: { x: 0, y: 0 },
        parentWidth: 560,
        parentHeight: 280,
        managedByLayout: false
      }
    }, {
      path: "SurfaceTest/Panel/Row/Primary",
      className: "TextButton",
      visible: true,
      x: 20,
      y: 10,
      width: 80,
      height: 60,
      layout: {
        size: { sx: 0, ox: 40, sy: 0, oy: 40 },
        pos: { sx: 0, ox: 0, sy: 0, oy: 0 },
        anchor: { x: 0, y: 0 },
        parentWidth: 300,
        parentHeight: 80,
        managedByLayout: true
      }
    }, {
      path: "SurfaceTest/Panel/Row/Secondary",
      className: "TextButton",
      visible: true,
      x: 112,
      y: 0,
      width: 120,
      height: 80,
      layout: {
        size: { sx: 0, ox: 40, sy: 0, oy: 40 },
        pos: { sx: 0, ox: 0, sy: 0, oy: 0 },
        anchor: { x: 0, y: 0 },
        parentWidth: 300,
        parentHeight: 80,
        managedByLayout: true
      }
    }, {
      path: "SurfaceTest/Panel/Freeform",
      className: "Frame",
      visible: true,
      x: 340,
      y: 80,
      width: 160,
      height: 100,
      layout: {
        size: { sx: 0, ox: 160, sy: 0, oy: 100 },
        pos: { sx: 0, ox: 340, sy: 0, oy: 80 },
        anchor: { x: 0, y: 0 },
        parentWidth: 560,
        parentHeight: 280,
        managedByLayout: false
      }
    }, {
      path: "SurfaceTest/Panel/Freeform/Top",
      className: "TextButton",
      visible: true,
      x: 0,
      y: 0,
      width: 100,
      height: 30,
      layout: {
        size: { sx: 0, ox: 100, sy: 0, oy: 30 },
        pos: { sx: 0, ox: 0, sy: 0, oy: 0 },
        anchor: { x: 0, y: 0 },
        parentWidth: 160,
        parentHeight: 100,
        managedByLayout: true
      }
    }, {
      path: "SurfaceTest/Panel/Freeform/Bottom",
      className: "TextButton",
      visible: true,
      x: 40,
      y: 50,
      width: 100,
      height: 30,
      layout: {
        size: { sx: 0, ox: 100, sy: 0, oy: 30 },
        pos: { sx: 0, ox: 40, sy: 0, oy: 50 },
        anchor: { x: 0, y: 0 },
        parentWidth: 160,
        parentHeight: 100,
        managedByLayout: true
      }
    }, {
      path: "SurfaceTest/Panel/LegacyExcluded",
      className: "Frame",
      visible: true,
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      layout: {
        size: { sx: 0, ox: 10, sy: 0, oy: 10 },
        pos: { sx: 0, ox: 0, sy: 0, oy: 0 },
        anchor: { x: 0, y: 0 },
        parentWidth: 560,
        parentHeight: 280,
        managedByLayout: false
      }
    }, {
      path: "SurfaceTest/Panel/NewFromFigma",
      className: "TextLabel",
      visible: true,
      x: 400,
      y: 220,
      width: 120,
      height: 30,
      text: "NEW",
      cornerRadius: 8,
      stroke: { color: [1, 0.8, 0.1], thickness: 2 },
      layout: {
        size: { sx: 0, ox: 120, sy: 0, oy: 30 },
        pos: { sx: 0, ox: 400, sy: 0, oy: 220 },
        anchor: { x: 0, y: 0 },
        parentWidth: 560,
        parentHeight: 280,
        managedByLayout: false
      }
    }, {
      path: "SurfaceTest/Panel/Reclassed",
      className: "TextLabel",
      visible: true,
      x: 10,
      y: 200,
      width: 100,
      height: 30,
      text: "RECLASSED",
      layout: {
        size: { sx: 0, ox: 100, sy: 0, oy: 30 },
        pos: { sx: 0, ox: 10, sy: 0, oy: 200 },
        anchor: { x: 0, y: 0 },
        parentWidth: 560,
        parentHeight: 280,
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
    patchPath,
    "--exclude-path",
    "SurfaceTest/Panel/LegacyExcluded"
  ], { cwd: repo, encoding: "utf8" });
  assert.equal(applyResult.status, 0, applyResult.stderr || applyResult.stdout);
  const applied = JSON.parse(fs.readFileSync(modelPath, "utf8"));
  assert.deepEqual(applied.Children[0].Properties.BackgroundColor3, [0.1, 0.2, 0.3]);
  assert.equal(applied.Children[0].Properties.BackgroundTransparency, 0.25);
  assert.deepEqual(applied.Children[0].Properties.Size, { UDim2: [[1, -40], [1, -20]] });
  assert.deepEqual(applied.Children[0].Properties.Position, { UDim2: [[0, 20], [0, 10]] });
  assert.deepEqual(applied.Children[0].Children[0].Properties.AnchorPoint, [1, 1]);
  assert.deepEqual(applied.Children[0].Children[0].Properties.Position, { UDim2: [[1, 10], [1, -8]] });
  assert.equal(applied.Children[0].Children[0].Properties.Text, "12.4K");
  assert.equal(applied.Children[0].Children[0].Properties.TextXAlignment, "Right");
  assert.deepEqual(applied.Children[0].Children[0].Properties.FontFace, {
    family: "rbxasset://fonts/families/LuckiestGuy.json",
    weight: "Regular",
    style: "Normal"
  });
  assert.deepEqual(
    applied.Children[0].Children[1].Properties.Size,
    { UDim2: [[0, 140], [0, 48]] },
    "a substantially resized stretch node becomes a responsive fixed-size tab"
  );
  assert.deepEqual(applied.Children[0].Children[1].Children[0].Properties.MinSize, [140, 48]);
  const importedRow = applied.Children[0].Children[2];
  assert.equal(importedRow.Children[0].ClassName, "UIListLayout");
  assert.deepEqual(importedRow.Children[0].Properties.Padding, { UDim: [0, 12] });
  assert.equal(importedRow.Children[0].Properties.HorizontalAlignment, "Left");
  const importedFreeform = applied.Children[0].Children.find((child) => child.Name === "Freeform");
  assert.ok(importedFreeform, "multi-row Figma composition remains authored");
  assert.equal(
    importedFreeform.Children.some((child) => child.ClassName === "UIListLayout"),
    false,
    "legacy list layout cannot rearrange a freeform multi-row Figma composition"
  );
  assert.notDeepEqual(
    importedFreeform.Children.find((child) => child.Name === "Bottom").Properties.Position,
    { UDim2: [[0, 0], [0, 0]] },
    "freeform child receives its Figma-authored position after the legacy layout is removed"
  );
  assert.equal(
    applied.Children[0].Children.some((child) => child.Name === "LegacyOverlay"),
    false,
    "unmapped legacy visuals are pruned by an authoritative import"
  );
  assert.equal(
    applied.Children[0].Children.some((child) => child.Name === "LegacyExcluded"),
    false,
    "explicitly excluded obsolete source paths are pruned instead of reimported"
  );
  const createdFromFigma = applied.Children[0].Children.find((child) => child.Name === "NewFromFigma");
  assert.ok(createdFromFigma, "a new mapped Figma visual is created at its authoritative path");
  assert.equal(createdFromFigma.ClassName, "TextLabel");
  assert.equal(createdFromFigma.Properties.Text, "NEW");
  assert.equal(
    createdFromFigma.Children.find((child) => child.ClassName === "UICorner").Properties.CornerRadius.UDim[1],
    8
  );
  assert.equal(
    createdFromFigma.Children.find((child) => child.ClassName === "UIStroke").Properties.Thickness,
    2
  );
  const reclassed = applied.Children[0].Children.find((child) => child.Name === "Reclassed");
  assert.equal(reclassed.ClassName, "TextLabel", "a stable path can change Roblox visual class");
  assert.equal(reclassed.Properties.Text, "RECLASSED");
  assert.equal(applied.Properties.Enabled, false);
  assert.equal(applied.Properties.ResetOnSpawn, false);
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}

const pluginUi = fs.readFileSync(path.join(repo, "figma/roblox-ui-bridge/ui.html"), "utf8");
assert.match(pluginUi, /<button class="file" id="import" type="button">/);
assert.match(pluginUi, /<input id="models"[^>]*tabindex="-1">/);
assert.match(pluginUi, /<div id="status" role="status">/);
assert.doesNotMatch(pluginUi, /input\[type=file\]\s*\{\s*display:\s*none/);
const pluginSource = fs.readFileSync(path.join(repo, "figma/roblox-ui-bridge/code.js"), "utf8");
assert.match(pluginSource, /entry\.fontFamily = textNode\.fontName\.family/);
assert.match(pluginSource, /entry\.textAlignHorizontal/);
assert.match(pluginSource, /const layout = inferredLayout\(node\)/);
assert.match(pluginSource, /mode: "authoritative"/);
assert.match(pluginSource, /Duplicate Roblox paths found in Figma/);
assert.doesNotMatch(
  pluginSource,
  /new Set\(\["ComponentTemplates", "ShowcaseCanvas", "ScreenTemplate", "Screens"\]\)/,
  "workspace import does not silently omit visual branches"
);
assert.deepEqual(
  bridge.inferredBinding({
    name: "ClaimButton",
    type: "FRAME",
    children: [{ name: "Label", type: "TEXT" }],
    fills: []
  }),
  { name: "ClaimButton", className: "TextButton" },
  "new named Figma controls receive a stable Roblox class and path"
);

const staleLayoutData = new Map([
  ["path", "TemplateUI/Root/Navigation/Buttons/ProfileButton"],
  ["className", "TextButton"],
  ["layout", JSON.stringify({
    size: { sx: 0, ox: 82, sy: 0, oy: 74 },
    pos: { sx: 0, ox: 0, sy: 0, oy: 0 },
    anchor: { x: 1, y: 0 },
    parentWidth: 220,
    parentHeight: 360,
    managedByLayout: true
  })]
]);
const movedFigmaNode = {
  name: "ProfileButton",
  type: "FRAME",
  visible: true,
  opacity: 1,
  x: 108,
  y: 59,
  width: 96,
  height: 106,
  constraints: { horizontal: "MIN", vertical: "MIN" },
  fills: [],
  strokes: [],
  children: [],
  parent: { width: 220, height: 360, layoutMode: "NONE" },
  getSharedPluginData(_namespace, key) {
    return staleLayoutData.get(key) || "";
  },
  setSharedPluginData(_namespace, key, value) {
    staleLayoutData.set(key, value);
  }
};
const movedEntry = bridge.collectPatch([movedFigmaNode])[0];
assert.deepEqual(
  movedEntry.layout,
  {
    size: { sx: 0, ox: 96, sy: 0, oy: 106 },
    pos: { sx: 0, ox: 108, sy: 0, oy: 59 },
    anchor: { x: 0, y: 0 },
    parentWidth: 220,
    parentHeight: 360,
    managedByLayout: false
  },
  "patch export uses current Figma geometry instead of stale imported layout metadata"
);

const templateUi = readJson("src/ui/presets/incremental/TemplateUI.model.json");
const childNamed = (node, name) =>
  (node.Children || []).find((child) => child.Name === name);
const findNamed = (node, name) => {
  if (node.Name === name) {
    return node;
  }
  for (const child of node.Children || []) {
    const match = findNamed(child, name);
    if (match) {
      return match;
    }
  }
  return undefined;
};
const navigation = findNamed(templateUi, "Navigation");
assert.ok(navigation, "TemplateUI keeps the authored lobby navigation");
assert.equal(templateUi.Properties.Enabled, false, "TemplateUI starts disabled until its binder is ready");
for (const legacyName of ["CurrencyHUD", "ShowcaseCanvas", "ScreenTemplate", "ComponentTemplates"]) {
  assert.equal(
    findNamed(templateUi, legacyName),
    undefined,
    `${legacyName} is absent when it is absent from the authoritative Figma workspace`
  );
}
for (const screen of findNamed(templateUi, "Screens").Children) {
  assert.equal(screen.Properties.Visible, false, `${screen.Name} starts closed`);
}
const rewardsContent = findNamed(findNamed(templateUi, "RewardsScreen"), "Content");
assert.ok(rewardsContent, "Rewards content remains authored");
assert.equal(
  rewardsContent.Children.some((child) => child.ClassName === "UIListLayout"),
  false,
  "an obsolete list layout cannot rearrange Figma's multi-row Rewards composition"
);
const navigationButtons = childNamed(navigation, "Buttons");
assert.ok(navigationButtons, "TemplateUI keeps the navigation button container");
assert.equal(navigation.Properties.BackgroundTransparency, 1);
assert.equal(navigation.Properties.ClipsDescendants, false);
assert.equal(navigationButtons.Properties.AutomaticCanvasSize, "None");
assert.equal(navigationButtons.Properties.ClipsDescendants, false);
assert.equal(
  navigation.Children.some((child) => child.ClassName === "UISizeConstraint"),
  false,
  "obsolete horizontal-rail constraint cannot flatten the 3+2 navigation"
);
assert.equal(
  navigationButtons.Children.some(
    (child) => child.ClassName === "UIGridLayout" || child.ClassName === "UIListLayout"
  ),
  false,
  "explicit staggered button positions are not overridden by a layout helper"
);
for (const [name, expected] of Object.entries({
  BagButton: [0, 0],
  ShopButton: [0, 118],
  GiftButton: [0, 236],
  ProfileButton: [108, 59],
  MoreButton: [108, 177]
})) {
  const button = childNamed(navigationButtons, name);
  assert.ok(button, `${name} remains authored`);
  assert.deepEqual(
    button.Properties.Position,
    { UDim2: [[0, expected[0]], [0, expected[1]]] },
    `${name} preserves the intended staggered position`
  );
  assert.equal(button.Properties.BackgroundTransparency, 1);
  assert.equal(button.Properties.ClipsDescendants, false);
  const iconBubble = childNamed(button, "IconBubble");
  assert.equal(iconBubble.Properties.BackgroundTransparency, 1);
  assert.equal(
    iconBubble.Children.find((child) => child.ClassName === "UIStroke").Properties.Transparency,
    1,
    `${name} does not render a generic plate around its icon`
  );
}

const towerLoadoutUi = readJson("src/ui/TowerDefenseLoadoutHUD.model.json");
const towerControlRow = findNamed(towerLoadoutUi, "ControlRow");
assert.ok(towerControlRow, "tower-defense loadout keeps the Figma-authored action row");
assert.equal(
  towerControlRow.Children.some((child) => child.ClassName === "UIListLayout"),
  false,
  "the raised Roll action is not flattened by a legacy UIListLayout"
);
for (const [name, expectedPosition] of Object.entries({
  InventoryButton: [0, 22],
  DiceButton: [116, 0],
  UpgradeTreeButton: [260, 22]
})) {
  const button = childNamed(towerControlRow, name);
  assert.ok(button, `${name} remains authored`);
  assert.deepEqual(
    button.Properties.Position,
    { UDim2: [[0, expectedPosition[0]], [0, expectedPosition[1]]] }
  );
  assert.equal(button.Properties.Text, "");
  assert.equal(childNamed(button, "Icon").ClassName, "ImageLabel");
  assert.equal(childNamed(button, "Label").ClassName, "TextLabel");
}

const towerLevelController = fs.readFileSync(
  path.join(repo, "src/client/Controllers/TowerDefenseLevelController.luau"),
  "utf8"
);
assert.doesNotMatch(
  towerLevelController,
  /applyResponsiveLayout|ViewportSize/,
  "runtime state binding does not replace the Figma-authored level-selector geometry"
);
const towerLevelUi = readJson("src/ui/TowerDefenseLevelHUD.model.json");
const towerLevelPanel = findNamed(towerLevelUi, "Panel");
assert.deepEqual(towerLevelPanel.Properties.AnchorPoint, [1, 1]);
assert.deepEqual(
  towerLevelPanel.Properties.Position,
  { UDim2: [[1, -24], [1, -180]] },
  "level selector stays attached to the authored lower-right safe area"
);
assert.deepEqual(
  towerLevelPanel.Properties.Size,
  { UDim2: [[0.94, 0], [0, 330]] },
  "level selector scales down from its compact authored maximum width"
);
const towerLoadoutController = fs.readFileSync(
  path.join(repo, "src/client/Controllers/TowerDefenseLoadoutController.luau"),
  "utf8"
);
assert.match(towerLoadoutController, /IconCatalog\.get\("rollDice"\)/);
assert.match(towerLoadoutController, /IconCatalog\.get\("talentUpgrade"\)/);
assert.doesNotMatch(
  towerLoadoutController,
  /inventoryButton\.Size|diceButton\.Size|upgradeButton\.Size/,
  "runtime state binding does not replace the Figma-authored action geometry"
);

console.log("Figma UI bridge world-space tests passed.");
