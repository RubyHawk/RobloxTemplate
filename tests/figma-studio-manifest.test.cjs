const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repository = path.resolve(__dirname, "..");
const generator = path.join(repository, "scripts", "generate-figma-studio-manifest.mjs");
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "figma-studio-manifest-"));

function run(arguments_) {
  return spawnSync(process.execPath, [generator, ...arguments_], {
    cwd: temporary,
    encoding: "utf8",
  });
}

try {
  const modelPath = path.join(temporary, "Example.model.json");
  const workspacePath = path.join(temporary, "workspace.json");
  const patchPath = path.join(temporary, "export.figma-patch.json");
  const deliveryPath = path.join(temporary, "delivery.json");
  const outputPath = path.join(temporary, "Manifest.generated.luau");
  const runtimePath = path.join(temporary, "Manifest.runtime.json");

  fs.writeFileSync(modelPath, JSON.stringify({
    ClassName: "ScreenGui",
    Properties: { Enabled: true },
    Children: [{
      Name: "Root",
      ClassName: "Frame",
      Properties: {
        Position: { UDim2: [[0.5, -20], [0, 12]] },
        Size: { UDim2: [[0, 200], [0, 80]] },
        Visible: true,
      },
      Children: [{
        ClassName: "UIStroke",
        Properties: { Color: [0.1, 0.2, 0.3], Thickness: 2 },
        Children: [],
      }],
    }],
  }));
  fs.writeFileSync(workspacePath, JSON.stringify({
    format: "roblox-ui-workspace-v1",
    id: "example",
    name: "Example",
    models: [{
      root: "ExampleUI",
      path: "Example.model.json",
      studioPath: "StarterGui/ExampleUI",
      scope: "production",
    }],
  }));
  const patchText = JSON.stringify({
    format: "roblox-ui-bridge-v1",
    mode: "authoritative",
    exportedAt: "2026-07-27T10:00:00.000Z",
    workspace: "example",
    roots: ["ExampleUI"],
    entries: [],
  });
  fs.writeFileSync(patchPath, patchText);

  const arguments_ = [
    "--workspace", workspacePath,
    "--delivery", deliveryPath,
    "--output", outputPath,
    "--runtime", runtimePath,
    "--patch", patchPath,
  ];
  const generated = run(arguments_);
  assert.equal(generated.status, 0, generated.stderr);

  const delivery = JSON.parse(fs.readFileSync(deliveryPath, "utf8"));
  assert.equal(delivery.rootCount, 1);
  assert.equal(delivery.entryCount, 3);
  assert.equal(delivery.source.checksum, crypto.createHash("sha256").update(patchText).digest("hex"));

  const manifest = fs.readFileSync(outputPath, "utf8");
  assert.match(manifest, /StarterGui\/ExampleUI/);
  assert.match(manifest, /\["Thickness"\] = 2/);
  assert.doesNotMatch(manifest, /\["Text"\]/);
  const runtimeManifest = JSON.parse(fs.readFileSync(runtimePath, "utf8"));
  assert.equal(runtimeManifest.roots[0].studioPath, "StarterGui/ExampleUI");

  const checked = run([
    "--workspace", workspacePath,
    "--delivery", deliveryPath,
    "--output", outputPath,
    "--runtime", runtimePath,
    "--check",
  ]);
  assert.equal(checked.status, 0, checked.stderr);

  fs.rmSync(outputPath);
  const runtimeGenerated = run([
    "--workspace", workspacePath,
    "--delivery", deliveryPath,
    "--output", outputPath,
    "--runtime", runtimePath,
    "--manifest-only",
  ]);
  assert.equal(runtimeGenerated.status, 0, runtimeGenerated.stderr);
  assert.equal(fs.existsSync(outputPath), true);

  const model = JSON.parse(fs.readFileSync(modelPath, "utf8"));
  model.Children[0].Properties.Size = { UDim2: [[0, 240], [0, 80]] };
  fs.writeFileSync(modelPath, JSON.stringify(model));
  const stale = run([
    "--workspace", workspacePath,
    "--delivery", deliveryPath,
    "--output", outputPath,
    "--runtime", runtimePath,
    "--check",
  ]);
  assert.notEqual(stale.status, 0);
  assert.match(stale.stderr, /manifest is stale/i);

  const staleRuntime = run([
    "--workspace", workspacePath,
    "--delivery", deliveryPath,
    "--output", outputPath,
    "--runtime", runtimePath,
    "--manifest-only",
  ]);
  assert.notEqual(staleRuntime.status, 0);
  assert.match(staleRuntime.stderr, /delivery metadata is stale/i);

  console.log("Figma Studio manifest tests passed.");
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
