--!strict

-- Parses and shape-checks a generated DesignerConfig.luau before it is baked
-- into a test experience. Rojo copies module source verbatim, so this is the
-- only pre-Studio point where a generation bug (bad escaping, dropped
-- currency, wrong types) can fail loudly instead of shipping a dead place.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

-- Lune forwards a literal "--" separator as the first argument; accept both
-- invocation styles.
local path = process.args[1]
if path == "--" then
	path = process.args[2]
end
assert(type(path) == "string" and #path > 0, "usage: lune run scripts/validate-designer-config <path>")

local source = fs.readFile(path)
local recipe = luau.load(source)()
assert(type(recipe) == "table", "generated DesignerConfig must return a table")
assert(
	recipe.preset == "incremental" or recipe.preset == "rpg",
	"generated preset must be incremental or rpg"
)
assert(
	type(recipe.currencies) == "table" and #recipe.currencies >= 1 and #recipe.currencies <= 5,
	"generated recipe must keep one to five currencies"
)
local usedIds: { [string]: boolean } = {}
for index, currency in recipe.currencies do
	assert(type(currency) == "table", `currency {index} must be a table`)
	assert(
		type(currency.id) == "string" and string.match(currency.id, "^[a-z][a-z0-9_]*$") ~= nil,
		`currency {index} id must be a lowercase identifier`
	)
	assert(not usedIds[currency.id], `currency id {currency.id} is duplicated`)
	usedIds[currency.id] = true
	assert(type(currency.name) == "string" and #currency.name >= 1, `currency {index} needs a name`)
	assert(type(currency.symbol) == "string" and #currency.symbol >= 1, `currency {index} needs a symbol`)
	assert(
		type(currency.startingAmount) == "number" and currency.startingAmount >= 0,
		`currency {index} starting amount must be zero or more`
	)
	assert(type(currency.color) == "table" and #currency.color == 3, `currency {index} needs an RGB color`)
end
assert(type(recipe.features) == "table", "generated features must be a table")
for feature, enabled in recipe.features do
	assert(type(feature) == "string", "feature keys must be strings")
	assert(type(enabled) == "boolean", `feature {feature} must be true or false`)
end

print(`validated {path}`)
