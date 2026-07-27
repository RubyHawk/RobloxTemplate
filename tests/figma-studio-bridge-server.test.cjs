const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

(async () => {
  const bridge = await import("../scripts/figma-studio-bridge-server.mjs");
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "figma-studio-bridge-"));
  try {
    fs.writeFileSync(path.join(temporary, "older.figma-patch.json"), "{}");
    await new Promise((resolve) => setTimeout(resolve, 20));
    fs.writeFileSync(path.join(temporary, "newer.figma-patch"), "{}");
    fs.writeFileSync(path.join(temporary, "ignored.json"), "{}");

    const newest = await bridge.findNewestPatch(temporary);
    assert.equal(path.basename(newest), "newer.figma-patch");

    const workspace = {
      id: "rng-defender",
      models: [{ root: "TemplateUI" }, { root: "DungeonHUD" }],
    };
    bridge.validatePatch({
      format: "roblox-ui-bridge-v1",
      mode: "authoritative",
      workspace: "rng-defender",
      roots: ["TemplateUI", "DungeonHUD"],
    }, workspace);

    assert.throws(() => bridge.validatePatch({
      format: "roblox-ui-bridge-v1",
      mode: "authoritative",
      workspace: "other",
      roots: ["TemplateUI", "DungeonHUD"],
    }, workspace), /not 'rng-defender'/);

    assert.throws(() => bridge.validatePatch({
      format: "roblox-ui-bridge-v1",
      mode: "authoritative",
      workspace: "rng-defender",
      roots: ["TemplateUI"],
    }, workspace), /missing DungeonHUD/);

    assert.equal(bridge.tailOutput("one\ntwo\nthree", 2), "two\nthree");
    console.log("Figma Studio bridge server tests passed.");
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
