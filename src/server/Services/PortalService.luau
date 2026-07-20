--!strict

-- Lobby-side portal pad. Occupancy is decided entirely on the server from real
-- character positions (never a client "I'm on the pad" claim): whoever is
-- standing on the authored pad forms a party, a server-owned countdown runs, and
-- when it ends the party is handed to DungeonService to enter a reserved server.
-- The pad roster + countdown are broadcast so the authored BillboardGui above the
-- pad can draw who is joining. Solo is allowed; friends simply appear as they
-- step on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local DungeonLogic = require(Shared.DungeonLogic)

export type Deps = {
	-- Broadcasts the pad roster + countdown to lobby clients.
	publish: (data: any) -> (),
	-- Hands the finalized party to DungeonService (teleport or Studio sim).
	launch: (players: { Player }) -> boolean,
}

local PortalService = {}

local dungeon = Config.dungeon
local padPlatform: BasePart? = nil
local deps: Deps? = nil

-- Arrival-ordered list of players currently standing on the pad.
local order: { Player } = {}
local deadline: number? = nil
-- After a launch the pad ignores occupancy briefly so the just-launched party
-- (still physically on the pad for a beat before they teleport or move) is not
-- re-detected and re-launched, and so the pad reliably re-arms afterward.
local cooldownUntil = 0

function PortalService.registerPad(platform: BasePart)
	padPlatform = platform
end

local function padRadius(platform: BasePart): number
	-- Cylinder pads are authored on their side (Orientation z=90), so the disc
	-- radius comes from the larger of the two non-thickness axes, matching the
	-- authored RuneCircle occupancy test.
	return math.max(platform.Size.Y, platform.Size.Z) / 2 + dungeon.padPadding
end

local function standingOnPad(platform: BasePart, player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	local humanoid = character:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	if humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	local offset = root.Position - platform.Position
	return DungeonLogic.isWithinCylinder(
		offset.X,
		offset.Y,
		offset.Z,
		padRadius(platform),
		dungeon.padHeightTolerance
	)
end

local function indexOf(player: Player): number?
	for index, candidate in order do
		if candidate == player then
			return index
		end
	end
	return nil
end

local function removeFromOrder(player: Player)
	local index = indexOf(player)
	if index ~= nil then
		table.remove(order, index)
	end
end

function PortalService.forget(player: Player)
	removeFromOrder(player)
end

local function refreshOrder(platform: BasePart)
	-- Drop anyone who stepped off or left; keep arrival order for the rest.
	for i = #order, 1, -1 do
		local player = order[i]
		if player.Parent == nil or not standingOnPad(platform, player) then
			table.remove(order, i)
		end
	end
	-- Append new arrivals in a stable order.
	for _, player in Players:GetPlayers() do
		if standingOnPad(platform, player) and indexOf(player) == nil then
			table.insert(order, player)
		end
	end
end

local function buildRoster(): { { userId: number, name: string } }
	local roster: { { userId: number, name: string } } = {}
	for index, player in order do
		if index > dungeon.partyMax then
			break
		end
		table.insert(roster, { userId = player.UserId, name = player.DisplayName })
	end
	return roster
end

local function publishState(launching: boolean)
	local target = deps
	if target == nil then
		return
	end
	local countdown: number? = nil
	if deadline ~= nil then
		countdown = DungeonLogic.countdownRemaining(deadline, os.clock())
	end
	target.publish({
		occupants = buildRoster(),
		count = #order,
		partyMax = dungeon.partyMax,
		countdown = countdown,
		launching = launching,
	})
end

local function launchParty(): boolean
	-- The pad roster is already arrival-ordered and capped when displayed; take
	-- the first partyMax as the finalized party (DungeonLogic.clampParty covers
	-- the same rule under test).
	local players: { Player } = {}
	for index, player in order do
		if index > dungeon.partyMax then
			break
		end
		table.insert(players, player)
	end
	deadline = nil
	table.clear(order)
	cooldownUntil = os.clock() + 3
	local target = deps
	if target == nil then
		return false
	end
	return target.launch(players)
end

local function tick(platform: BasePart)
	if os.clock() < cooldownUntil then
		publishState(true)
		return
	end

	refreshOrder(platform)

	if #order == 0 then
		deadline = nil
		publishState(false)
		return
	end

	if deadline == nil then
		deadline = os.clock() + dungeon.countdownSeconds
	end

	if os.clock() >= deadline then
		publishState(true)
		launchParty()
		return
	end

	publishState(false)
end

function PortalService.start(dependencies: Deps)
	deps = dependencies
	task.spawn(function()
		-- Portals are inert inside a reserved dungeon server; only the lobby runs
		-- the pad loop.
		local platform = padPlatform
		local waited = 0
		while platform == nil and waited < 15 do
			task.wait(0.5)
			waited += 0.5
			platform = padPlatform
		end
		if platform == nil then
			return
		end
		while true do
			task.wait(0.4)
			local current = padPlatform
			if current ~= nil then
				tick(current)
			end
		end
	end)
end

return PortalService
