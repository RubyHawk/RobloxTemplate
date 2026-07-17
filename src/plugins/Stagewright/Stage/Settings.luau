--!strict

export type Input = {
	name: string,
	waveSetId: string,
	themeId: string,
	columns: string,
	rows: string,
	cellSize: string,
}

export type Update = {
	name: string?,
	waveSetId: string,
	themeId: string,
	columns: number,
	rows: number,
	cellSize: number,
}

type Grid = {
	columns: number,
	rows: number,
	cellSize: number,
	cells: { [string]: any },
}

type StageDefinition = {
	name: string,
	waveSetId: string,
	themeId: string,
	grid: Grid,
}

local Settings = {}

Settings.INVALID_GRID_MESSAGE =
	"Grid width and height must be 1-512; cell size must be greater than 0 and at most 128."

local function cellIsOutside(key: string, columns: number, rows: number): boolean
	local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
	local column, row = tonumber(columnText), tonumber(rowText)
	return column == nil or row == nil or column > columns or row > rows
end

function Settings.parse(input: Input): (Update?, string?)
	local columns = tonumber(input.columns)
	local rows = tonumber(input.rows)
	local cellSize = tonumber(input.cellSize)
	if
		columns == nil
		or rows == nil
		or cellSize == nil
		or columns < 1
		or columns > 512
		or rows < 1
		or rows > 512
		or cellSize <= 0
		or cellSize > 128
	then
		return nil, Settings.INVALID_GRID_MESSAGE
	end
	return {
		name = if input.name ~= "" then input.name else nil,
		waveSetId = input.waveSetId,
		themeId = input.themeId,
		columns = math.floor(columns),
		rows = math.floor(rows),
		cellSize = cellSize,
	},
		nil
end

function Settings.countTruncated(grid: Grid, columns: number, rows: number): number
	local count = 0
	for key in grid.cells do
		if cellIsOutside(key, columns, rows) then
			count += 1
		end
	end
	return count
end

function Settings.apply(definition: StageDefinition, update: Update)
	if update.name ~= nil then
		definition.name = update.name
	end
	definition.waveSetId = update.waveSetId
	definition.themeId = update.themeId
	definition.grid.columns = update.columns
	definition.grid.rows = update.rows
	definition.grid.cellSize = update.cellSize
	for key in definition.grid.cells do
		if cellIsOutside(key, update.columns, update.rows) then
			definition.grid.cells[key] = nil
		end
	end
end

return table.freeze(Settings)
