--!strict

export type Layer = "All" | "Terrain" | "Build" | "Traversal" | "Roles"

export type Brush = {
	id: string,
	label: string,
	layer: Layer,
	help: string,
	apply: (cell: any) -> (),
}

local Brushes = {}

Brushes.RESET_ID = "reset_cell"

local definitions: { Brush } = {
	{
		id = Brushes.RESET_ID,
		label = "Reset cell (all properties)",
		layer = "All",
		help = "Remove every authored cell property so the cell inherits all level defaults.",
		apply = function(cell)
			for key in cell do
				cell[key] = nil
			end
		end,
	},
	{
		id = "terrain_ground",
		label = "Ground",
		layer = "Terrain",
		help = "Set Surface to Ground. Tower placement, route access, and roles stay unchanged.",
		apply = function(cell)
			cell.terrainId = "ground"
		end,
	},
	{
		id = "terrain_void",
		label = "Void",
		layer = "Terrain",
		help = "Set Surface to Void. Tower placement, route access, and roles stay unchanged.",
		apply = function(cell)
			cell.terrainId = "void"
		end,
	},
	{
		id = "build_allowed",
		label = "Build allowed",
		layer = "Build",
		help = "Set Tower placement to Allowed without changing the cell surface or route access.",
		apply = function(cell)
			cell.buildPolicy = "Allowed"
		end,
	},
	{
		id = "build_blocked",
		label = "Build blocked",
		layer = "Build",
		help = "Set Tower placement to Blocked without changing the cell surface or route access.",
		apply = function(cell)
			cell.buildPolicy = "Blocked"
		end,
	},
	{
		id = "build_auto",
		label = "Auto-place only",
		layer = "Build",
		help = "Set Tower placement to Auto-place only; other cell properties stay unchanged.",
		apply = function(cell)
			cell.buildPolicy = "AutoOnly"
		end,
	},
	{
		id = "traversal_allowed",
		label = "Traversal allowed",
		layer = "Traversal",
		help = "Set Route access to Allowed without changing the surface or tower placement.",
		apply = function(cell)
			cell.enemyTraversalPolicy = "Allowed"
		end,
	},
	{
		id = "traversal_blocked",
		label = "Traversal blocked",
		layer = "Traversal",
		help = "Set Route access to Blocked without changing the surface or tower placement.",
		apply = function(cell)
			cell.enemyTraversalPolicy = "Blocked"
		end,
	},
}

local function roleBrush(role: string): Brush
	local label = string.gsub(role, "(%l)(%u)", "%1 %2")
	local help = if role == "EnemySpawn" or role == "EnemyGoal"
		then `Toggle the {label} role. Enabling it also blocks tower placement on this cell.`
		elseif
			role == "AutoPlace"
		then "Toggle the Auto Place role. Enabling it also sets Tower placement to Allowed."
		else `Toggle the {label} role. Surface, tower placement, and route access stay unchanged.`
	return {
		id = `role_{role}`,
		label = label,
		layer = "Roles",
		help = help,
		apply = function(cell)
			cell.roles = cell.roles or {}
			local enabled = cell.roles[role] ~= true
			cell.roles[role] = if enabled then true else nil
			if enabled and (role == "EnemySpawn" or role == "EnemyGoal" or role == "AutoPlace") then
				for _, primaryRole in { "EnemySpawn", "EnemyGoal", "AutoPlace" } do
					if primaryRole ~= role then
						cell.roles[primaryRole] = nil
					end
				end
			end
			if enabled then
				if role == "EnemySpawn" or role == "EnemyGoal" then
					cell.buildPolicy = "Blocked"
				elseif role == "AutoPlace" then
					cell.buildPolicy = "Allowed"
				end
			end
			if next(cell.roles) == nil then
				cell.roles = nil
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

local eraseBrushes: { [Layer]: Brush } = {
	All = definitions[1],
	Terrain = {
		id = "erase_terrain",
		label = "Reset Surface",
		layer = "Terrain",
		help = "Restore Surface from the level default; other cell properties stay unchanged.",
		apply = function(cell)
			cell.terrainId = nil
		end,
	},
	Build = {
		id = "erase_build",
		label = "Reset Tower placement",
		layer = "Build",
		help = "Restore Tower placement from the level default; other cell properties stay unchanged.",
		apply = function(cell)
			cell.buildPolicy = nil
		end,
	},
	Traversal = {
		id = "erase_traversal",
		label = "Reset Route access",
		layer = "Traversal",
		help = "Restore Route access from the level default; other cell properties stay unchanged.",
		apply = function(cell)
			cell.enemyTraversalPolicy = nil
		end,
	},
	Roles = {
		id = "erase_roles",
		label = "Clear optional roles",
		layer = "Roles",
		help = "Remove optional roles from this cell; other cell properties stay unchanged.",
		apply = function(cell)
			cell.roles = nil
		end,
	},
}

Brushes.all = table.freeze(definitions)

function Brushes.layerLabel(layer: Layer): string
	if layer == "Terrain" then
		return "Surface"
	elseif layer == "Build" then
		return "Tower placement"
	elseif layer == "Traversal" then
		return "Route access"
	elseif layer == "Roles" then
		return "Cell roles"
	end
	return "All properties"
end

function Brushes.find(id: string): Brush
	for _, brush in definitions do
		if brush.id == id then
			return brush
		end
	end
	for _, brush in eraseBrushes do
		if brush.id == id then
			return brush
		end
	end
	return definitions[1]
end

function Brushes.eraseId(layer: Layer): string
	return eraseBrushes[layer].id
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
