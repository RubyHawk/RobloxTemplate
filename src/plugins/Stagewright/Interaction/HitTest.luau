--!strict

local HitTest = {}

export type Point2 = {
	x: number,
	y: number,
}

export type HandlePrimitive = {
	kind: "Handle",
	id: string,
	handleId: string,
	center: Point2,
	radius: number,
}

export type NodePrimitive = {
	kind: "Node",
	id: string,
	center: Point2,
	radius: number,
}

export type EdgePrimitive = {
	kind: "Edge",
	id: string,
	points: { Point2 },
	radius: number,
}

export type Primitive = HandlePrimitive | NodePrimitive | EdgePrimitive
export type HitKind = "Handle" | "Node" | "Edge"
export type Hit = {
	kind: HitKind,
	id: string,
	handleId: string?,
	distance: number,
}

local PRIORITY = {
	Handle = 1,
	Node = 2,
	Edge = 3,
}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function assertPoint(point: Point2, label: string)
	assert(isFinite(point.x) and isFinite(point.y), `{label} must be finite`)
end

local function pointDistance(first: Point2, second: Point2): number
	local x = first.x - second.x
	local y = first.y - second.y
	return math.sqrt(x * x + y * y)
end

local function segmentDistance(point: Point2, first: Point2, second: Point2): number
	local deltaX = second.x - first.x
	local deltaY = second.y - first.y
	local lengthSquared = deltaX * deltaX + deltaY * deltaY
	if lengthSquared <= 1e-12 then
		return pointDistance(point, first)
	end
	local pointX = point.x - first.x
	local pointY = point.y - first.y
	local alpha = math.clamp((pointX * deltaX + pointY * deltaY) / lengthSquared, 0, 1)
	return pointDistance(point, {
		x = first.x + deltaX * alpha,
		y = first.y + deltaY * alpha,
	})
end

local function edgeDistance(point: Point2, points: { Point2 }): number?
	if #points == 0 then
		return nil
	end
	assertPoint(points[1], "edge point")
	if #points == 1 then
		return pointDistance(point, points[1])
	end

	local closest = math.huge
	for index = 2, #points do
		local first = points[index - 1]
		local second = points[index]
		assertPoint(second, "edge point")
		closest = math.min(closest, segmentDistance(point, first, second))
	end
	return closest
end

local function stableKey(primitive: Primitive): string
	if primitive.kind == "Handle" then
		return `{primitive.id}\0{primitive.handleId}`
	end
	return primitive.id
end

function HitTest.resolve(point: Point2, primitives: { Primitive }): Hit?
	assertPoint(point, "point")
	local bestPriority = math.huge
	local bestDistance = math.huge
	local bestKey = ""
	local bestHit: Hit? = nil

	for _, primitive in primitives do
		assert(primitive.id ~= "", "primitive id cannot be empty")
		assert(
			isFinite(primitive.radius) and primitive.radius >= 0,
			"primitive radius must be finite and non-negative"
		)

		local distance: number?
		local handleId: string? = nil
		if primitive.kind == "Edge" then
			distance = edgeDistance(point, primitive.points)
		else
			assertPoint(primitive.center, "primitive center")
			distance = pointDistance(point, primitive.center)
			if primitive.kind == "Handle" then
				assert(primitive.handleId ~= "", "handle id cannot be empty")
				handleId = primitive.handleId
			end
		end

		if distance == nil or distance > primitive.radius then
			continue
		end
		local priority = PRIORITY[primitive.kind]
		local key = stableKey(primitive)
		local isBetter = priority < bestPriority
			or (priority == bestPriority and distance < bestDistance)
			or (priority == bestPriority and distance == bestDistance and key < bestKey)
		if isBetter then
			bestPriority = priority
			bestDistance = distance
			bestKey = key
			bestHit = table.freeze({
				kind = primitive.kind,
				id = primitive.id,
				handleId = handleId,
				distance = distance,
			})
		end
	end

	return bestHit
end

return table.freeze(HitTest)
