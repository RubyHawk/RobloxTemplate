--!strict

local Theme = require(script.Parent.Theme)

local COLORS = Theme.colors
local PaintAppearance = {}

function PaintAppearance.resolve(cell: any, authoredCell: any?, defaultCell: any): (Color3, string)
	local roles = cell.roles or defaultCell.roles or {}
	local terrainId = cell.terrainId or defaultCell.terrainId
	local color = if terrainId == "void" then COLORS.void else COLORS.ground
	local glyph = ""
	if authoredCell ~= nil and authoredCell.buildPolicy == "Allowed" then
		color = COLORS.allowed
	elseif authoredCell ~= nil and authoredCell.buildPolicy == "Blocked" then
		color = COLORS.blocked
		glyph = "X"
	elseif authoredCell ~= nil and authoredCell.buildPolicy == "AutoOnly" then
		color = COLORS.auto
		glyph = "A"
	end
	if authoredCell ~= nil and authoredCell.enemyTraversalPolicy == "Allowed" then
		color = Color3.fromRGB(51, 116, 164)
	elseif authoredCell ~= nil and authoredCell.enemyTraversalPolicy == "Blocked" then
		color = COLORS.blocked
		glyph = "X"
	end
	if roles.EnemySpawn then
		return Color3.fromRGB(45, 146, 84), "S"
	elseif roles.EnemyGoal then
		return Color3.fromRGB(113, 76, 193), "G"
	elseif roles.AutoPlace then
		return color, "A"
	elseif roles.Hazard then
		return COLORS.blocked, "H"
	elseif roles.Reward then
		return COLORS.warning, "R"
	elseif roles.Trigger then
		return COLORS.accent, "T"
	elseif roles.StageTransition then
		return COLORS.accentMuted, ">"
	elseif roles.DecorationAnchor then
		return COLORS.surface, "D"
	end
	return color, glyph
end

return table.freeze(PaintAppearance)
