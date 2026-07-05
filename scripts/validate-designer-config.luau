--!strict

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.args[1]
if path == "--" then
	path = process.args[2]
end
assert(type(path) == "string" and #path > 0, "usage: validate-designer-config <path>")

local source = fs.readFile(path)
local recipe = luau.load(source)()
assert(type(recipe) == "table", "generated DesignerConfig must return a table")
assert(
	type(recipe.experienceMode) == "string" and recipe.experienceMode == "playable",
	"generated experiences must select playable persistence"
)
assert(
	type(recipe.preset) == "string" and string.match(recipe.preset, "^[a-z][a-z0-9_-]*$") ~= nil,
	"generated preset name is invalid"
)
assert(
	type(recipe.dataNamespace) == "string"
		and #recipe.dataNamespace >= 1
		and #recipe.dataNamespace <= 15
		and string.match(recipe.dataNamespace, "^[a-z][a-z0-9_]*$") ~= nil,
	"generated DataStore namespace is invalid"
)
assert(type(recipe.identity) == "table", "generated identity must be a table")
assert(
	type(recipe.identity.universeId) == "number" and recipe.identity.universeId >= 0,
	"generated universe ID is invalid"
)
assert(
	type(recipe.identity.placeId) == "number" and recipe.identity.placeId >= 0,
	"generated place ID is invalid"
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
	assert(type(currency.iconAssetId) == "string", `currency {index} icon asset ID must be a string`)
	assert(
		currency.iconAssetId == "" or string.match(currency.iconAssetId, "^%d+$") ~= nil,
		`currency {index} icon asset ID must contain only digits`
	)
	assert(
		type(currency.startingAmount) == "number" and currency.startingAmount >= 0,
		`currency {index} starting amount must be zero or more`
	)
	assert(type(currency.color) == "table" and #currency.color == 3, `currency {index} needs RGB`)
end
assert(type(recipe.features) == "table", "generated features must be a table")
for feature, enabled in recipe.features do
	assert(type(feature) == "string", "feature keys must be strings")
	assert(type(enabled) == "boolean", `feature {feature} must be true or false`)
end

print(`validated {path}`)
