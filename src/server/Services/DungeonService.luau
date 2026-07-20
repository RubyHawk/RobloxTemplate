--!strict

-- Dungeon runtime for the portal feature. The same place boots in one of two
-- modes; DungeonService owns the dungeon half:
--   * Lobby (public) server -> `launchParty` reserves a private server and sends
--     the pad party there in a single TeleportAsync call.
--   * Reserved (dungeon) server -> `start` detects it, pulls the party onto the
--     authored arena, and runs a server-authoritative boss fight.
-- Every authority decision (boss health, damage, victory, reward) is computed on
-- the server from DungeonLogic; clients only receive a throttled snapshot to draw
-- the HUD. In Studio, where TeleportService cannot reserve servers, the whole
-- loop is simulated in-place, mirroring AfkService's Studio guard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local DungeonConfig = require(Shared.DungeonConfig)
local DungeonLogic = require(Shared.DungeonLogic)

export type Deps = {
	-- Broadcasts a dungeon HUD snapshot to the clients in this server.
	publish: (data: any) -> (),
	-- Server-authoritative currency grant (EconomyService.awardCurrencyRaw).
	award: (player: Player, currencyId: string, amount: number, source: string) -> (boolean, number),
	-- Fallback currency id when a boss reward currency is not configured.
	fallbackCurrencyId: string,
	-- User-safe toast (NotificationService / RemoteService bridge).
	notify: (player: Player, message: string) -> (),
}

local DungeonService = {}

type Run = {
	active: boolean,
	boss: DungeonConfig.Boss,
	core: BasePart?,
	party: { Player },
	health: number,
	maxHealth: number,
	startClock: number,
}

local dungeon = Config.dungeon
local deps: Deps? = nil
local runInProgress = false
-- Authoritative state for the active fight, exposed so the DungeonAttack remote
-- handler can apply validated hits between combat ticks. `lastHitAt` enforces a
-- per-player attack cooldown on the server.
local run: Run? = nil
local lastHitAt: { [Player]: number } = {}

-- Reserved-server detection. In Studio a reserved server cannot exist, so a
-- Workspace attribute opts a test session into dungeon mode.
function DungeonService.isDungeonServer(): boolean
	if RunService:IsStudio() then
		return Workspace:GetAttribute("SimulateDungeonServer") == true
	end
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

local function spawnCFrame(index: number): CFrame
	local base = dungeon.arenaSpawn
	-- Fan arrivals around the spawn point so characters never stack.
	local angle = (index - 1) * (math.pi * 2 / 6)
	local radius = if index <= 1 then 0 else 6
	return CFrame.new(base[1] + math.cos(angle) * radius, base[2], base[3] + math.sin(angle) * radius)
end

local function bossPosition(): Vector3
	local base = dungeon.arenaSpawn
	local offset = dungeon.bossOffset
	return Vector3.new(base[1] + offset[1], base[2] + offset[2], base[3] + offset[3])
end

local function characterRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root, humanoid
	end
	return nil, humanoid
end

local function isAlive(player: Player): boolean
	local _, humanoid = characterRoot(player)
	return humanoid ~= nil and humanoid.Health > 0
end

local function moveToArena(player: Player, index: number)
	local character = player.Character
	if character ~= nil then
		character:PivotTo(spawnCFrame(index))
	end
end

local function findArena(): Model?
	local arena = Workspace:FindFirstChild("DungeonArena")
	if arena ~= nil and arena:IsA("Model") then
		return arena
	end
	return nil
end

local function findBossCore(arena: Model?): BasePart?
	if arena == nil then
		return nil
	end
	local boss = arena:FindFirstChild("Boss")
	if boss == nil then
		return nil
	end
	local core = boss:FindFirstChild("Core")
	if core ~= nil and core:IsA("BasePart") then
		return core
	end
	return nil
end

local function attackersInRing(party: { Player }, center: Vector3, radius: number): number
	local count = 0
	for _, player in party do
		local root = (characterRoot(player))
		if root ~= nil and isAlive(player) then
			local offset = root.Position - center
			if DungeonLogic.isWithinCylinder(offset.X, offset.Y, offset.Z, radius, 30) then
				count += 1
			end
		end
	end
	return count
end

local function livingParty(party: { Player }): { Player }
	local alive: { Player } = {}
	for _, player in party do
		if player.Parent ~= nil and isAlive(player) then
			table.insert(alive, player)
		end
	end
	return alive
end

local function bossAttack(party: { Player }, core: BasePart, boss: DungeonConfig.Boss)
	-- Brief telegraph flash so the AoE reads on the client without a per-frame
	-- stream; the damage decision itself is server-side.
	local bossModel = core.Parent
	local eye = if bossModel ~= nil then bossModel:FindFirstChild("Eye") else nil
	if eye ~= nil and eye:IsA("BasePart") then
		eye.Color = Color3.fromRGB(255, 60, 60)
		task.delay(0.3, function()
			if eye.Parent ~= nil then
				eye.Color = Color3.fromRGB(255, 217, 77)
			end
		end)
	end
	for _, player in party do
		local root, humanoid = characterRoot(player)
		if root ~= nil and humanoid ~= nil and humanoid.Health > 0 then
			local offset = root.Position - core.Position
			if DungeonLogic.isWithinCylinder(offset.X, offset.Y, offset.Z, dungeon.attackRingRadius, 30) then
				humanoid:TakeDamage(boss.attackDamage)
			end
		end
	end
end

-- Broadcasts the current fight's HUD snapshot. Reads the shared `run` state so
-- both the combat loop and the DungeonAttack handler publish the same source.
local function publishRun(phase: string, result: string?)
	local current = run
	local target = deps
	if current == nil or target == nil then
		return
	end
	target.publish({
		active = true,
		bossName = current.boss.name,
		fraction = DungeonLogic.healthFraction(current.health, current.maxHealth),
		phase = phase,
		result = result,
		timeLeft = DungeonLogic.countdownRemaining(
			current.startClock + current.boss.timeLimitSeconds,
			os.clock()
		),
	})
end

-- Runs one server-authoritative boss fight against `party`, positioning them on
-- the arena first. Damage comes from validated player hits (DungeonAttack);
-- proximity auto-DPS is an opt-in fallback. Returns the result and survivors.
local function runFight(party: { Player }, bossId: string): (string, { Player })
	local boss = DungeonConfig.bossById(dungeon, bossId) or dungeon.bosses[1]
	local arena = findArena()
	local core = findBossCore(arena)
	local center = bossPosition()
	if core ~= nil then
		core.CFrame = CFrame.new(center)
	end

	for index, player in party do
		moveToArena(player, index)
	end

	local maxHealth = DungeonLogic.bossMaxHealth(boss, #party)
	local current: Run = {
		active = true,
		boss = boss,
		core = core,
		party = party,
		health = maxHealth,
		maxHealth = maxHealth,
		startClock = os.clock(),
	}
	run = current
	table.clear(lastHitAt)

	local lastClock = current.startClock
	local lastAttack = current.startClock
	local lastSnapshot = 0
	local result = "defeat"

	publishRun("fight")
	while true do
		task.wait(dungeon.tickSeconds)
		local now = os.clock()
		local dt = now - lastClock
		lastClock = now

		local alive = livingParty(party)
		if #alive == 0 then
			result = "defeat"
			break
		end

		if core ~= nil and dungeon.proximityAutoDps then
			local attackers = attackersInRing(party, core.Position, dungeon.damageRingRadius)
			current.health =
				DungeonLogic.applyDamage(current.health, DungeonLogic.partyDps(boss, attackers), dt)
		end

		if DungeonLogic.isDefeated(current.health) then
			result = "victory"
			break
		end

		if now - current.startClock >= boss.timeLimitSeconds then
			result = "defeat"
			break
		end

		if core ~= nil and now - lastAttack >= dungeon.attackIntervalSeconds then
			lastAttack = now
			bossAttack(party, core, boss)
		end

		if now - lastSnapshot >= dungeon.snapshotSeconds then
			lastSnapshot = now
			publishRun("fight")
		end
	end

	current.active = false
	local survivors = livingParty(party)
	publishRun(result, result)

	if result == "victory" and deps ~= nil then
		for _, player in survivors do
			local granted = deps.award(player, boss.rewardCurrencyId, boss.rewardAmount, `dungeon:{boss.id}`)
			if not granted then
				-- Reward currency is not configured in this recipe; fall back to
				-- the primary currency rather than silently dropping the reward.
				deps.award(player, deps.fallbackCurrencyId, boss.rewardAmount, `dungeon:{boss.id}`)
			end
		end
	end

	run = nil
	return result, survivors
end

-- DungeonAttack remote entry: a single validated player hit on the boss. The
-- client only asks; the server verifies an active run, party membership,
-- liveness, range, and a per-player cooldown before subtracting health.
function DungeonService.registerHit(player: Player): (boolean, string)
	local current = run
	if current == nil or not current.active then
		return false, "No active dungeon"
	end
	if table.find(current.party, player) == nil then
		return false, "You are not in this dungeon"
	end
	local root, humanoid = characterRoot(player)
	if root == nil or humanoid == nil or humanoid.Health <= 0 then
		return false, "You are down"
	end
	local core = current.core
	if core == nil then
		return false, "The boss is not present"
	end
	local now = os.clock()
	if now - (lastHitAt[player] or 0) < dungeon.attackCooldownSeconds then
		return false, "Too fast"
	end
	local offset = root.Position - core.Position
	if not DungeonLogic.isWithinCylinder(offset.X, offset.Y, offset.Z, dungeon.damageRingRadius, 30) then
		return false, "Move closer to the boss"
	end
	lastHitAt[player] = now
	current.health = DungeonLogic.applyHit(current.health, current.boss.attackDamagePerHit)
	publishRun("fight")
	return true, "Hit"
end

function DungeonService.forget(player: Player)
	lastHitAt[player] = nil
end

local function userIds(players: { Player }): { number }
	local ids: { number } = {}
	for _, player in players do
		table.insert(ids, player.UserId)
	end
	return ids
end

local function teleportToLobby(players: { Player })
	if #players == 0 then
		return
	end
	if RunService:IsStudio() then
		return
	end
	for attempt = 0, dungeon.teleportRetries do
		local ok = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, players)
		end)
		if ok then
			return
		end
		task.wait(2 ^ attempt)
	end
end

-- Reserved dungeon server: gather the arrivals, run the fight, return everyone
-- to a fresh public lobby server.
local function runDungeonServer()
	if runInProgress then
		return
	end
	runInProgress = true
	Workspace:WaitForChild("DungeonArena", 30)

	local bossId = dungeon.defaultBossId
	local deadline = os.clock() + 10
	-- Wait for at least one character, then a short grace for the rest of the
	-- party to stream in before locking the roster.
	while #Players:GetPlayers() == 0 and os.clock() < deadline do
		task.wait(0.2)
	end
	local firstPlayer = Players:GetPlayers()[1]
	if firstPlayer ~= nil then
		local ok, data = pcall(function()
			return firstPlayer:GetJoinData()
		end)
		if ok and type(data) == "table" and type(data.TeleportData) == "table" then
			local requested = data.TeleportData.bossId
			if type(requested) == "string" and DungeonConfig.bossById(dungeon, requested) ~= nil then
				bossId = requested
			end
		end
	end
	task.wait(2)

	local party: { Player } = {}
	for index, player in Players:GetPlayers() do
		if index <= dungeon.partyMax then
			table.insert(party, player)
		end
	end

	if #party == 0 then
		runInProgress = false
		return
	end

	runFight(party, bossId)
	task.wait(4)
	teleportToLobby(Players:GetPlayers())
end

-- Studio-only: run the same fight in-place (no teleport), then set characters
-- back where they were so the loop is testable without a published place.
local function simulateInPlace(players: { Player }, bossId: string)
	if runInProgress then
		return
	end
	runInProgress = true
	local returnPivots: { [Player]: CFrame } = {}
	for _, player in players do
		local character = player.Character
		if character ~= nil then
			returnPivots[player] = character:GetPivot()
		end
	end

	runFight(players, bossId)
	task.wait(4)

	for _, player in players do
		local character = player.Character
		local pivot = returnPivots[player]
		if character ~= nil and pivot ~= nil then
			character:PivotTo(pivot)
		end
	end
	if deps ~= nil then
		deps.publish({ active = false })
	end
	runInProgress = false
end

local function teleportPartyToReservedServer(players: { Player }, bossId: string): boolean
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({ v = 1, bossId = bossId, party = userIds(players) })
	for attempt = 0, dungeon.teleportRetries do
		local ok = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, players, options)
		end)
		if ok then
			return true
		end
		task.wait(2 ^ attempt)
	end
	local target = deps
	if target ~= nil then
		for _, player in players do
			target.notify(player, "The dungeon portal is busy. Please try again.")
		end
	end
	return false
end

-- Lobby-server entry point used by PortalService when the pad countdown ends.
function DungeonService.launchParty(players: { Player }): boolean
	if #players == 0 then
		return false
	end
	local bossId = dungeon.defaultBossId
	if RunService:IsStudio() then
		task.spawn(function()
			simulateInPlace(players, bossId)
		end)
		return true
	end
	return teleportPartyToReservedServer(players, bossId)
end

function DungeonService.start(dependencies: Deps)
	deps = dependencies
	if not DungeonService.isDungeonServer() then
		return
	end
	if not RunService:IsStudio() then
		TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
			warn(`Dungeon return teleport failed for {player.Name}: {message}`)
		end)
	end
	task.spawn(runDungeonServer)
end

return DungeonService
