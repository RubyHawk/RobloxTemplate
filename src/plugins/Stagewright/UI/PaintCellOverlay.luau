--!strict

local Factory = require(script.Parent.Factory)
local Theme = require(script.Parent.Theme)

local COLORS = Theme.colors
local create = Factory.create
local CELL_INSET = 22

export type RefreshConfig = {
	columns: number,
	rows: number,
	cellPixels: number,
	selectedCellKey: string?,
	showHover: boolean,
	showSelection: boolean,
}

export type Controller = {
	clearHover: (self: Controller) -> (),
	setHover: (self: Controller, column: number, row: number) -> (),
	hoverCell: (self: Controller, pointerPosition: Vector2?) -> (number?, number?),
	refresh: (self: Controller, config: RefreshConfig) -> (),
}

local PaintCellOverlay = {}

local function outline(parent: Instance, name: string, color: Color3, zIndex: number): Frame
	local frame = create("Frame", {
		Name = name,
		Active = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Interactable = false,
		Selectable = false,
		Visible = false,
		ZIndex = zIndex,
	}, parent) :: Frame
	create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color,
		Thickness = 2,
	}, frame)
	return frame
end

function PaintCellOverlay.new(parent: Frame): Controller
	local selectedOutline = outline(parent, "SelectedCellOutline", COLORS.accent, 17)
	local hoverOutline = outline(parent, "HoverCellOutline", COLORS.warning, 18)
	local columns = 0
	local rows = 0
	local cellPixels = 22
	local selectedCellKey: string? = nil
	local hoverColumn: number? = nil
	local hoverRow: number? = nil
	local showHover = false
	local showSelection = false

	local function position(target: Frame, column: number?, row: number?, visible: boolean)
		if
			not visible
			or column == nil
			or row == nil
			or column < 1
			or row < 1
			or column > columns
			or row > rows
		then
			target.Visible = false
			return
		end
		target.Position = UDim2.fromOffset(
			CELL_INSET + 1 + (column - 1) * cellPixels,
			CELL_INSET + 1 + (row - 1) * cellPixels
		)
		local size = math.max(cellPixels - 2, 1)
		target.Size = UDim2.fromOffset(size, size)
		target.Visible = true
	end

	local function update()
		position(hoverOutline, hoverColumn, hoverRow, showHover)
		local columnText, rowText =
			if selectedCellKey ~= nil then string.match(selectedCellKey, "^(%d+):(%d+)$") else nil, nil
		position(
			selectedOutline,
			if columnText ~= nil then tonumber(columnText) else nil,
			if rowText ~= nil then tonumber(rowText) else nil,
			showSelection
		)
	end

	local controller: Controller = {} :: any
	controller.clearHover = function(_self: Controller)
		hoverColumn = nil
		hoverRow = nil
		parent:SetAttribute("HoverColumn", nil)
		parent:SetAttribute("HoverRow", nil)
		update()
	end
	controller.setHover = function(_self: Controller, column: number, row: number)
		hoverColumn = column
		hoverRow = row
		parent:SetAttribute("HoverColumn", column)
		parent:SetAttribute("HoverRow", row)
		update()
	end
	controller.hoverCell = function(_self: Controller, pointerPosition: Vector2?): (number?, number?)
		local column = hoverColumn
		local row = hoverRow
		if column == nil or row == nil then
			return nil, nil
		end
		if pointerPosition ~= nil then
			local origin = parent.AbsolutePosition
				+ Vector2.new(CELL_INSET + (column - 1) * cellPixels, CELL_INSET + (row - 1) * cellPixels)
			if
				pointerPosition.X < origin.X
				or pointerPosition.Y < origin.Y
				or pointerPosition.X >= origin.X + cellPixels
				or pointerPosition.Y >= origin.Y + cellPixels
			then
				return nil, nil
			end
		end
		return column, row
	end
	controller.refresh = function(_self: Controller, config: RefreshConfig)
		columns = config.columns
		rows = config.rows
		cellPixels = config.cellPixels
		selectedCellKey = config.selectedCellKey
		showHover = config.showHover
		showSelection = config.showSelection
		update()
	end
	return controller
end

return table.freeze(PaintCellOverlay)
