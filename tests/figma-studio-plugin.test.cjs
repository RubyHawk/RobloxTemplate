const assert = require("node:assert/strict");
const fs = require("node:fs");

const source = fs.readFileSync("src/plugins/FigmaUiBridgePlugin.server.luau", "utf8");
const validator = fs.readFileSync("src/plugins/FigmaUiBridge/Validator.luau", "utf8");
const project = JSON.parse(fs.readFileSync("plugins/figma-ui-bridge.project.json", "utf8"));

assert.match(source, /require\(script\.FigmaUiBridge\.Validator\)/);
assert.match(source, /require\(script\.FigmaUiBridge\.Manifest\)/);
assert.match(source, /require\(script\.FigmaUiBridge\.Runtime\)/);
assert.doesNotMatch(source, /script\.Parent\.FigmaUiBridge/);
assert.match(source, /requestJson\("POST", "\/apply"\)/);
assert.match(source, /requestJson\("GET", "\/status"\)/);
assert.match(source, /requestJson\("GET", "\/manifest"\)/);
assert.match(source, /\["x-figma-ui-token"\] = Runtime\.token/);
assert.match(source, /Validator\.validate\(currentManifest\)/);
assert.match(source, /Stop the playtest before/);
assert.doesNotMatch(source, /ChangeHistoryService/);
assert.match(validator, /local COLOR_EPSILON = 0\.5 \/ 255 \+ EPSILON/);
assert.match(validator, /COLOR_PROPERTIES\[propertyName\]/);
assert.match(validator, /return "\{ " \.\. table\.concat\(parts, ", "\) \.\. " \}"/);

assert.equal(
  project.tree.FigmaUiBridge.Runtime.$path,
  "../src/plugins/FigmaUiBridge/Runtime.generated.luau",
);

console.log("Figma Studio plugin contract tests passed.");
