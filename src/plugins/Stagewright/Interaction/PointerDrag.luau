--!strict

local PointerDrag = {}

export type Point2 = {
	x: number,
	y: number,
}

export type HandleTarget = {
	kind: "Handle",
	id: string,
	handleId: string,
}
export type NodeTarget = {
	kind: "Node",
	id: string,
}
export type EdgeTarget = {
	kind: "Edge",
	id: string,
}
export type Target = HandleTarget | NodeTarget | EdgeTarget

export type Phase = "Idle" | "Pressed" | "Dragging"
export type State = {
	phase: Phase,
	pointerId: string?,
	target: Target?,
	startPosition: Point2?,
	lastPosition: Point2?,
}

export type ActionKind = "Pressed" | "DragStarted" | "DragMoved" | "Clicked" | "Committed" | "Cancelled"
export type Action = {
	kind: ActionKind,
	pointerId: string,
	target: Target,
	startPosition: Point2,
	position: Point2,
	reason: string?,
}

export type Result = {
	state: State,
	actions: { Action },
}

PointerDrag.THRESHOLD_PIXELS = 4

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function assertPoint(point: Point2, label: string)
	assert(isFinite(point.x) and isFinite(point.y), `{label} must be finite`)
end

local function frozenPoint(point: Point2): Point2
	return table.freeze({
		x = point.x,
		y = point.y,
	})
end

local function frozenTarget(target: Target): Target
	assert(target.id ~= "", "target id cannot be empty")
	if target.kind == "Handle" then
		assert(
			type(target.handleId) == "string" and target.handleId ~= "",
			"handle target id cannot be empty"
		)
		return table.freeze({
			kind = "Handle",
			id = target.id,
			handleId = target.handleId,
		})
	elseif target.kind == "Node" then
		return table.freeze({
			kind = "Node",
			id = target.id,
		})
	elseif target.kind == "Edge" then
		return table.freeze({
			kind = "Edge",
			id = target.id,
		})
	end
	error("target kind must be Handle, Node, or Edge")
end

local IDLE: State = table.freeze({
	phase = "Idle",
	pointerId = nil,
	target = nil,
	startPosition = nil,
	lastPosition = nil,
})

local EMPTY_ACTIONS: { Action } = table.freeze({})

local function result(state: State, actions: { Action }): Result
	return table.freeze({
		state = state,
		actions = actions,
	})
end

local function ignored(state: State): Result
	return result(state, EMPTY_ACTIONS)
end

local function activeState(
	phase: "Pressed" | "Dragging",
	pointerId: string,
	target: Target,
	start: Point2,
	last: Point2
): State
	return table.freeze({
		phase = phase,
		pointerId = pointerId,
		target = target,
		startPosition = frozenPoint(start),
		lastPosition = frozenPoint(last),
	})
end

local function action(kind: ActionKind, state: State, position: Point2, reason: string?): Action
	local pointerId = state.pointerId
	local target = state.target
	local startPosition = state.startPosition
	assert(pointerId ~= nil and target ~= nil and startPosition ~= nil, "action requires an active pointer")
	return table.freeze({
		kind = kind,
		pointerId = pointerId,
		target = target,
		startPosition = startPosition,
		position = frozenPoint(position),
		reason = reason,
	})
end

local function acted(state: State, emitted: Action): Result
	return result(state, table.freeze({ emitted }))
end

local function actedTwice(state: State, first: Action, second: Action): Result
	return result(state, table.freeze({ first, second }))
end

function PointerDrag.idle(): State
	return IDLE
end

function PointerDrag.isActive(state: State): boolean
	return state.phase ~= "Idle"
end

function PointerDrag.isDragging(state: State): boolean
	return state.phase == "Dragging"
end

function PointerDrag.press(state: State, pointerId: string, target: Target?, position: Point2): Result
	if state.phase ~= "Idle" or target == nil then
		return ignored(state)
	end
	assert(pointerId ~= "", "pointer id cannot be empty")
	assertPoint(position, "position")
	local capturedTarget = frozenTarget(target)
	local nextState = activeState("Pressed", pointerId, capturedTarget, position, position)
	return acted(nextState, action("Pressed", nextState, position, nil))
end

function PointerDrag.move(state: State, pointerId: string, position: Point2): Result
	if state.phase == "Idle" or state.pointerId ~= pointerId then
		return ignored(state)
	end
	assertPoint(position, "position")
	local target = state.target
	local startPosition = state.startPosition
	assert(target ~= nil and startPosition ~= nil, "active pointer state is incomplete")

	local nextPhase: "Pressed" | "Dragging" = if state.phase == "Pressed" then "Pressed" else "Dragging"
	local actionKind: ActionKind? = nil
	if state.phase == "Pressed" then
		local deltaX = position.x - startPosition.x
		local deltaY = position.y - startPosition.y
		if deltaX * deltaX + deltaY * deltaY >= PointerDrag.THRESHOLD_PIXELS ^ 2 then
			nextPhase = "Dragging"
			actionKind = "DragStarted"
		end
	else
		actionKind = "DragMoved"
	end

	local nextState = activeState(nextPhase, pointerId, target, startPosition, position)
	if actionKind == nil then
		return ignored(nextState)
	end
	return acted(nextState, action(actionKind, nextState, position, nil))
end

function PointerDrag.release(state: State, pointerId: string, position: Point2): Result
	if state.phase == "Idle" or state.pointerId ~= pointerId then
		return ignored(state)
	end
	assertPoint(position, "position")
	if state.phase == "Pressed" then
		local startPosition = state.startPosition
		local target = state.target
		assert(startPosition ~= nil and target ~= nil, "active pointer state is incomplete")
		local deltaX = position.x - startPosition.x
		local deltaY = position.y - startPosition.y
		if deltaX * deltaX + deltaY * deltaY < PointerDrag.THRESHOLD_PIXELS ^ 2 then
			return acted(IDLE, action("Clicked", state, position, nil))
		end
		local draggingState = activeState("Dragging", pointerId, target, startPosition, position)
		return actedTwice(
			IDLE,
			action("DragStarted", draggingState, position, nil),
			action("Committed", draggingState, position, nil)
		)
	end
	return acted(IDLE, action("Committed", state, position, nil))
end

function PointerDrag.cancel(state: State, reason: string): Result
	if state.phase == "Idle" then
		return ignored(state)
	end
	assert(reason ~= "", "cancel reason cannot be empty")
	local lastPosition = state.lastPosition
	assert(lastPosition ~= nil, "active pointer state has no last position")
	return acted(IDLE, action("Cancelled", state, lastPosition, reason))
end

return table.freeze(PointerDrag)
