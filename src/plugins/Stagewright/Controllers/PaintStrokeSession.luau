--!strict

export type Tool = "Pencil" | "Erase" | "Rect" | "Fill"
export type FailurePhase = "Apply" | "Commit"
export type Spec = {
	tool: Tool,
	brushId: string,
	brushSize: number,
}
export type Visited = { [string]: boolean }

export type Config = {
	beginEdit: (label: string) -> number?,
	finishEdit: (transaction: number, commit: boolean) -> boolean,
	dimensions: () -> (number, number),
	fillToken: (column: number, row: number) -> any,
	applyArea: (
		brushId: string,
		column: number,
		row: number,
		brushSize: number,
		visited: Visited
	) -> boolean,
	onPreview: () -> (),
	reportBlocked: (action: string) -> (),
	onCommitted: (action: string) -> (),
	onFailed: (action: string, phase: FailurePhase) -> (),
}

export type Session = {
	begin: (self: Session, spec: Spec, column: number, row: number) -> boolean,
	move: (self: Session, column: number, row: number, modifierDown: boolean) -> boolean,
	release: (self: Session, column: number?, row: number?) -> boolean,
	cancel: (self: Session, reason: string) -> boolean,
	isActive: (self: Session) -> boolean,
}

type ActiveStroke = {
	spec: Spec,
	transaction: number,
	originColumn: number,
	originRow: number,
	visited: Visited,
}

type Cell = {
	column: number,
	row: number,
}

local PaintStrokeSession = {}

local function actionFor(tool: Tool): string
	return if tool == "Fill" then "Paint fill" else "Paint stroke"
end

local function copySpec(spec: Spec): Spec
	return {
		tool = spec.tool,
		brushId = spec.brushId,
		brushSize = math.max(math.floor(spec.brushSize), 1),
	}
end

function PaintStrokeSession.new(config: Config): Session
	local active: ActiveStroke? = nil

	local function finish(transaction: number, commit: boolean): boolean
		local succeeded, committed = pcall(config.finishEdit, transaction, commit)
		return succeeded and committed == true
	end

	local function failApply(stroke: ActiveStroke, action: string): boolean
		active = nil
		finish(stroke.transaction, false)
		config.onFailed(action, "Apply")
		return false
	end

	local function apply(stroke: ActiveStroke, column: number, row: number, brushSize: number): boolean
		local succeeded, changed =
			pcall(config.applyArea, stroke.spec.brushId, column, row, brushSize, stroke.visited)
		if not succeeded or changed ~= true then
			return false
		end
		return true
	end

	local function commit(stroke: ActiveStroke, action: string): boolean
		active = nil
		if finish(stroke.transaction, true) then
			config.onCommitted(action)
			return true
		end
		config.onFailed(action, "Commit")
		return false
	end

	local function fill(stroke: ActiveStroke, column: number, row: number): boolean
		local columns, rows = config.dimensions()
		if column < 1 or column > columns or row < 1 or row > rows then
			return failApply(stroke, "Paint fill")
		end
		local tokenSucceeded, targetToken = pcall(config.fillToken, column, row)
		if not tokenSucceeded then
			return failApply(stroke, "Paint fill")
		end
		local queue: { Cell } = { { column = column, row = row } }
		local scanned: Visited = {}
		local head = 1
		while queue[head] ~= nil do
			local cell = queue[head]
			head += 1
			local key = `{cell.column}:{cell.row}`
			if
				not scanned[key]
				and cell.column >= 1
				and cell.column <= columns
				and cell.row >= 1
				and cell.row <= rows
			then
				scanned[key] = true
				local readSucceeded, token = pcall(config.fillToken, cell.column, cell.row)
				if not readSucceeded then
					return failApply(stroke, "Paint fill")
				end
				if token == targetToken then
					if not apply(stroke, cell.column, cell.row, 1) then
						return failApply(stroke, "Paint fill")
					end
					table.insert(queue, { column = cell.column - 1, row = cell.row })
					table.insert(queue, { column = cell.column + 1, row = cell.row })
					table.insert(queue, { column = cell.column, row = cell.row - 1 })
					table.insert(queue, { column = cell.column, row = cell.row + 1 })
				end
			end
		end
		config.onPreview()
		return commit(stroke, "Paint fill")
	end

	local session: Session = {} :: any
	session.begin = function(_self: Session, requestedSpec: Spec, column: number, row: number): boolean
		local replaced = active
		active = nil
		if replaced ~= nil then
			finish(replaced.transaction, false)
		end

		local spec = copySpec(requestedSpec)
		local action = actionFor(spec.tool)
		local began, transaction = pcall(config.beginEdit, "Paint Stagewright cells")
		if not began or transaction == nil then
			config.reportBlocked(action)
			return false
		end
		local stroke: ActiveStroke = {
			spec = spec,
			transaction = transaction,
			originColumn = column,
			originRow = row,
			visited = {},
		}
		active = stroke
		if spec.tool == "Fill" then
			return fill(stroke, column, row)
		elseif spec.tool == "Rect" then
			return true
		end
		if not apply(stroke, column, row, spec.brushSize) then
			return failApply(stroke, action)
		end
		config.onPreview()
		return true
	end

	session.move = function(_self: Session, column: number, row: number, modifierDown: boolean): boolean
		local stroke = active
		if
			stroke == nil
			or not modifierDown
			or (stroke.spec.tool ~= "Pencil" and stroke.spec.tool ~= "Erase")
		then
			return false
		end
		if not apply(stroke, column, row, stroke.spec.brushSize) then
			return failApply(stroke, actionFor(stroke.spec.tool))
		end
		config.onPreview()
		return true
	end

	session.release = function(_self: Session, column: number?, row: number?): boolean
		local stroke = active
		if stroke == nil then
			return false
		end
		local action = actionFor(stroke.spec.tool)
		if stroke.spec.tool == "Rect" and column ~= nil and row ~= nil then
			for targetRow = math.min(stroke.originRow, row), math.max(stroke.originRow, row) do
				for targetColumn = math.min(stroke.originColumn, column), math.max(stroke.originColumn, column) do
					if not apply(stroke, targetColumn, targetRow, 1) then
						return failApply(stroke, action)
					end
				end
			end
			config.onPreview()
		end
		return commit(stroke, action)
	end

	session.cancel = function(_self: Session, _reason: string): boolean
		local stroke = active
		active = nil
		if stroke == nil then
			return false
		end
		finish(stroke.transaction, false)
		return true
	end

	session.isActive = function(_self: Session): boolean
		return active ~= nil
	end

	return session
end

return table.freeze(PaintStrokeSession)
