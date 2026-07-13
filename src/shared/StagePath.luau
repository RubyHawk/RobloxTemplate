--!strict

local StagePath = {}

export type Vec3 = { x: number, y: number, z: number }
export type Sample = {
	position: Vec3,
	tangent: Vec3,
	up: Vec3,
	distance: number,
}
export type BakeOptions = {
	maximumChordError: number?,
	maximumSegmentLength: number?,
	maximumTurnAngleDegrees: number?,
	maximumDepth: number?,
}

local EPSILON = 1e-7

local function add(left: Vec3, right: Vec3): Vec3
	return { x = left.x + right.x, y = left.y + right.y, z = left.z + right.z }
end

local function subtract(left: Vec3, right: Vec3): Vec3
	return { x = left.x - right.x, y = left.y - right.y, z = left.z - right.z }
end

local function scale(value: Vec3, amount: number): Vec3
	return { x = value.x * amount, y = value.y * amount, z = value.z * amount }
end

local function dot(left: Vec3, right: Vec3): number
	return left.x * right.x + left.y * right.y + left.z * right.z
end

local function cross(left: Vec3, right: Vec3): Vec3
	return {
		x = left.y * right.z - left.z * right.y,
		y = left.z * right.x - left.x * right.z,
		z = left.x * right.y - left.y * right.x,
	}
end

local function magnitude(value: Vec3): number
	return math.sqrt(dot(value, value))
end

local function normalize(value: Vec3, fallback: Vec3): Vec3
	local length = magnitude(value)
	if length <= EPSILON then
		return fallback
	end
	return scale(value, 1 / length)
end

local function lerp(left: Vec3, right: Vec3, alpha: number): Vec3
	return add(left, scale(subtract(right, left), alpha))
end

function StagePath.position(p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3, alpha: number): Vec3
	local oneMinus = 1 - alpha
	local oneMinus2 = oneMinus * oneMinus
	local alpha2 = alpha * alpha
	return add(
		add(scale(p0, oneMinus2 * oneMinus), scale(p1, 3 * oneMinus2 * alpha)),
		add(scale(p2, 3 * oneMinus * alpha2), scale(p3, alpha2 * alpha))
	)
end

function StagePath.derivative(p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3, alpha: number): Vec3
	local oneMinus = 1 - alpha
	return add(
		add(scale(subtract(p1, p0), 3 * oneMinus * oneMinus), scale(subtract(p2, p1), 6 * oneMinus * alpha)),
		scale(subtract(p3, p2), 3 * alpha * alpha)
	)
end

local function stableUp(tangent: Vec3, previousUp: Vec3): Vec3
	local right = cross(previousUp, tangent)
	if magnitude(right) <= EPSILON then
		local alternate = if math.abs(tangent.y) < 0.9
			then { x = 0, y = 1, z = 0 }
			else { x = 1, y = 0, z = 0 }
		right = cross(alternate, tangent)
	end
	right = normalize(right, { x = 0, y = 0, z = 1 })
	return normalize(cross(tangent, right), previousUp)
end

function StagePath.bake(p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3, options: BakeOptions?): ({ Sample }, number)
	local maximumChordError = if options ~= nil and options.maximumChordError ~= nil
		then math.max(options.maximumChordError, 0.001)
		else 0.08
	local maximumSegmentLength = if options ~= nil and options.maximumSegmentLength ~= nil
		then math.max(options.maximumSegmentLength, 0.1)
		else 1.5
	local maximumDepth = if options ~= nil and options.maximumDepth ~= nil
		then math.clamp(math.floor(options.maximumDepth), 1, 16)
		else 10
	local maximumTurnAngle = math.rad(
		if options ~= nil and options.maximumTurnAngleDegrees ~= nil
			then math.clamp(options.maximumTurnAngleDegrees, 0.25, 90)
			else 8
	)

	local parameters: { number } = { 0 }
	local function subdivide(startAlpha: number, endAlpha: number, depth: number)
		local middleAlpha = (startAlpha + endAlpha) * 0.5
		local startPosition = StagePath.position(p0, p1, p2, p3, startAlpha)
		local middlePosition = StagePath.position(p0, p1, p2, p3, middleAlpha)
		local endPosition = StagePath.position(p0, p1, p2, p3, endAlpha)
		local chordMiddle = lerp(startPosition, endPosition, 0.5)
		local chordError = magnitude(subtract(middlePosition, chordMiddle))
		local chordLength = magnitude(subtract(endPosition, startPosition))
		local startTangent =
			normalize(StagePath.derivative(p0, p1, p2, p3, startAlpha), { x = 0, y = 0, z = -1 })
		local endTangent = normalize(StagePath.derivative(p0, p1, p2, p3, endAlpha), startTangent)
		local turnAngle = math.acos(math.clamp(dot(startTangent, endTangent), -1, 1))
		if
			depth < maximumDepth
			and (
				chordError > maximumChordError
				or chordLength > maximumSegmentLength
				or turnAngle > maximumTurnAngle
			)
		then
			subdivide(startAlpha, middleAlpha, depth + 1)
			subdivide(middleAlpha, endAlpha, depth + 1)
		else
			table.insert(parameters, endAlpha)
		end
	end
	subdivide(0, 1, 0)

	local samples: { Sample } = {}
	local totalDistance = 0
	local previousPosition: Vec3? = nil
	local previousUp: Vec3 = { x = 0, y = 1, z = 0 }
	for _, alpha in parameters do
		local position = StagePath.position(p0, p1, p2, p3, alpha)
		local derivative = StagePath.derivative(p0, p1, p2, p3, alpha)
		if magnitude(derivative) <= EPSILON and previousPosition ~= nil then
			derivative = subtract(position, previousPosition)
		end
		local tangent = normalize(derivative, { x = 0, y = 0, z = -1 })
		local up = stableUp(tangent, previousUp)
		if previousPosition ~= nil then
			totalDistance += magnitude(subtract(position, previousPosition))
		end
		table.insert(samples, {
			position = position,
			tangent = tangent,
			up = up,
			distance = totalDistance,
		})
		previousPosition = position
		previousUp = up
	end
	return samples, totalDistance
end

function StagePath.sample(samples: { Sample }, length: number, distance: number): Sample?
	if #samples == 0 then
		return nil
	end
	if distance <= 0 or #samples == 1 then
		return samples[1]
	elseif distance >= length then
		return samples[#samples]
	end

	local low = 2
	local high = #samples
	while low < high do
		local middle = math.floor((low + high) * 0.5)
		if samples[middle].distance < distance then
			low = middle + 1
		else
			high = middle
		end
	end
	local after = samples[low]
	local before = samples[low - 1]
	local span = after.distance - before.distance
	local alpha = if span > EPSILON then math.clamp((distance - before.distance) / span, 0, 1) else 0
	return {
		position = lerp(before.position, after.position, alpha),
		tangent = normalize(lerp(before.tangent, after.tangent, alpha), before.tangent),
		up = normalize(lerp(before.up, after.up, alpha), before.up),
		distance = distance,
	}
end

StagePath.add = add
StagePath.subtract = subtract
StagePath.scale = scale
StagePath.dot = dot
StagePath.cross = cross
StagePath.magnitude = magnitude
StagePath.normalize = normalize

return table.freeze(StagePath)
