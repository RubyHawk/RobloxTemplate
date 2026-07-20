--!strict

local StageCell = require(script.Parent.Parent.Shared.StageCell)
local Theme = require(script.Parent.Theme)

local COLORS = Theme.colors

export type Layer = "All" | "Terrain" | "Build" | "Traversal" | "Roles"

type RoleAppearance = {
	color: Color3,
	glyph: string,
}

local ROLE_APPEARANCE: { [string]: RoleAppearance } = {
	EnemySpawn = { color = Color3.fromRGB(45, 146, 84), glyph = "S" },
	EnemyGoal = { color = Color3.fromRGB(113, 76, 193), glyph = "G" },
	AutoPlace = { color = COLORS.auto, glyph = "A" },
	Hazard = { color = COLORS.blocked, glyph = "H" },
	Reward = { color = COLORS.warning, glyph = "R" },
	Trigger = { color = COLORS.accent, glyph = "T" },
	StageTransition = { color = COLORS.accentMuted, glyph = ">" },
	DecorationAnchor = { color = COLORS.surface, glyph = "D" },
}

local ROLE_ORDER: { string } = {
	"EnemySpawn",
	"EnemyGoal",
	"AutoPlace",
	"Hazard",
	"Reward",
	"Trigger",
	"StageTransition",
	"DecorationAnchor",
}

local PaintAppearance = {}

local function terrainAppearance(terrainId: string?): (Color3, string)
	return if terrainId == "void" then COLORS.void else COLORS.ground, ""
end

local function buildAppearance(buildPolicy: string?): (Color3, string)
	if buildPolicy == "Blocked" then
		return COLORS.blocked, "X"
	elseif buildPolicy == "AutoOnly" then
		return COLORS.auto, "A"
	end
	return COLORS.allowed, ""
end

local function traversalAppearance(traversalPolicy: string?): (Color3, string)
	if traversalPolicy == "Blocked" then
		return COLORS.blocked, "X"
	end
	return Color3.fromRGB(51, 116, 164), ""
end

local function roleNames(roles: any): { string }
	local names: { string } = {}
	if type(roles) ~= "table" then
		return names
	end
	for role, enabled in roles do
		if type(role) == "string" and enabled == true then
			table.insert(names, role)
		end
	end
	table.sort(names)
	return names
end

local function rolesAppearance(roles: any): (Color3, string)
	local names = roleNames(roles)
	if #names == 0 then
		return COLORS.surface, ""
	end
	local firstAppearance: RoleAppearance? = nil
	for _, role in ROLE_ORDER do
		if roles[role] == true then
			firstAppearance = ROLE_APPEARANCE[role]
			break
		end
	end
	if firstAppearance == nil then
		firstAppearance = { color = COLORS.accent, glyph = "R" }
	end
	return firstAppearance.color, if #names > 1 then tostring(math.min(#names, 9)) else firstAppearance.glyph
end

function PaintAppearance.token(authoredCell: any?, defaultCell: any, layer: Layer): string
	local cell = StageCell.resolve(defaultCell, authoredCell)
	if layer == "Terrain" then
		return `surface:{tostring(cell.terrainId)}`
	elseif layer == "Build" then
		return `towers:{tostring(cell.buildPolicy)}`
	elseif layer == "Traversal" then
		return `route:{tostring(cell.enemyTraversalPolicy)}`
	elseif layer == "Roles" then
		return `roles:{table.concat(roleNames(cell.roles), ",")}`
	end
	return table.concat({
		`surface:{tostring(cell.terrainId)}`,
		`towers:{tostring(cell.buildPolicy)}`,
		`route:{tostring(cell.enemyTraversalPolicy)}`,
		`roles:{table.concat(roleNames(cell.roles), ",")}`,
	}, "|")
end

function PaintAppearance.resolve(authoredCell: any?, defaultCell: any, layer: Layer?): (Color3, string)
	local cell = StageCell.resolve(defaultCell, authoredCell)
	local resolvedLayer = layer or "All"
	if resolvedLayer == "Terrain" then
		return terrainAppearance(cell.terrainId)
	elseif resolvedLayer == "Build" then
		return buildAppearance(cell.buildPolicy)
	elseif resolvedLayer == "Traversal" then
		return traversalAppearance(cell.enemyTraversalPolicy)
	elseif resolvedLayer == "Roles" then
		return rolesAppearance(cell.roles)
	end

	local roleColor, roleGlyph = rolesAppearance(cell.roles)
	if roleGlyph ~= "" then
		return roleColor, roleGlyph
	end
	if cell.enemyTraversalPolicy == "Blocked" then
		return COLORS.blocked, "R"
	elseif cell.buildPolicy == "Blocked" then
		return COLORS.blocked, "X"
	elseif cell.buildPolicy == "AutoOnly" then
		return COLORS.auto, "A"
	end
	return terrainAppearance(cell.terrainId)
end

return table.freeze(PaintAppearance)
