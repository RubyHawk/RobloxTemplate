--!strict

local Factory = require(script.Parent.Factory)
local Theme = require(script.Parent.Theme)

local COLORS = Theme.colors
local button = Factory.button
local create = Factory.create
local setButtonSelected = Factory.setSelected

local HierarchyBrowserView = {}

export type Config = {
	list: ScrollingFrame,
	onSelectMap: (representativeLevelId: string) -> (),
	onSelectStage: (representativeLevelId: string) -> (),
	onSelectLevel: (levelId: string) -> (),
}

export type RenderState = {
	hierarchy: any,
	query: string,
	selectedLevelId: string,
	mapPropertiesVisible: boolean,
	issues: { any },
}

export type Controller = {
	render: (self: Controller, state: RenderState) -> (),
}

local function contains(haystack: string, needle: string): boolean
	return needle == "" or string.find(string.lower(haystack), needle, 1, true) ~= nil
end

function HierarchyBrowserView.new(config: Config): Controller
	local controller: Controller = {} :: any
	controller.render = function(_self: Controller, state: RenderState)
		for _, child in config.list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local query = string.lower(state.query)
		local layoutOrder = 0
		local canvasHeight = 14
		for _, mapItem in state.hierarchy.maps do
			local mapMatches = contains(`{mapItem.name} {mapItem.id}`, query)
			local visibleStages: { any } = {}
			for _, stageItem in mapItem.stages do
				local stageMatches = mapMatches or contains(`stage {stageItem.number} {stageItem.id}`, query)
				local visibleLevels: { any } = {}
				for _, levelItem in stageItem.levels do
					if
						stageMatches
						or contains(`level {levelItem.number} {levelItem.name} {levelItem.id}`, query)
					then
						table.insert(visibleLevels, levelItem)
					end
				end
				if #visibleLevels > 0 then
					table.insert(visibleStages, { item = stageItem, levels = visibleLevels })
				end
			end
			if #visibleStages == 0 then
				continue
			end
			layoutOrder += 1
			local mapButton = button(config.list, `v  {mapItem.name}`, 200, function()
				config.onSelectMap(mapItem.representativeLevelId)
			end)
			mapButton.LayoutOrder = layoutOrder
			mapButton.Size = UDim2.new(1, -8, 0, 30)
			mapButton.Font = Enum.Font.BuilderSansBold
			mapButton.TextXAlignment = Enum.TextXAlignment.Left
			create("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 8) }, mapButton)
			setButtonSelected(
				mapButton,
				state.hierarchy.selectedMapId == mapItem.id and state.mapPropertiesVisible
			)
			canvasHeight += 35
			for _, visibleStage in visibleStages do
				local stageItem = visibleStage.item
				layoutOrder += 1
				local stageButton = button(config.list, `v  Stage {stageItem.number}`, 200, function()
					config.onSelectStage(stageItem.representativeLevelId)
				end)
				stageButton.LayoutOrder = layoutOrder
				stageButton.Size = UDim2.new(1, -12, 0, 27)
				stageButton.TextXAlignment = Enum.TextXAlignment.Left
				create(
					"UIPadding",
					{ PaddingLeft = UDim.new(0, 17), PaddingRight = UDim.new(0, 8) },
					stageButton
				)
				if
					state.hierarchy.selectedStageGroupId == stageItem.id and not state.mapPropertiesVisible
				then
					stageButton.BackgroundColor3 = COLORS.surface
				end
				canvasHeight += 32
				for _, level in visibleStage.levels do
					layoutOrder += 1
					local levelId = level.id
					local levelButton = button(
						config.list,
						`Level {level.number}  {level.name}`,
						200,
						function()
							config.onSelectLevel(levelId)
						end
					)
					levelButton.LayoutOrder = layoutOrder
					levelButton.Size = UDim2.new(1, -12, 0, 28)
					levelButton.TextXAlignment = Enum.TextXAlignment.Left
					create(
						"UIPadding",
						{ PaddingLeft = UDim.new(0, 30), PaddingRight = UDim.new(0, 18) },
						levelButton
					)
					setButtonSelected(levelButton, levelId == state.selectedLevelId)
					local hasError = false
					local hasWarning = false
					local issueCount = 0
					for _, issue in state.issues do
						if issue.stageId == levelId then
							issueCount += 1
							hasError = hasError or issue.severity == "Error"
							hasWarning = hasWarning or issue.severity ~= "Error"
						end
					end
					levelButton.Text = `Level {level.number}  {level.name}{if issueCount > 0
						then `  ({issueCount})`
						else ""}`
					local statusDot = create("Frame", {
						AnchorPoint = Vector2.new(1, 0.5),
						BackgroundColor3 = if hasError
							then COLORS.danger
							elseif hasWarning then COLORS.warning
							else COLORS.success,
						BorderSizePixel = 0,
						Position = UDim2.new(1, -8, 0.5, 0),
						Size = UDim2.fromOffset(7, 7),
					}, levelButton) :: Frame
					create("UICorner", { CornerRadius = UDim.new(1, 0) }, statusDot)
					canvasHeight += 33
				end
			end
		end
		config.list.CanvasSize = UDim2.fromOffset(0, canvasHeight)
	end
	return controller
end

return table.freeze(HierarchyBrowserView)
