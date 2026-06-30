--!strict

-- Pure validation for pack descriptors, dependency-free so it can be unit-tested
-- under Lune. PackRegistry.validate delegates here with the authored pool sizes,
-- so the model, descriptors, binder, and config can never silently drift.

local PackValidation = {}

export type PoolSizes = {
	stat: number,
	action: number,
	progress: number,
}

function PackValidation.check(descriptor: any, pool: PoolSizes): (boolean, string?)
	if type(descriptor) ~= "table" then
		return false, "descriptor must be a table"
	end
	if type(descriptor.id) ~= "string" or descriptor.id == "" then
		return false, "descriptor.id must be a non-empty string"
	end
	local id = descriptor.id

	if type(descriptor.currencies) ~= "table" then
		return false, `pack "{id}" must list currencies`
	end
	local hasPrimary = false
	for _, currency in descriptor.currencies do
		if currency.primary then
			hasPrimary = true
		end
	end
	if not hasPrimary then
		return false, `pack "{id}" has no primary currency`
	end

	if type(descriptor.hud) ~= "table" then
		return false, `pack "{id}" must define hud`
	end

	local function checkSlots(bindings: any, limit: number, kind: string): (boolean, string?)
		if bindings == nil then
			return true, nil
		end
		for _, binding in bindings do
			if type(binding.slot) ~= "number" or binding.slot < 1 or binding.slot > limit then
				return false, `pack "{id}" {kind} slot {tostring(binding.slot)} is outside 1..{limit}`
			end
		end
		return true, nil
	end

	local ok, reason = checkSlots(descriptor.hud.stats, pool.stat, "stat")
	if not ok then
		return false, reason
	end
	ok, reason = checkSlots(descriptor.hud.progress, pool.progress, "progress")
	if not ok then
		return false, reason
	end
	ok, reason = checkSlots(descriptor.hud.actions, pool.action, "action")
	if not ok then
		return false, reason
	end

	local screenSet: { [string]: boolean } = {}
	for _, screen in descriptor.screens or {} do
		screenSet[screen] = true
	end
	for _, item in descriptor.navigation or {} do
		if not screenSet[item.screen] then
			return false, `pack "{id}" navigates to "{item.screen}" which is not in screens`
		end
	end

	return true, nil
end

return PackValidation
