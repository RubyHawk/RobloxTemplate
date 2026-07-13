--!strict

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local StageCatalog = require(Shared.StageCatalog)
local StageGraph = require(Shared.StageGraph)
local StagePath = require(Shared.StagePath)
local StageSchema = require(Shared.StageSchema)

local ProfileService = require(script.Parent.ProfileService)

local StageRuntimeService = {}

export type RouteContext = StageGraph.Context

type UpgradeLevelProvider = (player: Player, upgradeId: string) -> number
type StageOriginProvider = (player: Player, stageId: string) -> CFrame
type StageAvailabilityProvider = (player: Player) -> boolean

local activeStageIds: { [Player]: string } = {}
local upgradeLevelProvider: UpgradeLevelProvider = function(_player: Player, _upgradeId: string): number
	return 0
end
local originProvider: StageOriginProvider? = nil
local availabilityProvider: StageAvailabilityProvider = function(_player: Player): boolean
	return true
end

local function stageById(stageId: string): any?
	return StageCatalog.get(stageId)
end

local function defaultPlatformOrigin(): BasePart?
	local island = Workspace:FindFirstChild(Config.towerDefense.firstPlatformIslandName)
	local platform = if island ~= nil
		then island:FindFirstChild(Config.towerDefense.platformModelName)
		else nil
	local origin = if platform ~= nil
		then platform:FindFirstChild(Config.towerDefense.platformOriginName)
		else nil
	if origin ~= nil and origin:IsA("BasePart") then
		return origin
	end
	local base = if platform ~= nil then platform:FindFirstChild("PlatformBase") else nil
	return if base ~= nil and base:IsA("BasePart") then base else nil
end

function StageRuntimeService.originFor(player: Player, stage: any): CFrame
	if originProvider ~= nil then
		return originProvider(player, stage.id)
	end
	local origin = defaultPlatformOrigin()
	return if origin ~= nil then origin.CFrame else CFrame.new()
end

function StageRuntimeService.hasPlatform(player: Player): boolean
	return availabilityProvider(player)
end

local function profileProgress(player: Player): ({ [string]: any }, { [string]: number })
	local profile = ProfileService.get(player)
	if profile == nil then
		return {}, {}
	end
	return profile.towerDefense.stageProgress, profile.currencies
end

local function unlockedStages(player: Player): { [string]: boolean }
	local progress = profileProgress(player)
	local unlocked: { [string]: boolean } = {}
	for stageId, state in progress do
		unlocked[stageId] = type(state) == "table" and state.unlocked == true
	end
	return unlocked
end

local function requirementsPass(player: Player, stage: any): boolean
	local progress, currencies = profileProgress(player)
	for _, requirement in stage.unlockRequirements or {} do
		if requirement.kind == "StageUnlocked" then
			local state = progress[requirement.stageId]
			if type(state) ~= "table" or state.unlocked ~= true then
				return false
			end
		elseif requirement.kind == "CurrencyAtLeast" then
			if (currencies[requirement.currencyId] or 0) < requirement.amount then
				return false
			end
		elseif requirement.kind == "UpgradeLevelAtLeast" then
			if upgradeLevelProvider(player, requirement.upgradeId) < requirement.level then
				return false
			end
		end
	end
	return true
end

function StageRuntimeService.isUnlocked(player: Player, stageId: string): boolean
	local stage = stageById(stageId)
	if stage == nil then
		return false
	end
	if stageId == Config.towerDefense.startingStageId then
		return true
	end
	local progress = profileProgress(player)
	local state = progress[stageId]
	return type(state) == "table" and state.unlocked == true and requirementsPass(player, stage)
end

function StageRuntimeService.activate(player: Player, stageId: any): (boolean, string)
	if type(stageId) ~= "string" or #stageId > 80 or stageById(stageId) == nil then
		return false, "Unknown stage"
	end
	if not StageRuntimeService.isUnlocked(player, stageId) then
		return false, "Stage is locked"
	end
	local profile = ProfileService.get(player)
	if profile == nil then
		return false, "Profile is not loaded"
	end
	activeStageIds[player] = stageId
	profile.towerDefense.selectedStageId = stageId
	ProfileService.markDirty(player, "towerDefense:activateStage")
	return true, `Activated {stageById(stageId).name}`
end

function StageRuntimeService.activeStageId(player: Player): string
	local active = activeStageIds[player]
	if active ~= nil and stageById(active) ~= nil and StageRuntimeService.isUnlocked(player, active) then
		return active
	end
	local profile = ProfileService.get(player)
	local selected = if profile ~= nil then profile.towerDefense.selectedStageId else ""
	if selected ~= "" and stageById(selected) ~= nil and StageRuntimeService.isUnlocked(player, selected) then
		activeStageIds[player] = selected
		return selected
	end
	activeStageIds[player] = Config.towerDefense.startingStageId
	return Config.towerDefense.startingStageId
end

function StageRuntimeService.activeStage(player: Player): any
	return stageById(StageRuntimeService.activeStageId(player))
end

function StageRuntimeService.firstGraph(stage: any): any?
	local ids: { string } = {}
	for graphId in stage.pathGraphs do
		table.insert(ids, graphId)
	end
	table.sort(ids)
	return if ids[1] ~= nil then stage.pathGraphs[ids[1]] else nil
end

function StageRuntimeService.spawnNodes(graph: any): { any }
	local ids: { string } = {}
	for nodeId, node in graph.nodes do
		if node.kind == "Spawn" then
			table.insert(ids, nodeId)
		end
	end
	table.sort(ids)
	local nodes: { any } = {}
	for _, nodeId in ids do
		table.insert(nodes, graph.nodes[nodeId])
	end
	return nodes
end

function StageRuntimeService.firstSpawnNode(graph: any): any?
	return StageRuntimeService.spawnNodes(graph)[1]
end

function StageRuntimeService.context(
	player: Player,
	wave: number,
	enemyTags: { string },
	nodeVisits: { [string]: number },
	stageFlags: { [string]: boolean }?
): RouteContext
	local tags: { [string]: boolean } = {}
	for _, tag in enemyTags do
		tags[tag] = true
	end
	local upgrades: { [string]: number } = {}
	local stage = StageRuntimeService.activeStage(player)
	for _, graph in stage.pathGraphs do
		for _, edge in graph.edges do
			for _, predicate in edge.predicates do
				if predicate.kind == "UpgradeLevelAtLeast" then
					upgrades[predicate.upgradeId] = upgradeLevelProvider(player, predicate.upgradeId)
				end
			end
		end
	end
	local profile = ProfileService.get(player)
	return {
		wave = wave,
		stageFlags = stageFlags or {},
		enemyTags = tags,
		nodeVisits = nodeVisits,
		unlockedStages = unlockedStages(player),
		upgradeLevels = upgrades,
		currencies = if profile ~= nil then profile.currencies else {},
	}
end

function StageRuntimeService.chooseEdge(graph: any, nodeId: string, context: RouteContext): (any?, string?)
	return StageGraph.chooseEdge(graph, nodeId, context)
end

local function vector(value: any): Vector3
	return Vector3.new(value.x, value.y, value.z)
end

function StageRuntimeService.sampleEdge(
	player: Player,
	_stage: any,
	graph: any,
	edgeId: string,
	distance: number,
	laneIndex: number
): (CFrame?, any?)
	local edge = graph.edges[edgeId]
	if edge == nil then
		return nil, nil
	end
	local sample = StagePath.sample(edge.samples, edge.length, distance)
	if sample == nil then
		return nil, nil
	end
	local origin = StageRuntimeService.originFor(player, _stage)
	local worldPosition = origin:PointToWorldSpace(vector(sample.position))
	local worldTangent = origin:VectorToWorldSpace(vector(sample.tangent))
	local worldUp = origin:VectorToWorldSpace(vector(sample.up))
	local frame = CFrame.lookAt(worldPosition, worldPosition + worldTangent, worldUp)
	local laneProfile = graph.laneProfiles[edge.laneProfileId]
	local laneOffset = if laneProfile ~= nil then laneProfile.offsets[laneIndex] or 0 else 0
	frame += frame.RightVector * laneOffset
	return frame, sample
end

function StageRuntimeService.cell(stage: any, column: number, row: number): any
	local key = StageSchema.cellKey(column, row)
	return stage.grid.cells[key] or stage.grid.defaultCell
end

function StageRuntimeService.isBuildable(stage: any, column: number, row: number): boolean
	if column < 1 or column > stage.grid.columns or row < 1 or row > stage.grid.rows then
		return false
	end
	local cell = StageRuntimeService.cell(stage, column, row)
	local routeMask = stage.routeNoBuildMask or {}
	if routeMask[StageSchema.cellKey(column, row)] == true then
		return false
	end
	return cell.buildPolicy == nil or cell.buildPolicy == "Allowed" or cell.buildPolicy == "AutoOnly"
end

function StageRuntimeService.cellsWithRole(stage: any, role: string): { { column: number, row: number } }
	local cells: { { column: number, row: number } } = {}
	for key, cell in stage.grid.cells do
		if cell.roles ~= nil and cell.roles[role] == true then
			local columnText, rowText = string.match(key, "^(%d+):(%d+)$")
			if columnText ~= nil and rowText ~= nil then
				table.insert(
					cells,
					{ column = tonumber(columnText) :: number, row = tonumber(rowText) :: number }
				)
			end
		end
	end
	table.sort(cells, function(left, right)
		return if left.row == right.row then left.column < right.column else left.row < right.row
	end)
	return cells
end

function StageRuntimeService.cellWorldPosition(
	player: Player,
	stage: any,
	column: number,
	row: number,
	verticalOffset: number
): Vector3
	local grid = stage.grid
	local localX = -(grid.columns * grid.cellSize) / 2 + (column - 0.5) * grid.cellSize
	local localZ = -(grid.rows * grid.cellSize) / 2 + (row - 0.5) * grid.cellSize
	return StageRuntimeService.originFor(player, stage)
		:PointToWorldSpace(Vector3.new(localX, verticalOffset, localZ))
end

function StageRuntimeService.start(options: {
	upgradeLevel: UpgradeLevelProvider?,
	origin: StageOriginProvider?,
	available: StageAvailabilityProvider?,
}?)
	if options ~= nil and options.upgradeLevel ~= nil then
		upgradeLevelProvider = options.upgradeLevel
	end
	if options ~= nil and options.origin ~= nil then
		originProvider = options.origin
	end
	if options ~= nil and options.available ~= nil then
		availabilityProvider = options.available
	end
end

function StageRuntimeService.forget(player: Player)
	activeStageIds[player] = nil
end

return StageRuntimeService
