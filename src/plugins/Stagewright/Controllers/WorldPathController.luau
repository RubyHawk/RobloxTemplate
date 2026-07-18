--!strict

local StageTypes = require(script.Parent.Parent.Shared.StageTypes)
local WorldPathView = require(script.Parent.Parent.WorldPathView)
local WorldPathEditSession = require(script.Parent.WorldPathEditSession)

type PathGraphDefinition = StageTypes.PathGraphDefinition
type StageDefinition = StageTypes.StageDefinition
type StagePreviewDefinition = StageTypes.StagePreviewDefinition

export type Option = "AssetPreview" | "Lanes" | "BuildMask" | "Conflicts"

export type RenderState = {
	stage: StageDefinition?,
	graph: PathGraphDefinition?,
	preview: StagePreviewDefinition?,
	selectedNodeId: string?,
	selectedEdgeId: string?,
	tracedEdgeIds: { [string]: boolean },
}

export type Config = {
	parent: Instance,
	theme: WorldPathView.Theme,
	currentPreview: () -> StagePreviewDefinition?,
	beginEdit: (label: string) -> number?,
	finishEdit: (transaction: number, commit: boolean) -> boolean,
	applyNode: (nodeId: string, position: WorldPathEditSession.Vec3) -> boolean,
	applyHandle: (
		edgeId: string,
		handleId: WorldPathEditSession.HandleId,
		offset: WorldPathEditSession.Vec3
	) -> boolean,
	cancelActiveInteraction: () -> (),
	reportBlocked: (action: string) -> (),
	onCommitted: () -> (),
	onFailed: (action: string) -> (),
	selectNode: (nodeId: string) -> (),
	selectEdge: (edgeId: string) -> (),
	setLanes: (edgeId: string, laneCount: number) -> (),
	focusWorld: (edgeId: string?) -> (),
	testSegment: (edgeId: string) -> (),
}

export type Controller = {
	render: (self: Controller, state: RenderState) -> (),
	getOption: (self: Controller, option: Option) -> boolean,
	toggleOption: (self: Controller, option: Option) -> (),
	fitToView: (self: Controller) -> (),
	cancelInteraction: (self: Controller) -> boolean,
	destroy: (self: Controller) -> (),
}

local WorldPathController = {}

function WorldPathController.new(config: Config): Controller
	local view: WorldPathView.Controller
	local editSession = WorldPathEditSession.new({
		beginEdit = config.beginEdit,
		finishEdit = config.finishEdit,
		applyNode = config.applyNode,
		applyHandle = config.applyHandle,
		currentPreview = config.currentPreview,
		onPreview = function(preview: any?)
			view.preview = preview
		end,
		reportBlocked = config.reportBlocked,
		onCommitted = config.onCommitted,
		onFailed = config.onFailed,
	})

	view = WorldPathView.new(config.parent, config.theme, {
		cancelInteraction = config.cancelActiveInteraction,
		selectNode = config.selectNode,
		selectEdge = config.selectEdge,
		moveNode = function(nodeId: string, position: any, finished: boolean)
			editSession:moveNode(nodeId, {
				x = position.x,
				y = position.y,
				z = position.z,
			}, finished)
		end,
		moveHandle = function(edgeId: string, handleId: string, offset: any, finished: boolean)
			if handleId ~= "Out" and handleId ~= "In" then
				return
			end
			local resolvedHandleId = handleId :: WorldPathEditSession.HandleId
			editSession:moveHandle(edgeId, resolvedHandleId, {
				x = offset.x,
				y = offset.y,
				z = offset.z,
			}, finished)
		end,
		setLanes = config.setLanes,
		focusWorld = config.focusWorld,
		testSegment = config.testSegment,
	})

	local controller: Controller = {} :: any
	controller.render = function(_self: Controller, state: RenderState)
		view:render(
			state.stage,
			state.graph,
			state.preview,
			state.selectedNodeId,
			state.selectedEdgeId,
			state.tracedEdgeIds
		)
	end
	controller.getOption = function(_self: Controller, option: Option): boolean
		if option == "AssetPreview" then
			return view.assetPreview
		elseif option == "Lanes" then
			return view.showLanes
		elseif option == "BuildMask" then
			return view.showBuildMask
		end
		return view.showConflicts
	end
	controller.toggleOption = function(self: Controller, option: Option)
		local enabled = not self:getOption(option)
		if option == "AssetPreview" then
			view.assetPreview = enabled
		elseif option == "Lanes" then
			view.showLanes = enabled
		elseif option == "BuildMask" then
			view.showBuildMask = enabled
		else
			view.showConflicts = enabled
		end
		view:rerender()
	end
	controller.fitToView = function(_self: Controller)
		view:fitToView()
	end
	controller.cancelInteraction = function(_self: Controller): boolean
		local canceled = editSession:cancel()
		return view:cancelInteraction() or canceled
	end
	controller.destroy = function(self: Controller)
		self:cancelInteraction()
		view:destroy()
	end
	return controller
end

return table.freeze(WorldPathController)
