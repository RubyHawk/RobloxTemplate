--!strict

local GraphOperations = if script ~= nil
	then require(script.Parent.Parent.Graph.Operations)
	else require("../Graph/Operations")

export type Config = {
	currentGraph: () -> any?,
	sourceNodeId: () -> string?,
	setSourceNodeId: (string?) -> (),
	mutate: (string, () -> ()) -> boolean,
	select: (string?, string?) -> (),
	setStatus: (string, boolean?) -> (),
	finishTool: () -> (),
	render: () -> (),
}

export type Controller = {
	beginSource: (Controller, string) -> boolean,
	activateNode: (Controller, string) -> boolean?,
	connectNodes: (Controller, string, string) -> boolean?,
	splitEdge: (Controller, string) -> boolean,
}

local GraphToolController = {}

function GraphToolController.new(config: Config): Controller
	local controller: Controller = {} :: any

	local function armSource(nodeId: string, render: boolean): boolean
		local graph = config.currentGraph()
		local node = if graph ~= nil then graph.nodes[nodeId] else nil
		if node == nil then
			config.setSourceNodeId(nil)
			config.setStatus("That route node is no longer available.", true)
			return false
		end
		if node.kind == "Goal" then
			config.setSourceNodeId(nil)
			config.setStatus("Goal nodes cannot start a route connection.", true)
			return false
		end
		config.setSourceNodeId(nodeId)
		config.select(nodeId, nil)
		config.setStatus("Start selected. Click the destination node; Escape cancels.")
		if render then
			config.render()
		end
		return true
	end

	controller.beginSource = function(_self: Controller, nodeId: string): boolean
		return armSource(nodeId, true)
	end

	controller.activateNode = function(self: Controller, nodeId: string): boolean?
		local graph = config.currentGraph()
		local sourceNodeId = config.sourceNodeId()
		local sourceNode = if graph ~= nil and sourceNodeId ~= nil then graph.nodes[sourceNodeId] else nil
		if sourceNodeId ~= nil and (sourceNode == nil or sourceNode.kind == "Goal") then
			config.setSourceNodeId(nil)
			sourceNodeId = nil
		end

		local node = if graph ~= nil then graph.nodes[nodeId] else nil
		if node == nil then
			config.setStatus("That route node is no longer available.", true)
			return nil
		end
		if sourceNodeId == nil then
			return if self:beginSource(nodeId) then false else nil
		end
		if sourceNodeId == nodeId then
			config.setStatus("Choose a different destination node.", true)
			return nil
		end
		if not GraphOperations.canConnect(graph, sourceNodeId, nodeId) then
			config.setStatus("Those route nodes cannot be connected in that direction.", true)
			return nil
		end

		local edgeId: string? = nil
		local committed = config.mutate("Connect Stagewright route nodes", function()
			edgeId = GraphOperations.connect(graph, sourceNodeId, nodeId)
		end)
		if not committed or edgeId == nil then
			config.setStatus("The route connection could not be created.", true)
			return nil
		end
		config.setSourceNodeId(nil)
		config.select(nil, edgeId)
		config.setStatus("Directed spline created. Select it to adjust lanes.")
		config.finishTool()
		config.render()
		return true
	end

	controller.connectNodes = function(self: Controller, fromNodeId: string, toNodeId: string): boolean?
		if not armSource(fromNodeId, false) then
			return nil
		end
		return self:activateNode(toNodeId)
	end

	controller.splitEdge = function(_self: Controller, edgeId: string): boolean
		local graph = config.currentGraph()
		if graph == nil or graph.edges[edgeId] == nil then
			config.setStatus("That spline is no longer available.", true)
			return false
		end
		local splitNodeId: string? = nil
		local committed = config.mutate("Split Stagewright graph edge", function()
			splitNodeId = GraphOperations.splitEdge(graph, edgeId)
		end)
		if not committed or splitNodeId == nil then
			config.setStatus("The spline could not be split.", true)
			return false
		end
		config.select(splitNodeId, nil)
		config.setStatus("Spline split at its midpoint. Drag the new junction to refine both curves.")
		config.finishTool()
		config.render()
		return true
	end

	return controller
end

return table.freeze(GraphToolController)
