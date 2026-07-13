--!strict

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local StageCatalog = require(Shared.StageCatalog)
local StagePath = require(Shared.StagePath)

local StageEnemyRenderer = {}

type RenderState = {
	part: BasePart,
	stageId: string,
	graphId: string,
	edgeId: string,
	edgeDistance: number,
	speed: number,
	laneIndex: number,
	serverTime: number,
	origin: CFrame,
}

local states: { [string]: RenderState } = {}
local partPool: { BasePart } = {}
local folder: Folder? = nil
local initialized = false

local function renderFolder(): Folder
	if folder ~= nil and folder.Parent ~= nil then
		return folder
	end
	local nextFolder = Instance.new("Folder")
	nextFolder.Name = "StagewrightClientEnemies"
	nextFolder.Parent = Workspace
	folder = nextFolder
	return nextFolder
end

local function createPart(enemyId: string): BasePart
	local pooled = table.remove(partPool)
	if pooled ~= nil then
		pooled.Name = enemyId
		pooled.Transparency = 0
		return pooled
	end
	local part = Instance.new("Part")
	part.Name = enemyId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.4, 1.4, 1.4)
	part.Color = Color3.fromRGB(95, 57, 35)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = renderFolder()
	return part
end

local function releasePart(part: BasePart)
	part.Transparency = 1
	part.Name = "PooledEnemy"
	table.insert(partPool, part)
end

local function vector(value: any): Vector3
	return Vector3.new(value.x, value.y, value.z)
end

local function render(renderState: RenderState)
	local stage = StageCatalog.get(renderState.stageId)
	local graph = if stage ~= nil then stage.pathGraphs[renderState.graphId] else nil
	local edge = if graph ~= nil then graph.edges[renderState.edgeId] else nil
	if edge == nil then
		renderState.part.Transparency = 1
		return
	end
	local elapsed = math.max(Workspace:GetServerTimeNow() - renderState.serverTime, 0)
	local distance = math.min(renderState.edgeDistance + renderState.speed * elapsed, edge.length)
	local sample = StagePath.sample(edge.samples, edge.length, distance)
	if sample == nil then
		renderState.part.Transparency = 1
		return
	end
	local origin = renderState.origin
	local position = origin:PointToWorldSpace(vector(sample.position))
	local tangent = origin:VectorToWorldSpace(vector(sample.tangent))
	local up = origin:VectorToWorldSpace(vector(sample.up))
	local frame = CFrame.lookAt(position, position + tangent, up)
	local laneProfile = graph.laneProfiles[edge.laneProfileId]
	local laneOffset = if laneProfile ~= nil then laneProfile.offsets[renderState.laneIndex] or 0 else 0
	renderState.part.CFrame = frame + frame.RightVector * laneOffset
	renderState.part.Transparency = 0
end

function StageEnemyRenderer.apply(snapshot: any?)
	local seen: { [string]: boolean } = {}
	for _, enemy in if snapshot ~= nil and type(snapshot.enemies) == "table" then snapshot.enemies else {} do
		if
			type(enemy.id) ~= "string"
			or type(enemy.stageId) ~= "string"
			or type(enemy.graphId) ~= "string"
			or type(enemy.edgeId) ~= "string"
			or type(enemy.edgeDistance) ~= "number"
			or type(enemy.speed) ~= "number"
		then
			continue
		end
		seen[enemy.id] = true
		local renderState = states[enemy.id]
		if renderState == nil then
			renderState = {
				part = createPart(enemy.id),
				stageId = enemy.stageId,
				graphId = enemy.graphId,
				edgeId = enemy.edgeId,
				edgeDistance = enemy.edgeDistance,
				speed = enemy.speed,
				laneIndex = enemy.laneIndex or 1,
				serverTime = enemy.serverTime or Workspace:GetServerTimeNow(),
				origin = if typeof(snapshot.stageOrigin) == "CFrame"
					then snapshot.stageOrigin
					else CFrame.new(),
			}
			states[enemy.id] = renderState
		else
			renderState.stageId = enemy.stageId
			renderState.graphId = enemy.graphId
			renderState.edgeId = enemy.edgeId
			renderState.edgeDistance = enemy.edgeDistance
			renderState.speed = enemy.speed
			renderState.laneIndex = enemy.laneIndex or 1
			renderState.serverTime = enemy.serverTime or Workspace:GetServerTimeNow()
			renderState.origin = if typeof(snapshot.stageOrigin) == "CFrame"
				then snapshot.stageOrigin
				else CFrame.new()
		end
	end
	for enemyId, renderState in states do
		if not seen[enemyId] then
			releasePart(renderState.part)
			states[enemyId] = nil
		end
	end
end

function StageEnemyRenderer.initialize()
	if initialized then
		return
	end
	initialized = true
	RunService.RenderStepped:Connect(function()
		for _, renderState in states do
			render(renderState)
		end
	end)
end

return StageEnemyRenderer
