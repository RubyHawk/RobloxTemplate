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
	area: ("Marker" | "Label")?,
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
	area: ("Marker" | "Label")?,
	distance: number,
}

type RankedHit = {
	hit: Hit,
	priority: number,
	key: string,
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
		return `Handle\0{primitive.id}\0{primitive.handleId}`
	elseif primitive.kind == "Node" then
		return `Node\0{primitive.id}`
	end
	return `Edge\0{primitive.id}`
end

local function primitivePriority(primitive: Primitive): number
	if primitive.kind == "Handle" then
		return 1
	elseif primitive.kind == "Node" then
		return if primitive.area == "Label" then 3 else 2
	end
	return 4
end

local function rankedBefore(left: RankedHit, right: RankedHit): boolean
	return left.priority < right.priority
		or (left.priority == right.priority and left.hit.distance < right.hit.distance)
		or (
			left.priority == right.priority
			and left.hit.distance == right.hit.distance
			and left.key < right.key
		)
end

function HitTest.resolveAll(point: Point2, primitives: { Primitive }): { Hit }
	assertPoint(point, "point")
	local bestByKey: { [string]: RankedHit } = {}

	for _, primitive in primitives do
		assert(primitive.id ~= "", "primitive id cannot be empty")
		assert(
			isFinite(primitive.radius) and primitive.radius >= 0,
			"primitive radius must be finite and non-negative"
		)

		local distance: number?
		local handleId: string? = nil
		local area: ("Marker" | "Label")? = nil
		if primitive.kind == "Edge" then
			distance = edgeDistance(point, primitive.points)
		else
			assertPoint(primitive.center, "primitive center")
			distance = pointDistance(point, primitive.center)
			if primitive.kind == "Handle" then
				assert(primitive.handleId ~= "", "handle id cannot be empty")
				handleId = primitive.handleId
			else
				assert(
					primitive.area == nil or primitive.area == "Marker" or primitive.area == "Label",
					"node area must be Marker or Label"
				)
				area = primitive.area or "Marker"
			end
		end

		if distance == nil or distance > primitive.radius then
			continue
		end
		local key = stableKey(primitive)
		local ranked = {
			priority = primitivePriority(primitive),
			key = key,
			hit = table.freeze({
				kind = primitive.kind,
				id = primitive.id,
				handleId = handleId,
				area = area,
				distance = distance,
			}),
		}
		local existing = bestByKey[key]
		if existing == nil or rankedBefore(ranked, existing) then
			bestByKey[key] = ranked
		end
	end

	local rankedHits: { RankedHit } = {}
	for _, ranked in bestByKey do
		table.insert(rankedHits, ranked)
	end
	table.sort(rankedHits, rankedBefore)
	local hits: { Hit } = {}
	for _, ranked in rankedHits do
		table.insert(hits, ranked.hit)
	end
	return table.freeze(hits)
end

function HitTest.resolve(point: Point2, primitives: { Primitive }): Hit?
	return HitTest.resolveAll(point, primitives)[1]
end

function HitTest.cycleNode(hits: { Hit }, previousNodeId: string?): Hit?
	local nodes: { Hit } = {}
	for _, hit in hits do
		if hit.kind == "Node" then
			table.insert(nodes, hit)
		end
	end
	if #nodes == 0 then
		return nil
	end
	if previousNodeId ~= nil then
		for index, hit in nodes do
			if hit.id == previousNodeId then
				return nodes[index % #nodes + 1]
			end
		end
	end
	return nodes[1]
end

function HitTest.preferSelectedNode(hits: { Hit }, selectedNodeId: string?): Hit?
	local primary = hits[1]
	if primary == nil or primary.kind ~= "Node" or selectedNodeId == nil then
		return primary
	end
	for _, hit in hits do
		if
			hit.kind == "Node"
			and hit.id == selectedNodeId
			and (hit.area ~= "Label" or primary.area == "Label")
		then
			return hit
		end
	end
	return primary
end

return table.freeze(HitTest)
