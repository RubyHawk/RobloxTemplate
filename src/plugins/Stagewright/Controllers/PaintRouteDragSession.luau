--!strict

local PointerDrag = if script ~= nil
	then require(script.Parent.Parent.Interaction.PointerDrag)
	else require("../Interaction/PointerDrag")

export type Point2 = PointerDrag.Point2
export type Vec3 = {
	x: number,
	y: number,
	z: number,
}
export type Target = PointerDrag.NodeTarget | PointerDrag.HandleTarget
export type FailurePhase = "Apply" | "Commit"

export type Config = {
	beginEdit: (label: string) -> number?,
	finishEdit: (transaction: number, commit: boolean) -> boolean,
	applyTarget: (target: Target, position: Vec3) -> boolean,
	onPreview: () -> (),
	reportBlocked: (action: string) -> (),
	onCommitted: () -> (),
	onFailed: (action: string, phase: FailurePhase) -> (),
	onReleasedWithoutEdit: () -> (),
}

export type Session = {
	press: (self: Session, target: Target, position: Point2) -> boolean,
	move: (self: Session, position: Point2, localPosition: Vec3?) -> boolean,
	release: (self: Session, position: Point2, localPosition: Vec3?) -> boolean,
	cancel: (self: Session, reason: string) -> boolean,
	isActive: (self: Session) -> boolean,
}

local PaintRouteDragSession = {}
local PRIMARY_POINTER_ID = "mouse-primary"

local function editLabels(target: Target): (string, string)
	if target.kind == "Node" then
		return "Move Stagewright route node", "Move route node"
	end
	return "Shape Stagewright route spline", "Shape route spline"
end

function PaintRouteDragSession.new(config: Config): Session
	local pointerState = PointerDrag.idle()
	local activeTransaction: number? = nil
	local applied = false

	local function clearPointer(reason: string)
		pointerState = PointerDrag.cancel(pointerState, reason).state
	end

	local function finish(commit: boolean): boolean
		local transaction = activeTransaction
		activeTransaction = nil
		if transaction == nil then
			return false
		end
		local succeeded, committed = pcall(config.finishEdit, transaction, commit)
		return succeeded and committed == true
	end

	local function begin(target: Target): (boolean, string)
		local label, action = editLabels(target)
		if activeTransaction ~= nil then
			return true, action
		end
		local succeeded, transaction = pcall(config.beginEdit, label)
		activeTransaction = if succeeded then transaction else nil
		if activeTransaction == nil then
			clearPointer("Edit unavailable")
			config.reportBlocked(action)
			return false, action
		end
		return true, action
	end

	local function apply(target: Target, position: Vec3): boolean
		local began, action = begin(target)
		if not began then
			return false
		end
		local succeeded, changed = pcall(config.applyTarget, target, position)
		if not succeeded or changed ~= true then
			clearPointer("Apply failed")
			applied = false
			finish(false)
			config.onFailed(action, "Apply")
			return false
		end
		applied = true
		config.onPreview()
		return true
	end

	local function commit(target: Target)
		local _, action = editLabels(target)
		local hadAppliedEdit = activeTransaction ~= nil and applied
		applied = false
		if not hadAppliedEdit then
			config.onReleasedWithoutEdit()
			return
		end
		if finish(true) then
			config.onCommitted()
		else
			config.onFailed(action, "Commit")
		end
	end

	local session: Session = {} :: any
	session.press = function(_self: Session, target: Target, position: Point2): boolean
		if PointerDrag.isActive(pointerState) or activeTransaction ~= nil then
			clearPointer("Replaced by a new press")
			applied = false
			finish(false)
		end
		local result = PointerDrag.press(pointerState, PRIMARY_POINTER_ID, target, position)
		pointerState = result.state
		return #result.actions > 0
	end
	session.move = function(_self: Session, position: Point2, localPosition: Vec3?): boolean
		local wasActive = PointerDrag.isActive(pointerState)
		local result = PointerDrag.move(pointerState, PRIMARY_POINTER_ID, position)
		pointerState = result.state
		for _, action in result.actions do
			if (action.kind == "DragStarted" or action.kind == "DragMoved") and localPosition ~= nil then
				if not apply(action.target :: Target, localPosition) then
					break
				end
			end
		end
		return wasActive
	end
	session.release = function(_self: Session, position: Point2, localPosition: Vec3?): boolean
		if not PointerDrag.isActive(pointerState) then
			return false
		end
		local result = PointerDrag.release(pointerState, PRIMARY_POINTER_ID, position)
		pointerState = result.state
		local failed = false
		local appliedAtRelease = false
		for _, action in result.actions do
			if action.kind == "Clicked" then
				config.onReleasedWithoutEdit()
			elseif action.kind == "DragStarted" and localPosition ~= nil then
				appliedAtRelease = apply(action.target :: Target, localPosition)
				failed = not appliedAtRelease
			elseif action.kind == "Committed" and not failed then
				if not appliedAtRelease and localPosition ~= nil then
					appliedAtRelease = apply(action.target :: Target, localPosition)
					failed = not appliedAtRelease
				end
				if not failed then
					commit(action.target :: Target)
				end
			end
		end
		return true
	end
	session.cancel = function(_self: Session, reason: string): boolean
		local canceled = PointerDrag.isActive(pointerState) or activeTransaction ~= nil
		clearPointer(reason)
		applied = false
		finish(false)
		return canceled
	end
	session.isActive = function(_self: Session): boolean
		return PointerDrag.isActive(pointerState) or activeTransaction ~= nil
	end
	return session
end

return table.freeze(PaintRouteDragSession)
