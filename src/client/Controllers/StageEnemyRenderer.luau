--!strict

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Template = game:GetService("ReplicatedStorage"):WaitForChild("Template")
local Shared = Template:WaitForChild("Shared")
local StageCatalog = require(Shared.StageCatalog)
local StagePath = require(Shared.StagePath)
local StageTypes = require(Shared.StageTypes)

local StageEnemyRenderer = {}

local FALLBACK_RIG_NAME = "Fallback"
local BOSS_FILL_COLOR = Color3.fromRGB(255, 96, 84)
local DEATH_RELEASE_DELAY = 0.45
local DEATH_POOF_PARTICLES = 12
-- Pooled rigs park far below the platforms instead of toggling per-part
-- transparency; the models stay parented so reuse is allocation-free.
local POOL_STORAGE_FRAME = CFrame.new(0, -2048, 0)

type RenderState = {
	model: Model,
	enemyTypeId: string,
	healthGui: BillboardGui?,
	healthFill: Frame?,
	healthFraction: number,
	isBoss: boolean,
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
-- Pool key is the enemy type id (not the rig template name) so tint and
-- render scale applied at clone time always match the pooled model.
local modelPools: { [string]: { Model } } = {}
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

local function rigTemplates(): Folder?
	local rigs = Template:FindFirstChild("EnemyRigs")
	return if rigs ~= nil and rigs:IsA("Folder") then rigs else nil
end

local function bodyOf(model: Model): BasePart?
	local body = model:FindFirstChild("Body")
	return if body ~= nil and body:IsA("BasePart") then body else nil
end

local function healthBarOf(model: Model): (BillboardGui?, Frame?)
	local body = bodyOf(model)
	local gui = if body ~= nil then body:FindFirstChild("HealthBar") else nil
	if gui == nil or not gui:IsA("BillboardGui") then
		return nil, nil
	end
	local back = gui:FindFirstChild("Back")
	local fill = if back ~= nil then back:FindFirstChild("Fill") else nil
	return gui, if fill ~= nil and fill:IsA("Frame") then fill else nil
end

local function definitionFor(enemyTypeId: string): StageTypes.EnemyTypeDefinition?
	if enemyTypeId == "" then
		return nil
	end
	return StageCatalog.enemyType(enemyTypeId)
end

local function acquireModel(enemyTypeId: string): Model?
	local pool = modelPools[enemyTypeId]
	if pool ~= nil then
		local pooled = table.remove(pool)
		if pooled ~= nil and pooled.Parent ~= nil then
			return pooled
		end
	end
	local rigs = rigTemplates()
	if rigs == nil then
		return nil
	end
	local definition = definitionFor(enemyTypeId)
	local modelId = if definition ~= nil then definition.modelId else ""
	local template = if modelId ~= "" then rigs:FindFirstChild(modelId) else nil
	if template == nil or not template:IsA("Model") then
		template = rigs:FindFirstChild(FALLBACK_RIG_NAME)
	end
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	local renderScale = if definition ~= nil then math.clamp(definition.renderScale, 0.1, 10) else 1
	if renderScale ~= 1 then
		model:ScaleTo(renderScale)
	end
	local tint = if definition ~= nil then definition.tint else nil
	local body = bodyOf(model)
	if body ~= nil and tint ~= nil then
		body.Color = Color3.new(math.clamp(tint.r, 0, 1), math.clamp(tint.g, 0, 1), math.clamp(tint.b, 0, 1))
	end
	local gui = healthBarOf(model)
	if gui ~= nil and renderScale ~= 1 then
		-- ScaleTo does not scale billboard offsets; keep the bar above the rig.
		gui.StudsOffset = Vector3.new(0, gui.StudsOffset.Y * renderScale, 0)
	end
	model:PivotTo(POOL_STORAGE_FRAME)
	model.Parent = renderFolder()
	return model
end

local function releaseModel(enemyTypeId: string, model: Model)
	if model.Parent == nil then
		return
	end
	model:PivotTo(POOL_STORAGE_FRAME)
	local pool = modelPools[enemyTypeId]
	if pool == nil then
		pool = {}
		modelPools[enemyTypeId] = pool
	end
	table.insert(pool, model)
end

local function playDeathPoof(model: Model)
	local body = bodyOf(model)
	local attachment = if body ~= nil then body:FindFirstChild("DeathPoofAttachment") else nil
	local emitter = if attachment ~= nil then attachment:FindFirstChild("DeathPoof") else nil
	if emitter ~= nil and emitter:IsA("ParticleEmitter") then
		emitter:Emit(DEATH_POOF_PARTICLES)
	end
end

local function retire(renderState: RenderState)
	local gui = renderState.healthGui
	if gui ~= nil then
		gui.Enabled = false
	end
	-- The rig freezes in place for the poof, then returns to its pool. The
	-- model cannot be reused early because only releaseModel repools it.
	playDeathPoof(renderState.model)
	task.delay(DEATH_RELEASE_DELAY, function()
		releaseModel(renderState.enemyTypeId, renderState.model)
	end)
end

local function vector(value: any): Vector3
	return Vector3.new(value.x, value.y, value.z)
end

local function render(renderState: RenderState)
	local stage = StageCatalog.get(renderState.stageId)
	local graph = if stage ~= nil then stage.pathGraphs[renderState.graphId] else nil
	local edge = if graph ~= nil then graph.edges[renderState.edgeId] else nil
	if edge == nil then
		renderState.model:PivotTo(POOL_STORAGE_FRAME)
		return
	end
	local elapsed = math.max(Workspace:GetServerTimeNow() - renderState.serverTime, 0)
	local distance = math.min(renderState.edgeDistance + renderState.speed * elapsed, edge.length)
	local sample = StagePath.sample(edge.samples, edge.length, distance)
	if sample == nil then
		renderState.model:PivotTo(POOL_STORAGE_FRAME)
		return
	end
	local origin = renderState.origin
	local position = origin:PointToWorldSpace(vector(sample.position))
	local tangent = origin:VectorToWorldSpace(vector(sample.tangent))
	local up = origin:VectorToWorldSpace(vector(sample.up))
	local frame = CFrame.lookAt(position, position + tangent, up)
	local laneProfile = graph.laneProfiles[edge.laneProfileId]
	local laneOffset = if laneProfile ~= nil then laneProfile.offsets[renderState.laneIndex] or 0 else 0
	renderState.model:PivotTo(frame + frame.RightVector * laneOffset)
end

local function applyHealth(renderState: RenderState, health: any, maxHealth: any)
	if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		return
	end
	local fraction = math.clamp(health / maxHealth, 0, 1)
	renderState.healthFraction = fraction
	local fill = renderState.healthFill
	if fill ~= nil then
		fill.Size = UDim2.fromScale(fraction, 1)
	end
	local gui = renderState.healthGui
	if gui ~= nil then
		gui.Enabled = fraction < 1
	end
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
			local enemyTypeId = if type(enemy.enemyTypeId) == "string" then enemy.enemyTypeId else ""
			local model = acquireModel(enemyTypeId)
			if model == nil then
				continue
			end
			local gui, fill = healthBarOf(model)
			local isBoss = enemy.isBoss == true
			if fill ~= nil then
				fill.BackgroundColor3 = if isBoss then BOSS_FILL_COLOR else Color3.fromRGB(77, 217, 102)
			end
			renderState = {
				model = model,
				enemyTypeId = enemyTypeId,
				healthGui = gui,
				healthFill = fill,
				healthFraction = 1,
				isBoss = isBoss,
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
		applyHealth(renderState, enemy.health, enemy.maxHealth)
	end
	for enemyId, renderState in states do
		if not seen[enemyId] then
			retire(renderState)
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
