--!strict

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ISLAND_NAME = "FirstPrivateIsland"
local NPC_NAME = "GridNpc"
local PLATFORM_NAME = "GamePlatform"
local PATH_POINTS_NAME = "PathPoints"
local WALK_SPEED_STUDS_PER_SECOND = 7
local NPC_VERTICAL_OFFSET = 1.45
local STEP_FREQUENCY = 8
local STRIDE_RADIANS = 0.38
local SPLINE_SAMPLES_PER_SEGMENT = 18

type NpcParts = {
	root: BasePart,
	body: BasePart,
	head: BasePart,
	leftArm: BasePart,
	rightArm: BasePart,
	leftLeg: BasePart,
	rightLeg: BasePart,
}

type SplineSample = {
	position: Vector3,
	tangent: Vector3,
	distance: number,
}

type SplinePath = {
	samples: { SplineSample },
	length: number,
}

local function findModel(parent: Instance, name: string): Model?
	local child = parent:FindFirstChild(name)
	if child ~= nil and child:IsA("Model") then
		return child
	end
	return nil
end

local function findPathFolder(island: Model): Instance?
	local platform = findModel(island, PLATFORM_NAME)
	if platform ~= nil then
		local platformPathFolder = platform:FindFirstChild(PATH_POINTS_NAME)
		if platformPathFolder ~= nil then
			return platformPathFolder
		end
	end

	return island:FindFirstChild(PATH_POINTS_NAME)
end

local function findBasePart(parent: Instance, name: string): BasePart?
	local child = parent:FindFirstChild(name)
	if child ~= nil and child:IsA("BasePart") then
		return child
	end
	return nil
end

local function collectPathPoints(pathFolder: Instance): { BasePart }
	local points: { BasePart } = {}
	for _, child in pathFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end

	table.sort(points, function(left, right)
		return left.Name < right.Name
	end)

	return points
end

local function collectNpcParts(npc: Model): NpcParts?
	local root = findBasePart(npc, "Root")
	local body = findBasePart(npc, "Body")
	local head = findBasePart(npc, "Head")
	local leftArm = findBasePart(npc, "LeftArm")
	local rightArm = findBasePart(npc, "RightArm")
	local leftLeg = findBasePart(npc, "LeftLeg")
	local rightLeg = findBasePart(npc, "RightLeg")

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

local function controlPointPosition(points: { BasePart }, index: number): Vector3
	local clampedIndex = index
	if clampedIndex < 1 then
		clampedIndex = 1
	elseif clampedIndex > #points then
		clampedIndex = #points
	end

	return points[clampedIndex].Position
end

local function catmullRomPosition(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, alpha: number): Vector3
	local alpha2 = alpha * alpha
	local alpha3 = alpha2 * alpha

	return (
		(p1 * 2)
		+ ((p2 - p0) * alpha)
		+ ((p0 * 2 - p1 * 5 + p2 * 4 - p3) * alpha2)
		+ ((p1 * 3 - p0 - p2 * 3 + p3) * alpha3)
	) * 0.5
end

local function catmullRomTangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, alpha: number): Vector3
	local alpha2 = alpha * alpha

	return (
		(p2 - p0)
		+ ((p0 * 2 - p1 * 5 + p2 * 4 - p3) * (2 * alpha))
		+ ((p1 * 3 - p0 - p2 * 3 + p3) * (3 * alpha2))
	) * 0.5
end

local function buildSplinePath(points: { BasePart }): SplinePath
	local samples: { SplineSample } = {}
	local totalDistance = 0

	local function insertSample(position: Vector3, tangent: Vector3)
		if #samples > 0 then
			totalDistance += (position - samples[#samples].position).Magnitude

			if tangent.Magnitude < 0.001 then
				tangent = position - samples[#samples].position
			end
		end

		table.insert(samples, {
			position = position,
			tangent = tangent,
			distance = totalDistance,
		})
	end

	for segment = 1, #points - 1 do
		local p0 = controlPointPosition(points, segment - 1)
		local p1 = controlPointPosition(points, segment)
		local p2 = controlPointPosition(points, segment + 1)
		local p3 = controlPointPosition(points, segment + 2)

		for step = 0, SPLINE_SAMPLES_PER_SEGMENT do
			if segment > 1 and step == 0 then
				continue
			end

			local alpha = step / SPLINE_SAMPLES_PER_SEGMENT
			insertSample(catmullRomPosition(p0, p1, p2, p3, alpha), catmullRomTangent(p0, p1, p2, p3, alpha))
		end
	end

	return {
		samples = samples,
		length = totalDistance,
	}
end

local function sampleSplinePath(path: SplinePath, distance: number): (Vector3, Vector3)
	local samples = path.samples
	if distance <= 0 then
		return samples[1].position, samples[1].tangent
	elseif distance >= path.length then
		local finalSample = samples[#samples]
		return finalSample.position, finalSample.tangent
	end

	local low = 2
	local high = #samples
	while low < high do
		local middle = math.floor((low + high) / 2)
		if samples[middle].distance < distance then
			low = middle + 1
		else
			high = middle
		end
	end

	local after = samples[low]
	local before = samples[low - 1]
	local span = after.distance - before.distance
	local alpha = if span > 0 then math.clamp((distance - before.distance) / span, 0, 1) else 0
	local position = before.position:Lerp(after.position, alpha)
	local tangent = before.tangent:Lerp(after.tangent, alpha)

	if tangent.Magnitude < 0.001 then
		tangent = after.position - before.position
	end

	return position, tangent
end

local function poseNpc(parts: NpcParts, baseCFrame: CFrame, now: number)
	local stride = math.sin(now * STEP_FREQUENCY) * STRIDE_RADIANS
	local counterStride = -stride

	parts.root.CFrame = baseCFrame
	parts.body.CFrame = baseCFrame * CFrame.new(0, 0.32, 0)
	parts.head.CFrame = baseCFrame * CFrame.new(0, 1.62, 0)
	parts.leftArm.CFrame = baseCFrame * CFrame.new(-0.92, 0.28, 0) * CFrame.Angles(counterStride * 0.8, 0, 0)
	parts.rightArm.CFrame = baseCFrame * CFrame.new(0.92, 0.28, 0) * CFrame.Angles(stride * 0.8, 0, 0)
	parts.leftLeg.CFrame = baseCFrame * CFrame.new(-0.34, -0.86, 0) * CFrame.Angles(stride, 0, 0)
	parts.rightLeg.CFrame = baseCFrame * CFrame.new(0.34, -0.86, 0) * CFrame.Angles(counterStride, 0, 0)
end

local island = findModel(Workspace, ISLAND_NAME)
if island == nil then
	warn(`Workspace.{ISLAND_NAME} is missing; rebuild or sync the playable project to show the grid NPC demo`)
	return
end

local pathFolder = findPathFolder(island)
if pathFolder == nil then
	warn(`Workspace.{ISLAND_NAME}.{PATH_POINTS_NAME} is missing; the grid NPC has no path to walk`)
	return
end

local npc = findModel(island, NPC_NAME)
if npc == nil then
	warn(`Workspace.{ISLAND_NAME}.{NPC_NAME} is missing; the grid NPC demo cannot animate`)
	return
end

local pathPoints = collectPathPoints(pathFolder)
local npcParts = collectNpcParts(npc)
if #pathPoints < 2 then
	warn(`Workspace.{ISLAND_NAME}.{PATH_POINTS_NAME} needs at least two waypoint parts`)
	return
end
if npcParts == nil then
	warn(`Workspace.{ISLAND_NAME}.{NPC_NAME} is missing one or more authored body parts`)
	return
end

local splinePath = buildSplinePath(pathPoints)
if splinePath.length < 0.1 then
	warn(`Workspace.{ISLAND_NAME}.{PATH_POINTS_NAME} is too short for spline movement`)
	return
end

local pathStartedAt = os.clock()

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local travelDistance = ((now - pathStartedAt) * WALK_SPEED_STUDS_PER_SECOND) % splinePath.length
	local pathPosition, pathTangent = sampleSplinePath(splinePath, travelDistance)
	local displayPosition = pathPosition + Vector3.new(0, NPC_VERTICAL_OFFSET, 0)
	local flatTangent = Vector3.new(pathTangent.X, 0, pathTangent.Z)
	local facingTarget = displayPosition + flatTangent

	if (facingTarget - displayPosition).Magnitude < 0.001 then
		facingTarget = displayPosition + Vector3.new(0, 0, -1)
	end

	local bob = math.sin(now * STEP_FREQUENCY * 2) * 0.04
	local bobOffset = Vector3.new(0, bob, 0)
	poseNpc(npcParts, CFrame.lookAt(displayPosition + bobOffset, facingTarget + bobOffset), now)
end)
