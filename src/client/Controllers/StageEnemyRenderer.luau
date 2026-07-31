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
local ANIMATION_FOLDER_NAME = "Animations"
local BOSS_FILL_COLOR = Color3.fromRGB(255, 96, 84)
local DEATH_RELEASE_DELAY = 0.45
local DEATH_POOF_PARTICLES = 12
-- Pooled rigs park far below the platforms instead of toggling per-part
-- transparency; the models stay parented so reuse is allocation-free.
local POOL_STORAGE_FRAME = CFrame.new(0, -2048, 0)

type RigAnimations = {
	walk: AnimationTrack?,
	death: AnimationTrack?,
}

type RenderState = {
	model: Model,
	enemyTypeId: string,
	animations: RigAnimations,
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
-- Tracks are bound once per cloned rig and follow the model through the pool.
local animationsByModel: { [Model]: RigAnimations } = {}
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

-- A character asset normally ships its own Humanoid or AnimationController. One
-- is only created when the rig declares animations without a controller, so
-- simple part rigs are never given machinery they do not use.
local function animatorFor(model: Model, required: boolean): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local controller: Instance? = if humanoid ~= nil
		then humanoid
		else model:FindFirstChildOfClass("AnimationController")
	if controller == nil then
		if not required then
			return nil
		end
		local created = Instance.new("AnimationController")
		created.Parent = model
		controller = created
	end
	local existing = controller:FindFirstChildOfClass("Animator")
	if existing ~= nil then
		return existing
	end
	local animator = Instance.new("Animator")
	animator.Parent = controller
	return animator
end

-- An authored id wins; otherwise the rig's own `Animations` folder is used,
-- which is where a designer building the asset naturally puts them. A declared
-- Animation instance is reused as-is so the common case creates nothing, and an
-- override is parented into the rig rather than built and thrown away.
local function animationFor(model: Model, authoredId: string?, childName: string): Animation?
	local declaredFolder = model:FindFirstChild(ANIMATION_FOLDER_NAME)
	local declared = if declaredFolder ~= nil then declaredFolder:FindFirstChild(childName) else nil
	local declaredAnimation = if declared ~= nil and declared:IsA("Animation") then declared else nil
	if type(authoredId) ~= "string" or authoredId == "" then
		return if declaredAnimation ~= nil and declaredAnimation.AnimationId ~= ""
			then declaredAnimation
			else nil
	end
	if declaredAnimation ~= nil then
		declaredAnimation.AnimationId = authoredId
		return declaredAnimation
	end
	local folderInstance = declaredFolder
	if folderInstance == nil then
		local created = Instance.new("Folder")
		created.Name = ANIMATION_FOLDER_NAME
		created.Parent = model
		folderInstance = created
	end
	local animation = Instance.new("Animation")
	animation.Name = childName
	animation.AnimationId = authoredId
	animation.Parent = folderInstance
	return animation
end

local function loadTrack(animator: Animator, animation: Animation): AnimationTrack?
	local loaded, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not loaded or typeof(track) ~= "Instance" then
		warn(`Stagewright enemy animation failed to load: {animation.AnimationId}`)
		return nil
	end
	return track
end

local function bindAnimations(model: Model, definition: StageTypes.EnemyTypeDefinition?): RigAnimations
	local authored = if definition ~= nil then definition.animations else nil
	local walk = animationFor(model, if authored ~= nil then authored.walkId else nil, "Walk")
	local death = animationFor(model, if authored ~= nil then authored.deathId else nil, "Death")
	if walk == nil and death == nil then
		return {}
	end
	local animator = animatorFor(model, true)
	if animator == nil then
		return {}
	end
	local animations: RigAnimations = {}
	if walk ~= nil then
		local walkTrack = loadTrack(animator, walk)
		if walkTrack ~= nil then
			walkTrack.Looped = true
			animations.walk = walkTrack
		end
	end
	if death ~= nil then
		local deathTrack = loadTrack(animator, death)
		if deathTrack ~= nil then
			deathTrack.Looped = false
			animations.death = deathTrack
		end
	end
	return animations
end

local function acquireModel(enemyTypeId: string): (Model?, RigAnimations)
	local pool = modelPools[enemyTypeId]
	if pool ~= nil then
		local pooled = table.remove(pool)
		if pooled ~= nil and pooled.Parent ~= nil then
			-- Tracks belong to the pooled model's own Animator, so reuse costs no
			-- reload; they are only ever bound once per cloned rig.
			return pooled, animationsByModel[pooled] or {}
		end
	end
	local rigs = rigTemplates()
	if rigs == nil then
		return nil, {}
	end
	local definition = definitionFor(enemyTypeId)
	local modelId = if definition ~= nil then definition.modelId else ""
	local template = if modelId ~= "" then rigs:FindFirstChild(modelId) else nil
	if template == nil or not template:IsA("Model") then
		if modelId ~= "" then
			warn(`Stagewright enemy rig {modelId} is missing from EnemyRigs; rendering the fallback`)
		end
		template = rigs:FindFirstChild(FALLBACK_RIG_NAME)
	end
	if template == nil or not template:IsA("Model") then
		return nil, {}
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
	local animations = bindAnimations(model, definition)
	animationsByModel[model] = animations
	return model, animations
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
	local walk = renderState.animations.walk
	if walk ~= nil and walk.IsPlaying then
		walk:Stop(0.1)
	end
	local death = renderState.animations.death
	if death ~= nil then
		death:Play(0.1)
	end
	playDeathPoof(renderState.model)
	task.delay(DEATH_RELEASE_DELAY, function()
		if death ~= nil and death.IsPlaying then
			death:Stop(0)
		end
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
			local model, animations = acquireModel(enemyTypeId)
			if model == nil then
				continue
			end
			local walk = animations.walk
			if walk ~= nil and not walk.IsPlaying then
				walk:Play(0.1)
			end
			local gui, fill = healthBarOf(model)
			local isBoss = enemy.isBoss == true
			if fill ~= nil then
				fill.BackgroundColor3 = if isBoss then BOSS_FILL_COLOR else Color3.fromRGB(77, 217, 102)
			end
			renderState = {
				model = model,
				enemyTypeId = enemyTypeId,
				animations = animations,
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
