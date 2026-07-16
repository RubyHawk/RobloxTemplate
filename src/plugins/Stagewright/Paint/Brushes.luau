--!strict

export type Brush = {
	id: string,
	label: string,
	category: string,
	help: string,
	apply: (cell: any) -> (),
}

local Brushes = {}

Brushes.RESET_ID = "reset_cell"

local definitions: { Brush } = {
	{
		id = Brushes.RESET_ID,
		label = "Reset to default",
		category = "Quick tools",
		help = "Remove authored overrides so the cell inherits the level default.",
		apply = function(cell)
			for key in cell do
				cell[key] = nil
			end
		end,
	},
	{
		id = "terrain_ground",
		label = "Ground",
		category = "Terrain",
		help = "Paint normal playable ground.",
		apply = function(cell)
			cell.terrainId = "ground"
		end,
	},
	{
		id = "terrain_void",
		label = "Void",
		category = "Terrain",
		help = "Paint empty terrain outside the playable surface.",
		apply = function(cell)
			cell.terrainId = "void"
		end,
	},
	{
		id = "build_allowed",
		label = "Build allowed",
		category = "Build policy",
		help = "Allow players to place towers in this cell.",
		apply = function(cell)
			cell.buildPolicy = "Allowed"
		end,
	},
	{
		id = "build_blocked",
		label = "Build blocked",
		category = "Build policy",
		help = "Prevent tower placement without changing terrain.",
		apply = function(cell)
			cell.buildPolicy = "Blocked"
		end,
	},
	{
		id = "build_auto",
		label = "Auto-place only",
		category = "Build policy",
		help = "Reserve this cell for automatic placement systems.",
		apply = function(cell)
			cell.buildPolicy = "AutoOnly"
		end,
	},
	{
		id = "traversal_allowed",
		label = "Traversal allowed",
		category = "Enemy traversal",
		help = "Allow route corridors to cross this cell.",
		apply = function(cell)
			cell.enemyTraversalPolicy = "Allowed"
		end,
	},
	{
		id = "traversal_blocked",
		label = "Traversal blocked",
		category = "Enemy traversal",
		help = "Prevent route corridors from crossing this cell.",
		apply = function(cell)
			cell.enemyTraversalPolicy = "Blocked"
		end,
	},
}

local function roleBrush(role: string): Brush
	local label = string.gsub(role, "(%l)(%u)", "%1 %2")
	return {
		id = `role_{role}`,
		label = label,
		category = "Cell roles",
		help = `Toggle the {label} role on painted cells.`,
		apply = function(cell)
			cell.roles = cell.roles or {}
			cell.roles[role] = not cell.roles[role]
			if role == "EnemySpawn" or role == "EnemyGoal" then
				cell.buildPolicy = "Blocked"
			elseif role == "AutoPlace" and cell.buildPolicy == "Blocked" then
				cell.buildPolicy = "Allowed"
			end
		end,
	}
end

for _, role in
	{
		"EnemySpawn",
		"EnemyGoal",
		"AutoPlace",
		"Hazard",
		"Reward",
		"Trigger",
		"StageTransition",
		"DecorationAnchor",
	}
do
	table.insert(definitions, roleBrush(role))
end

Brushes.all = table.freeze(definitions)

function Brushes.find(id: string): Brush
	for _, brush in definitions do
		if brush.id == id then
			return brush
		end
	end
	return definitions[1]
end

function Brushes.applyArea(
	grid: any,
	brush: Brush,
	column: number,
	row: number,
	brushSize: number,
	paintedKeys: { [string]: boolean }
)
	local radius = math.floor(brushSize / 2)
	for targetRow = math.max(row - radius, 1), math.min(row + radius, grid.rows) do
		for targetColumn = math.max(column - radius, 1), math.min(column + radius, grid.columns) do
			local key = `{targetColumn}:{targetRow}`
			if not paintedKeys[key] then
				paintedKeys[key] = true
				local cell = grid.cells[key]
				if cell == nil then
					cell = {}
					grid.cells[key] = cell
				end
				brush.apply(cell)
				if next(cell) == nil then
					grid.cells[key] = nil
				end
			end
		end
	end
end

return table.freeze(Brushes)
