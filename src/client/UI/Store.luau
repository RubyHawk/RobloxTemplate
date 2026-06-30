--!strict

-- Minimal reactive store the HUD binds against. Widgets subscribe to dotted state
-- paths (e.g. "currencies.coins", "local.health") and receive a safe default when
-- a path is missing, so they never couple to the raw snapshot shape. Server
-- snapshots replace the view via :set(); client-only UI state (kept under the
-- "local" subtree) survives those replacements and is updated via :setLocal().

local Store = {}
Store.__index = Store

export type Store = typeof(setmetatable(
	{} :: {
		state: { [string]: any },
		subscribers: { [number]: { path: string, fn: (any) -> () } },
		nextId: number,
	},
	Store
))

local function getAt(root: { [string]: any }, path: string): any
	local node: any = root
	for segment in string.gmatch(path, "[^.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[segment]
	end
	return node
end

local function setAt(root: { [string]: any }, path: string, value: any)
	local keys = {}
	for segment in string.gmatch(path, "[^.]+") do
		table.insert(keys, segment)
	end
	local node: any = root
	for index = 1, #keys - 1 do
		local key = keys[index]
		if type(node[key]) ~= "table" then
			node[key] = {}
		end
		node = node[key]
	end
	node[keys[#keys]] = value
end

local function overlaps(a: string, b: string): boolean
	return a == b or string.sub(a, 1, #b + 1) == b .. "." or string.sub(b, 1, #a + 1) == a .. "."
end

function Store.new(): Store
	return setmetatable({ state = {}, subscribers = {}, nextId = 0 }, Store)
end

function Store.get(self: Store, path: string, default: any?): any
	local value = getAt(self.state, path)
	if value == nil then
		return default
	end
	return value
end

function Store.getRoot(self: Store): { [string]: any }
	return self.state
end

-- Replaces the server-driven view, preserving the client-local subtree.
function Store.set(self: Store, view: { [string]: any })
	view["local"] = self.state["local"]
	self.state = view
	for _, subscriber in self.subscribers do
		subscriber.fn(getAt(self.state, subscriber.path))
	end
end

-- Updates a single client-local path and notifies only affected subscribers.
function Store.setLocal(self: Store, path: string, value: any)
	setAt(self.state, path, value)
	for _, subscriber in self.subscribers do
		if overlaps(subscriber.path, path) then
			subscriber.fn(getAt(self.state, subscriber.path))
		end
	end
end

-- Subscribes to a path; fires immediately with the current value and returns an
-- unsubscribe function.
function Store.subscribe(self: Store, path: string, fn: (any) -> ()): () -> ()
	self.nextId += 1
	local id = self.nextId
	self.subscribers[id] = { path = path, fn = fn }
	fn(getAt(self.state, path))
	return function()
		self.subscribers[id] = nil
	end
end

return Store
