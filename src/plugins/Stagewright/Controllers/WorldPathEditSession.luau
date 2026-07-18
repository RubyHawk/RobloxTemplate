--!strict

export type Vec3 = {
	x: number,
	y: number,
	z: number,
}

export type HandleId = "Out" | "In"

export type Config = {
	beginEdit: (label: string) -> number?,
	finishEdit: (transaction: number, commit: boolean) -> boolean,
	applyNode: (nodeId: string, position: Vec3) -> boolean,
	applyHandle: (edgeId: string, handleId: HandleId, offset: Vec3) -> boolean,
	currentPreview: () -> any?,
	onPreview: (preview: any?) -> (),
	reportBlocked: (action: string) -> (),
	onCommitted: () -> (),
	onFailed: (action: string) -> (),
}

export type Session = {
	moveNode: (self: Session, nodeId: string, position: Vec3, finished: boolean) -> boolean,
	moveHandle: (
		self: Session,
		edgeId: string,
		handleId: HandleId,
		offset: Vec3,
		finished: boolean
	) -> boolean,
	cancel: (self: Session) -> boolean,
	isActive: (self: Session) -> boolean,
}

local WorldPathEditSession = {}

function WorldPathEditSession.new(config: Config): Session
	local activeTransaction: number? = nil

	local function finish(commit: boolean): boolean
		local transaction = activeTransaction
		activeTransaction = nil
		if transaction == nil then
			return false
		end
		local succeeded, finished = pcall(config.finishEdit, transaction, commit)
		if not succeeded then
			warn(`Stagewright World Path transaction finish failed: {tostring(finished)}`)
			return false
		end
		return finished
	end

	local function begin(label: string, blockedAction: string): boolean
		if activeTransaction ~= nil then
			return true
		end
		activeTransaction = config.beginEdit(label)
		if activeTransaction == nil then
			config.reportBlocked(blockedAction)
			return false
		end
		return true
	end

	local function finishAppliedEdit(finished: boolean, action: string): boolean
		config.onPreview(config.currentPreview())
		if not finished then
			return true
		end
		if finish(true) then
			config.onCommitted()
			return true
		end
		config.onFailed(action)
		return false
	end

	local function failApply(action: string): boolean
		finish(false)
		config.onFailed(action)
		return false
	end

	local session: Session = {} :: any
	session.moveNode = function(_self: Session, nodeId: string, position: Vec3, finished: boolean): boolean
		local action = "Move route node"
		if not begin("Move Stagewright route node", action) then
			return false
		elseif not config.applyNode(nodeId, position) then
			return failApply(action)
		end
		return finishAppliedEdit(finished, action)
	end
	session.moveHandle = function(
		_self: Session,
		edgeId: string,
		handleId: HandleId,
		offset: Vec3,
		finished: boolean
	): boolean
		local action = "Shape route spline"
		if not begin("Shape Stagewright route spline", action) then
			return false
		elseif not config.applyHandle(edgeId, handleId, offset) then
			return failApply(action)
		end
		return finishAppliedEdit(finished, action)
	end
	session.cancel = function(_self: Session): boolean
		local canceled = activeTransaction ~= nil
		finish(false)
		return canceled
	end
	session.isActive = function(_self: Session): boolean
		return activeTransaction ~= nil
	end
	return session
end

return table.freeze(WorldPathEditSession)
