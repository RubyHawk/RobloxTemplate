--!strict

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local StageCatalog = require(Shared.StageCatalog)
local StagePath = require(Shared.StagePath)

local WALK_SPEED_STUDS_PER_SECOND = 7
local STEP_FREQUENCY = 8
local STRIDE_RADIANS = 0.38

type NpcParts = {
	root: BasePart,
	body: BasePart,
	head: BasePart,
	leftArm: BasePart,
	rightArm: BasePart,
	leftLeg: BasePart,
	rightLeg: BasePart,
}

local function findPart(parent: Instance, name: string): BasePart?
	local child = parent:FindFirstChild(name)
	return if child ~= nil and child:IsA("BasePart") then child else nil
end

local function collectParts(npc: Model): NpcParts?
	local root = findPart(npc, "Root")
	local body = findPart(npc, "Body")
	local head = findPart(npc, "Head")
	local leftArm = findPart(npc, "LeftArm")
	local rightArm = findPart(npc, "RightArm")
	local leftLeg = findPart(npc, "LeftLeg")
	local rightLeg = findPart(npc, "RightLeg")
	if
		root == nil
		or body == nil
		or head == nil
		or leftArm == nil
		or rightArm == nil
		or leftLeg == nil
		or rightLeg == nil
	then
		return nil
	end
	return {
		root = root,
		body = body,
		head = head,
		leftArm = leftArm,
		rightArm = rightArm,
		leftLeg = leftLeg,
		rightLeg = rightLeg,
	}
end

local function pose(parts: NpcParts, baseCFrame: CFrame, now: number)
	local stride = math.sin(now * STEP_FREQUENCY) * STRIDE_RADIANS
	parts.root.CFrame = baseCFrame
	parts.body.CFrame = baseCFrame * CFrame.new(0, 0.32, 0)
	parts.head.CFrame = baseCFrame * CFrame.new(0, 1.62, 0)
	parts.leftArm.CFrame = baseCFrame * CFrame.new(-0.92, 0.28, 0) * CFrame.Angles(-stride * 0.8, 0, 0)
	parts.rightArm.CFrame = baseCFrame * CFrame.new(0.92, 0.28, 0) * CFrame.Angles(stride * 0.8, 0, 0)
	parts.leftLeg.CFrame = baseCFrame * CFrame.new(-0.34, -0.86, 0) * CFrame.Angles(stride, 0, 0)
	parts.rightLeg.CFrame = baseCFrame * CFrame.new(0.34, -0.86, 0) * CFrame.Angles(-stride, 0, 0)
end

local island = Workspace:FindFirstChild("FirstPrivateIsland")
local platform = if island ~= nil then island:FindFirstChild("GamePlatform") else nil
local base = if platform ~= nil then platform:FindFirstChild("PlatformOrigin") else nil
local npc = if island ~= nil then island:FindFirstChild("GridNpc") else nil
if base == nil or not base:IsA("BasePart") or npc == nil or not npc:IsA("Model") then
	return
end
local parts = collectParts(npc)
local stage = StageCatalog.get(StageCatalog.defaultStageId())
local graph = if stage ~= nil then stage.pathGraphs[stage.pathGraphs and "graph_main"] else nil
local edge = if graph ~= nil then graph.edges.edge_main else nil
if parts == nil or edge == nil or edge.length <= 0 then
	return
end

local startedAt = Workspace:GetServerTimeNow()
RunService.Heartbeat:Connect(function()
	local now = Workspace:GetServerTimeNow()
	local distance = ((now - startedAt) * WALK_SPEED_STUDS_PER_SECOND) % edge.length
	local sample = StagePath.sample(edge.samples, edge.length, distance)
	if sample == nil then
		return
	end
	local position =
		base.CFrame:PointToWorldSpace(Vector3.new(sample.position.x, sample.position.y, sample.position.z))
	local tangent =
		base.CFrame:VectorToWorldSpace(Vector3.new(sample.tangent.x, sample.tangent.y, sample.tangent.z))
	local up = base.CFrame:VectorToWorldSpace(Vector3.new(sample.up.x, sample.up.y, sample.up.z))
	local bob = math.sin(now * STEP_FREQUENCY * 2) * 0.04
	pose(parts, CFrame.lookAt(position, position + tangent, up) + up * bob, now)
end)
