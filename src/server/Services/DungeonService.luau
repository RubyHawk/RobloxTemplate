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
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local DungeonConfig = require(Shared.DungeonConfig)
local DungeonLogic = require(Shared.DungeonLogic)
local DungeonBossSelection = require(Shared.DungeonBossSelection)

local DungeonSessionStore = require(script.Parent.Parent.Util.DungeonSessionStore)
local DungeonEventStore = require(script.Parent.Parent.Util.DungeonEventStore)

export type Deps = {
	-- Sends a dungeon HUD snapshot only to the authoritative party. This must not
	-- become a server-wide broadcast because Studio simulation can share a lobby
	-- with players who never entered the encounter.
	publish: (players: { Player }, data: any) -> (),
	-- Server-authoritative currency grant (EconomyService.awardCurrencyRaw).
	award: (player: Player, currencyId: string, amount: number, source: string) -> (boolean, number),
	-- Fallback currency id when a boss reward currency is not configured.
	fallbackCurrencyId: string,
	-- User-safe toast (NotificationService / RemoteService bridge).
	notify: (player: Player, message: string) -> (),
	-- True only after ProfileService owns a writable profile in this server.
	ready: (player: Player) -> boolean,
	-- Saved inventory/equipment authority. The client never selects a weapon for
	-- a hit; the destination server resolves it from the owned profile.
	equippedItemId: (player: Player, slot: string) -> string?,
	ensureEquipped: (player: Player, slot: string, fallbackItemId: string) -> string?,
	grantItem: (player: Player, itemId: string, quantity: number) -> (boolean, number),
	-- Persists a player's chosen boss to their profile (their personal default,
	-- used for solo runs and as the party default when they lead the pad).
	setSavedBossId: (player: Player, bossId: string) -> boolean,
	-- Records the choice as the lobby pad's party pick when the player is the pad
	-- leader; PortalService enforces the leader check, so this is a no-op for a
	-- non-leader or on a reserved server with no pad.
	notePadBossPick: (player: Player, bossId: string) -> (),
}

local DungeonService = {}

type Run = {
	token: number,
	active: boolean,
	phase: string,
	phaseIndex: number,
	boss: DungeonConfig.Boss,
	core: BasePart?,
	arenaFloor: BasePart?,
	partySpawn: BasePart?,
	spectatorSpawn: BasePart?,
	slamTelegraph: BasePart?,
	party: { Player },
	weapons: { [Player]: DungeonConfig.Weapon },
	eliminated: { [Player]: boolean },
	preparedCharacters: { [Player]: Model },
	connections: { RBXScriptConnection },
	lastHitAt: { [Player]: number },
	lastDodgeAt: { [Player]: number },
	-- Per-player, per-ability last-use clock (os.clock) for the hotbar cooldowns.
	lastAbilityAt: { [Player]: { [string]: number } },
	health: number,
	maxHealth: number,
	startClock: number,
	readyUntil: number,
	nextSlamAt: number,
	allDeadSince: number?,
	resultReason: string?,
	rewardByUserId: { [string]: any },
	-- Set while a boss slam is telegraphing; nil otherwise.
	telegraphUntil: number?,
	telegraphCenter: Vector3?,
	telegraphPhase: number?,
}

type PendingTeleport = {
	kind: string,
	launchId: string,
	attempts: number,
	retryScheduled: boolean,
	terminalMessage: string,
}

type StudioReturnState = {
	pivot: CFrame,
	walkSpeed: number?,
	health: number?,
}

local dungeon = Config.dungeon
local deps: Deps? = nil
local runInProgress = false
local nextRunToken = 0
-- Authoritative state for the active fight, exposed so the attack and dodge
-- handlers can validate requests between combat ticks.
local run: Run? = nil
local pendingTeleports: { [Player]: PendingTeleport } = {}
local returningWhenProfileReady: { [Player]: boolean } = {}
local teleportFailureConnection: RBXScriptConnection? = nil
local dungeonArrivalConnection: RBXScriptConnection? = nil
local lockedManifest: DungeonLogic.PartyManifest? = nil
-- nil means arrivals are still being collected. Once populated, only these
-- user ids with the same shape-validated manifest belong in this run.
local admittedUserIds: { [number]: boolean }? = nil

-- Reserved-server detection. In Studio a reserved server cannot exist, so a
-- Workspace attribute opts a test session into dungeon mode.
function DungeonService.isDungeonServer(): boolean
	if RunService:IsStudio() then
		return Workspace:GetAttribute("SimulateDungeonServer") == true
	end
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

local function fallbackPartySpawnCFrame(): CFrame
	local base = dungeon.arenaSpawn
	return CFrame.new(base[1], base[2], base[3])
end

local function spawnCFrame(marker: BasePart?, index: number): CFrame
	local base = if marker ~= nil then marker.CFrame else fallbackPartySpawnCFrame()
	-- Fan arrivals around the spawn point so characters never stack.
	local angle = (index - 1) * (math.pi * 2 / math.max(dungeon.partyMax, 1))
	local radius = if index <= 1 then 0 else 6
	return base * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function spectatorCFrame(marker: BasePart?, partyMarker: BasePart?, index: number): CFrame
	local base = if marker ~= nil then marker.CFrame else spawnCFrame(partyMarker, 1) * CFrame.new(0, 15, -38)
	local columns = math.max(1, math.ceil(math.sqrt(dungeon.partyMax)))
	local column = (index - 1) % columns
	local row = math.floor((index - 1) / columns)
	return base * CFrame.new((column - (columns - 1) * 0.5) * 4, 3, row * 4)
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

local function isCurrentRun(current: Run): boolean
	return run == current and current.active and current.token > 0
end

local function removeDungeonTools(container: Instance?)
	if container == nil then
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("DungeonWeapon") == true then
			child:Destroy()
		end
	end
end

local function matchingDungeonTool(
	container: Instance?,
	weapon: DungeonConfig.Weapon,
	runToken: number
): Tool?
	if container == nil then
		return nil
	end
	for _, child in container:GetChildren() do
		if
			child:IsA("Tool")
			and child:GetAttribute("DungeonWeapon") == true
			and child:GetAttribute("DungeonWeaponId") == weapon.id
			and child:GetAttribute("DungeonRunToken") == runToken
		then
			return child
		end
	end
	return nil
end

local function equipDungeonWeapon(
	current: Run,
	player: Player,
	humanoid: Humanoid,
	weapon: DungeonConfig.Weapon
): boolean
	if not isCurrentRun(current) or current.eliminated[player] then
		return false
	end
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	removeDungeonTools(character)
	removeDungeonTools(backpack)
	local template = ReplicatedStorage:FindFirstChild("Template")
	local weaponFolder = if template ~= nil then template:FindFirstChild("DungeonWeapons") else nil
	local source = if weaponFolder ~= nil then weaponFolder:FindFirstChild(weapon.toolName) else nil
	if
		not isCurrentRun(current)
		or source == nil
		or not source:IsA("Tool")
		or backpack == nil
		or character == nil
		or player.Character ~= character
	then
		warn(`Authored dungeon weapon {weapon.toolName} is unavailable for {player.Name}`)
		return false
	end
	local tool = source:Clone()
	tool.Name = weapon.name
	tool:SetAttribute("DungeonWeapon", true)
	tool:SetAttribute("DungeonWeaponId", weapon.id)
	tool:SetAttribute("DungeonRunToken", current.token)
	tool.Parent = backpack
	humanoid:EquipTool(tool)
	return tool.Parent == character
end

local function bindCharacterDeath(current: Run, player: Player, character: Model, humanoid: Humanoid)
	if current.preparedCharacters[player] == character then
		return
	end
	current.preparedCharacters[player] = character
	table.insert(
		current.connections,
		humanoid.Died:Connect(function()
			if isCurrentRun(current) and current.phase == "fight" then
				current.eliminated[player] = true
				removeDungeonTools(character)
				removeDungeonTools(player:FindFirstChildOfClass("Backpack"))
			end
		end)
	)
end

local function prepareCharacter(
	current: Run,
	player: Player,
	index: number,
	weapon: DungeonConfig.Weapon
): boolean
	if not isCurrentRun(current) or current.eliminated[player] then
		return false
	end
	local character = player.Character
	if character == nil then
		return false
	end
	-- Wait briefly for the body to assemble so PivotTo has a root to move.
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if not isCurrentRun(current) or current.eliminated[player] or player.Character ~= character then
		return false
	end
	local humanoidInstance = character:FindFirstChildWhichIsA("Humanoid")
		or character:WaitForChild("Humanoid", 5)
	if
		not isCurrentRun(current)
		or current.eliminated[player]
		or player.Character ~= character
		or root == nil
		or not root:IsA("BasePart")
		or humanoidInstance == nil
		or not humanoidInstance:IsA("Humanoid")
	then
		return false
	end
	local humanoid = humanoidInstance :: Humanoid
	character:PivotTo(spawnCFrame(current.partySpawn, index))
	humanoid.WalkSpeed = dungeon.walkSpeed
	humanoid.AutoRotate = true
	humanoid.Health = humanoid.MaxHealth
	if not equipDungeonWeapon(current, player, humanoid, weapon) then
		return false
	end
	bindCharacterDeath(current, player, character, humanoid)
	return true
end

local function eliminatePlayer(current: Run, player: Player)
	if not isCurrentRun(current) or current.eliminated[player] then
		return
	end
	current.eliminated[player] = true
	removeDungeonTools(player.Character)
	removeDungeonTools(player:FindFirstChildOfClass("Backpack"))
end

local function prepareSpectator(current: Run, player: Player, index: number)
	if not isCurrentRun(current) or not current.eliminated[player] then
		return
	end
	removeDungeonTools(player.Character)
	removeDungeonTools(player:FindFirstChildOfClass("Backpack"))
	local character = player.Character
	if character == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if
		not isCurrentRun(current)
		or not current.eliminated[player]
		or player.Character ~= character
		or root == nil
		or not root:IsA("BasePart")
	then
		return
	end
	removeDungeonTools(character)
	removeDungeonTools(player:FindFirstChildOfClass("Backpack"))
	character:PivotTo(spectatorCFrame(current.spectatorSpawn, current.partySpawn, index))
	root.AssemblyLinearVelocity = Vector3.zero
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if humanoid ~= nil then
		humanoid.Health = humanoid.MaxHealth
		-- Spectators keep their own camera but cannot fall back into the arena or
		-- body-block living players. Normal cleanup restores movement before the
		-- Studio body is returned or the live server teleports the player away.
		humanoid.WalkSpeed = 0
	end
end

local function awaitPreparedCharacter(
	current: Run,
	player: Player,
	index: number,
	weapon: DungeonConfig.Weapon
): boolean
	local deadline = os.clock() + 5
	repeat
		if not isCurrentRun(current) then
			return false
		end
		if player.Parent ~= Players then
			return false
		end
		if player.Character ~= nil and prepareCharacter(current, player, index, weapon) then
			return true
		end
		task.wait(0.05)
	until os.clock() >= deadline
	return false
end

-- Connect lifecycle handling before preparing anyone, then await the complete
-- initial party preparation. No countdown starts while a character is still
-- assembling or while its authored weapon has not been equipped.
local function positionParty(current: Run): boolean
	local completed = 0
	local prepared: { [Player]: boolean } = {}
	for index, player in current.party do
		local weapon = current.weapons[player]
		if weapon == nil then
			current.eliminated[player] = true
			completed += 1
			continue
		end

		table.insert(
			current.connections,
			player.CharacterRemoving:Connect(function()
				if isCurrentRun(current) and current.phase == "fight" then
					eliminatePlayer(current, player)
				end
			end)
		)
		table.insert(
			current.connections,
			player.CharacterAdded:Connect(function()
				task.spawn(function()
					if not isCurrentRun(current) or current.phase == "preparing" then
						return
					end
					if current.phase == "fight" then
						-- Any replacement body after combat begins is a spectator body;
						-- resetting cannot grant an extra life.
						eliminatePlayer(current, player)
					end
					if current.eliminated[player] then
						prepareSpectator(current, player, index)
					else
						prepareCharacter(current, player, index, weapon)
					end
				end)
			end)
		)

		task.spawn(function()
			local ok, didPrepare = pcall(awaitPreparedCharacter, current, player, index, weapon)
			prepared[player] = ok and didPrepare
			completed += 1
		end)
	end

	while completed < #current.party do
		if not isCurrentRun(current) then
			return false
		end
		task.wait(0.05)
	end
	if not isCurrentRun(current) then
		return false
	end
	for _, player in current.party do
		if prepared[player] ~= true then
			eliminatePlayer(current, player)
		end
	end
	return true
end

local function clearPartyTools(party: { Player })
	for _, player in party do
		removeDungeonTools(player.Character)
		removeDungeonTools(player:FindFirstChildOfClass("Backpack"))
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

local function findArenaPart(arena: Model?, name: string): BasePart?
	if arena == nil then
		return nil
	end
	local part = arena:FindFirstChild(name)
	if part ~= nil and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function findSlamTelegraph(arena: Model?): BasePart?
	if arena == nil then
		return nil
	end
	local telegraph = arena:FindFirstChild("SlamTelegraph")
	if telegraph ~= nil and telegraph:IsA("BasePart") then
		return telegraph
	end
	return nil
end

local function setSlamTelegraph(marker: BasePart?, center: Vector3?, phaseIndex: number)
	if marker == nil then
		return
	end
	if center == nil then
		marker.Transparency = 1
		return
	end
	local diameter = dungeon.slamRadiusStuds * 2
	marker.Size = Vector3.new(math.max(marker.Size.X, 0.2), diameter, diameter)
	marker.CFrame = CFrame.new(center.X, marker.Position.Y, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	marker.Color = if phaseIndex >= 2 then Color3.fromRGB(255, 64, 48) else Color3.fromRGB(255, 174, 45)
	marker.Transparency = 0.42
end

local function alivePartyCount(current: Run): number
	local count = 0
	for _, player in current.party do
		if player.Parent == Players and not current.eliminated[player] and isAlive(player) then
			count += 1
		end
	end
	return count
end

local function nearestLivingRoot(current: Run, center: Vector3): BasePart?
	local selected: BasePart? = nil
	local bestDistance = math.huge
	for _, player in current.party do
		if current.eliminated[player] then
			continue
		end
		local root, humanoid = characterRoot(player)
		if root ~= nil and humanoid ~= nil and humanoid.Health > 0 then
			local distance = (root.Position - center).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				selected = root
			end
		end
	end
	return selected
end

local function attackersInRing(current: Run, center: Vector3, radius: number): number
	local count = 0
	for _, player in current.party do
		if current.eliminated[player] then
			continue
		end
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

-- Players still in the server (whether alive or mid-respawn). Presence decides
-- abandonment; the separate all-dead grace timer decides a real party wipe.
local function presentParty(party: { Player }): { Player }
	local present: { Player } = {}
	for _, player in party do
		if player.Parent ~= nil then
			table.insert(present, player)
		end
	end
	return present
end

-- Boss telegraph: color the eye/core to warn of an incoming slam (danger=true) or
-- return to idle (danger=false). Purely visual; damage is resolved separately.
local function setBossDanger(core: BasePart, danger: boolean)
	local bossModel = core.Parent
	local eye = if bossModel ~= nil then bossModel:FindFirstChild("Eye", true) else nil
	if eye ~= nil and eye:IsA("BasePart") then
		eye.Color = if danger then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(255, 217, 77)
	end
end

-- Resolves a telegraphed, target-locked slam. The marker stays at the position
-- chosen when the warning began, so moving or dodging out in time is reliable.
local function resolveSlam(current: Run, center: Vector3, phaseIndex: number)
	local boss = current.boss
	local damage = boss.attackDamage * if phaseIndex >= 2 then dungeon.enrageDamageMultiplier else 1
	for _, player in current.party do
		if current.eliminated[player] then
			continue
		end
		local root, humanoid = characterRoot(player)
		if root ~= nil and humanoid ~= nil and humanoid.Health > 0 then
			local offset = root.Position - center
			if
				DungeonLogic.isWithinCylinder(
					offset.X,
					offset.Y,
					offset.Z,
					dungeon.slamRadiusStuds,
					dungeon.slamHeightToleranceStuds
				)
			then
				humanoid:TakeDamage(damage)
			end
		end
	end
end

-- Broadcasts one compact, server-authored encounter snapshot. Per-player weapon
-- presentation is included as a keyed map; damage/cooldown still come only from
-- the cached server loadout and are never accepted back from a client.
local function publishRun(result: string?)
	local current = run
	local target = deps
	if current == nil or target == nil then
		return
	end
	local now = os.clock()
	local weaponByUserId: { [string]: any } = {}
	local eliminatedByUserId: { [string]: boolean } = {}
	for player, weapon in current.weapons do
		weaponByUserId[tostring(player.UserId)] = {
			id = weapon.id,
			name = weapon.name,
			cooldownSeconds = weapon.cooldownSeconds,
			rangeStuds = weapon.rangeStuds,
		}
	end
	for _, player in current.party do
		eliminatedByUserId[tostring(player.UserId)] = current.eliminated[player] == true
	end
	local rewardWeapon = if current.boss.rewardItemId ~= nil
		then DungeonConfig.weaponById(dungeon, current.boss.rewardItemId)
		else nil
	target.publish(current.party, {
		active = true,
		combatActive = current.active and current.phase == "fight" and result == nil,
		bossName = current.boss.name,
		fraction = DungeonLogic.healthFraction(current.health, current.maxHealth),
		phase = current.phase,
		phaseIndex = current.phaseIndex,
		result = result,
		resultReason = current.resultReason,
		danger = current.telegraphUntil ~= nil,
		readyTime = DungeonLogic.countdownRemaining(current.readyUntil, now),
		timeLeft = DungeonLogic.countdownRemaining(current.startClock + current.boss.timeLimitSeconds, now),
		slamRadiusStuds = dungeon.slamRadiusStuds,
		weaponByUserId = weaponByUserId,
		eliminatedByUserId = eliminatedByUserId,
		rewardByUserId = current.rewardByUserId,
		rewardCurrencyId = current.boss.rewardCurrencyId,
		rewardAmount = current.boss.rewardAmount,
		rewardItemId = current.boss.rewardItemId,
		rewardItemName = if rewardWeapon ~= nil then rewardWeapon.name else nil,
	})
end

local function resolvePartyWeapons(party: { Player }): { [Player]: DungeonConfig.Weapon }
	local resolved: { [Player]: DungeonConfig.Weapon } = {}
	local target = deps
	local fallback = DungeonConfig.weaponById(dungeon, dungeon.starterWeaponId)
	if target == nil or fallback == nil then
		return resolved
	end
	for _, player in party do
		local itemId = target.equippedItemId(player, dungeon.equipmentSlot)
		if itemId == nil then
			itemId = target.ensureEquipped(player, dungeon.equipmentSlot, dungeon.starterWeaponId)
		end
		resolved[player] = if itemId ~= nil
			then DungeonConfig.weaponById(dungeon, itemId) or fallback
			else fallback
	end
	return resolved
end

local function beginSlam(current: Run, now: number)
	local core = current.core
	if core == nil then
		return
	end
	local targetRoot = nearestLivingRoot(current, core.Position)
	if targetRoot == nil then
		current.nextSlamAt = now + 0.5
		return
	end
	current.telegraphCenter = targetRoot.Position
	current.telegraphPhase = current.phaseIndex
	current.telegraphUntil = now + dungeon.slamTelegraphSeconds
	setBossDanger(core, true)
	setSlamTelegraph(current.slamTelegraph, current.telegraphCenter, current.phaseIndex)
	publishRun(nil)
end

local function finishSlam(current: Run, now: number)
	local center = current.telegraphCenter
	local core = current.core
	if center ~= nil then
		resolveSlam(current, center, current.telegraphPhase or current.phaseIndex)
	end
	if core ~= nil then
		setBossDanger(core, false)
	end
	setSlamTelegraph(current.slamTelegraph, nil, current.phaseIndex)
	current.telegraphUntil = nil
	current.telegraphCenter = nil
	current.telegraphPhase = nil
	local interval = dungeon.slamIntervalSeconds
		* (if current.phaseIndex >= 2 then dungeon.enrageAttackIntervalMultiplier else 1)
	current.nextSlamAt = now + interval
	publishRun(nil)
end

-- Runs one complete server-authoritative encounter. The client supplies only
-- attack/dodge intent; saved loadout, hit geometry, boss attacks, defeat, and
-- rewards all resolve here.
local function runFight(party: { Player }, bossId: string, core: BasePart): (string, { Player })
	local boss = DungeonConfig.bossById(dungeon, bossId) or dungeon.bosses[1]
	local arena = findArena()
	local marker = findSlamTelegraph(arena)
	setSlamTelegraph(marker, nil, 1)
	setBossDanger(core, false)

	local weapons = resolvePartyWeapons(party)
	local originalWalkSpeeds: { [Player]: number } = {}
	for _, player in party do
		local _, humanoid = characterRoot(player)
		if humanoid ~= nil then
			originalWalkSpeeds[player] = humanoid.WalkSpeed
		end
	end
	local maxHealth = DungeonLogic.bossMaxHealth(boss, #party)
	local now = os.clock()
	nextRunToken += 1
	local current: Run = {
		token = nextRunToken,
		active = true,
		phase = "preparing",
		phaseIndex = 1,
		boss = boss,
		core = core,
		arenaFloor = findArenaPart(arena, "Floor"),
		partySpawn = findArenaPart(arena, "PartySpawn"),
		spectatorSpawn = findArenaPart(arena, "SpectatorSpawn"),
		slamTelegraph = marker,
		party = party,
		weapons = weapons,
		eliminated = {},
		preparedCharacters = {},
		connections = {},
		lastHitAt = {},
		lastDodgeAt = {},
		lastAbilityAt = {},
		health = maxHealth,
		maxHealth = maxHealth,
		startClock = now,
		readyUntil = now,
		nextSlamAt = now + dungeon.slamIntervalSeconds,
		allDeadSince = nil,
		resultReason = nil,
		rewardByUserId = {},
		telegraphUntil = nil,
		telegraphCenter = nil,
		telegraphPhase = nil,
	}
	run = current
	local result: string? = nil
	local lastSnapshot = 0

	-- Initial preparation is a real encounter phase, not a detached task. The
	-- ready countdown begins only after each connected character has either been
	-- placed/equipped or safely marked out of the run.
	if not positionParty(current) then
		result = "defeat"
		current.resultReason = "preparationFailed"
	else
		current.phase = "ready"
		current.readyUntil = os.clock() + dungeon.readySeconds
		publishRun(nil)
	end

	while result == nil and os.clock() < current.readyUntil do
		if #presentParty(party) == 0 then
			result = "defeat"
			current.resultReason = "abandoned"
			break
		end
		publishRun(nil)
		task.wait(math.min(dungeon.snapshotSeconds, 0.25))
	end

	current.startClock = os.clock()
	current.nextSlamAt = current.startClock + dungeon.slamIntervalSeconds
	if result == nil then
		-- Everyone enters combat at full health. If a body disappeared between
		-- preparation and this boundary it has spent its one life and is excluded.
		for _, player in party do
			if not current.eliminated[player] then
				local _, humanoid = characterRoot(player)
				if humanoid == nil or humanoid.Health <= 0 then
					eliminatePlayer(current, player)
				else
					humanoid.Health = humanoid.MaxHealth
				end
			end
		end
		current.phase = "fight"
		publishRun(nil)
	end
	local lastClock = current.startClock

	while result == nil do
		task.wait(dungeon.tickSeconds)
		now = os.clock()
		local dt = now - lastClock
		lastClock = now

		if #presentParty(party) == 0 then
			result = "defeat"
			current.resultReason = "abandoned"
			break
		end

		if dungeon.proximityAutoDps then
			local attackers = attackersInRing(current, core.Position, dungeon.damageRingRadius)
			current.health =
				DungeonLogic.applyDamage(current.health, DungeonLogic.partyDps(boss, attackers), dt)
		end

		-- Boss defeat wins ties against a simultaneous party wipe.
		if DungeonLogic.isDefeated(current.health) then
			result = "victory"
			current.resultReason = "bossDefeated"
			break
		end
		if now - current.startClock >= boss.timeLimitSeconds then
			result = "defeat"
			current.resultReason = "timeout"
			break
		end

		current.allDeadSince =
			DungeonLogic.nextAllDeadSince(current.allDeadSince, alivePartyCount(current), now)
		if DungeonLogic.isPartyWiped(current.allDeadSince, now, dungeon.wipeGraceSeconds) then
			result = "defeat"
			current.resultReason = "partyWipe"
			break
		end

		local nextPhase =
			DungeonLogic.phaseForHealth(current.health, current.maxHealth, dungeon.enrageHealthFraction)
		if nextPhase ~= current.phaseIndex then
			current.phaseIndex = nextPhase
			publishRun(nil)
		end

		if current.telegraphUntil ~= nil then
			if now >= current.telegraphUntil then
				finishSlam(current, now)
			end
		elseif now >= current.nextSlamAt then
			beginSlam(current, now)
		end

		if now - lastSnapshot >= dungeon.snapshotSeconds then
			lastSnapshot = now
			publishRun(nil)
		end
	end

	-- Invalidate every pending character-preparation/dodge task before any final
	-- cleanup. Those tasks all check the run token again after their yields.
	current.active = false
	for _, connection in current.connections do
		connection:Disconnect()
	end
	for _, player in party do
		local _, humanoid = characterRoot(player)
		if humanoid ~= nil then
			humanoid.WalkSpeed = originalWalkSpeeds[player] or StarterPlayer.CharacterWalkSpeed
		end
	end
	setBossDanger(core, false)
	setSlamTelegraph(marker, nil, current.phaseIndex)
	current.telegraphUntil = nil
	current.telegraphCenter = nil
	current.telegraphPhase = nil
	current.phase = result or "defeat"
	local survivors = presentParty(party)

	local target = deps
	if result == "victory" and target ~= nil then
		local rewardWeapon = if boss.rewardItemId ~= nil
			then DungeonConfig.weaponById(dungeon, boss.rewardItemId)
			else nil
		for _, player in survivors do
			if target.ready(player) then
				local actualCurrencyId: string? = nil
				local actualCurrencyAmount = 0
				local granted, grantedAmount =
					target.award(player, boss.rewardCurrencyId, boss.rewardAmount, `dungeon:{boss.id}`)
				if granted then
					actualCurrencyId = boss.rewardCurrencyId
					actualCurrencyAmount = grantedAmount
				elseif target.fallbackCurrencyId ~= boss.rewardCurrencyId then
					local fallbackGranted, fallbackAmount = target.award(
						player,
						target.fallbackCurrencyId,
						boss.rewardAmount,
						`dungeon:{boss.id}`
					)
					if fallbackGranted then
						actualCurrencyId = target.fallbackCurrencyId
						actualCurrencyAmount = fallbackAmount
					end
				end

				local actualItemId: string? = nil
				local actualItemQuantity = 0
				if boss.rewardItemId ~= nil and boss.rewardItemQuantity ~= nil then
					local itemGranted, itemQuantity =
						target.grantItem(player, boss.rewardItemId, boss.rewardItemQuantity)
					if itemGranted then
						actualItemId = boss.rewardItemId
						actualItemQuantity = itemQuantity
					end
				end
				current.rewardByUserId[tostring(player.UserId)] = {
					currencyId = actualCurrencyId,
					currencyAmount = actualCurrencyAmount,
					itemId = actualItemId,
					itemName = if actualItemId ~= nil
						then if rewardWeapon ~= nil then rewardWeapon.name else actualItemId
						else nil,
					itemQuantity = actualItemQuantity,
				}
			end
		end
	end

	-- Final state is emitted only after mutations succeed, so each player sees
	-- the exact server-granted reward rather than a configured promise.
	publishRun(result)
	run = nil
	return result or "defeat", survivors
end

local function strikeHasLineOfSight(current: Run, root: BasePart, core: BasePart): boolean
	local bossModel = core.Parent
	if bossModel == nil then
		return false
	end
	local excluded: { Instance } = {}
	for _, member in current.party do
		if member.Character ~= nil then
			table.insert(excluded, member.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	params.RespectCanCollide = false
	local origin = root.Position + Vector3.new(0, 1.25, 0)
	local direction = core.Position - origin
	if direction.Magnitude <= 1e-5 then
		return true
	end
	direction = direction.Unit * (direction.Magnitude + dungeon.strikeRaycastPaddingStuds)
	local hit = Workspace:Raycast(origin, direction, params)
	return hit ~= nil and hit.Instance:IsDescendantOf(bossModel)
end

local function isInsideAuthoredArena(current: Run, root: BasePart): boolean
	local floor = current.arenaFloor
	if floor == nil or floor.Parent == nil then
		return false
	end
	local point = floor.CFrame:PointToObjectSpace(root.Position)
	local size = floor.Size
	if floor:IsA("Part") and floor.Shape == Enum.PartType.Cylinder then
		-- Cylinder parts use local X as their axis. The arena's authored rotation
		-- therefore defines both its vertical band and horizontal playable radius.
		local radialLimit = math.min(size.Y, size.Z) * 0.5 + 2
		local radialDistance = math.sqrt(point.Y * point.Y + point.Z * point.Z)
		return math.abs(point.X) <= size.X * 0.5 + dungeon.slamHeightToleranceStuds
			and radialDistance <= radialLimit
	end
	return math.abs(point.X) <= size.X * 0.5 + 2
		and math.abs(point.Z) <= size.Z * 0.5 + 2
		and math.abs(point.Y) <= size.Y * 0.5 + dungeon.slamHeightToleranceStuds
end

local function ensureMatchingDungeonWeapon(
	current: Run,
	player: Player,
	humanoid: Humanoid,
	weapon: DungeonConfig.Weapon
): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	if matchingDungeonTool(character, weapon, current.token) ~= nil then
		return true
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local stored = matchingDungeonTool(backpack, weapon, current.token)
	if stored ~= nil then
		humanoid:EquipTool(stored)
		return stored.Parent == character
	end
	return equipDungeonWeapon(current, player, humanoid, weapon)
end

-- Payload-free basic strike. The server resolves the saved weapon and validates
-- liveness, cooldown, facing, distance, height, and obstruction before damage.
function DungeonService.registerHit(player: Player): (boolean, string, number?)
	local current = run
	if current == nil or not current.active or current.phase ~= "fight" then
		return false, "inactive", nil
	end
	if table.find(current.party, player) == nil then
		return false, "notParty", nil
	end
	if current.eliminated[player] then
		return false, "eliminated", nil
	end
	local root, humanoid = characterRoot(player)
	if root == nil or humanoid == nil or humanoid.Health <= 0 then
		return false, "down", nil
	end
	local core = current.core
	local weapon = current.weapons[player]
	if core == nil or weapon == nil then
		return false, "unavailable", nil
	end
	if not isInsideAuthoredArena(current, root) then
		return false, "outOfArena", nil
	end
	local now = os.clock()
	if now - (current.lastHitAt[player] or 0) < weapon.cooldownSeconds then
		return false, "cooldown", nil
	end
	local offset = core.Position - root.Position
	local look = root.CFrame.LookVector
	if
		not DungeonLogic.canStrike(
			offset.X,
			offset.Y,
			offset.Z,
			look.X,
			look.Z,
			weapon.rangeStuds,
			weapon.verticalToleranceStuds,
			weapon.facingDot
		)
	then
		return false, "outOfRange", nil
	end
	if not strikeHasLineOfSight(current, root, core) then
		return false, "blocked", nil
	end
	if not ensureMatchingDungeonWeapon(current, player, humanoid, weapon) then
		return false, "weaponUnavailable", nil
	end
	current.lastHitAt[player] = now
	current.health = DungeonLogic.applyHit(current.health, weapon.damage)
	return true, "hit", weapon.damage
end

-- Server-owned dodge impulse. Direction comes from the replicated Humanoid,
-- never from the request payload, and is rate/cooldown bounded independently.
function DungeonService.registerDodge(player: Player): (boolean, string)
	local current = run
	if current == nil or not current.active or current.phase ~= "fight" then
		return false, "inactive"
	end
	if table.find(current.party, player) == nil then
		return false, "notParty"
	end
	if current.eliminated[player] then
		return false, "eliminated"
	end
	local root, humanoid = characterRoot(player)
	if root == nil or humanoid == nil or humanoid.Health <= 0 then
		return false, "down"
	end
	local now = os.clock()
	if now - (current.lastDodgeAt[player] or 0) < dungeon.dodgeCooldownSeconds then
		return false, "cooldown"
	end
	local direction = humanoid.MoveDirection
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.05 then
		local look = root.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
	end
	if direction.Magnitude < 0.05 then
		return false, "noDirection"
	end
	direction = direction.Unit
	current.lastDodgeAt[player] = now
	local vertical = math.max(root.AssemblyLinearVelocity.Y, 2)
	root.AssemblyLinearVelocity =
		Vector3.new(direction.X * dungeon.dodgeSpeed, vertical, direction.Z * dungeon.dodgeSpeed)
	task.delay(dungeon.dodgeDurationSeconds, function()
		if
			not isCurrentRun(current)
			or current.lastDodgeAt[player] ~= now
			or root.Parent == nil
			or current.eliminated[player]
		then
			return
		end
		local velocity = root.AssemblyLinearVelocity
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
		if horizontal.Magnitude > dungeon.walkSpeed then
			horizontal = horizontal.Unit * dungeon.walkSpeed
			root.AssemblyLinearVelocity = Vector3.new(horizontal.X, velocity.Y, horizontal.Z)
		end
	end)
	return true, "dodged"
end

-- Hotbar ability (keys 1-4). Reuses the same liveness, arena, and equipped-weapon
-- authority as a basic strike, then applies the configured per-kind effect under a
-- per-player, per-ability cooldown. Damage kinds subtract the caster's weapon
-- damage (scaled) from the shared boss health; "heal" restores only the caster's
-- own humanoid and never touches the boss. The client supplies only the ability id.
function DungeonService.useAbility(player: Player, abilityId: string): (boolean, string, number?)
	local current = run
	if current == nil or not current.active or current.phase ~= "fight" then
		return false, "inactive", nil
	end
	if table.find(current.party, player) == nil then
		return false, "notParty", nil
	end
	if current.eliminated[player] then
		return false, "eliminated", nil
	end
	local ability = DungeonConfig.abilityById(dungeon, abilityId)
	if ability == nil then
		return false, "unknownAbility", nil
	end
	local root, humanoid = characterRoot(player)
	if root == nil or humanoid == nil or humanoid.Health <= 0 then
		return false, "down", nil
	end
	if not isInsideAuthoredArena(current, root) then
		return false, "outOfArena", nil
	end
	local now = os.clock()
	local cooldowns = current.lastAbilityAt[player]
	if cooldowns == nil then
		cooldowns = {}
		current.lastAbilityAt[player] = cooldowns
	end
	if now - (cooldowns[abilityId] or -math.huge) < ability.cooldownSeconds then
		return false, "cooldown", nil
	end

	-- Self-heal never needs the boss, a weapon, or a facing check.
	if ability.kind == "heal" then
		local missingHealth = math.max(0, humanoid.MaxHealth - humanoid.Health)
		local restoredHealth = math.min(missingHealth, math.max(0, ability.healAmount))
		if restoredHealth <= 0 then
			return false, "fullHealth", nil
		end
		humanoid.Health += restoredHealth
		cooldowns[abilityId] = now
		return true, "healed", restoredHealth
	end

	local core = current.core
	local weapon = current.weapons[player]
	if core == nil or weapon == nil then
		return false, "unavailable", nil
	end
	local offset = core.Position - root.Position
	if ability.kind == "cleave" then
		-- A spin hits anything inside the radius; no facing requirement.
		if
			not DungeonLogic.isWithinCylinder(
				offset.X,
				offset.Y,
				offset.Z,
				ability.rangeStuds,
				weapon.verticalToleranceStuds
			)
		then
			return false, "outOfRange", nil
		end
	else
		-- "strike" and "ranged" both need range/facing plus an unobstructed line.
		local look = root.CFrame.LookVector
		if
			not DungeonLogic.canStrike(
				offset.X,
				offset.Y,
				offset.Z,
				look.X,
				look.Z,
				ability.rangeStuds,
				weapon.verticalToleranceStuds,
				weapon.facingDot
			)
		then
			return false, "outOfRange", nil
		end
		if not strikeHasLineOfSight(current, root, core) then
			return false, "blocked", nil
		end
	end
	if not ensureMatchingDungeonWeapon(current, player, humanoid, weapon) then
		return false, "weaponUnavailable", nil
	end
	local damage = weapon.damage * math.max(0, ability.damageMultiplier)
	cooldowns[abilityId] = now
	current.health = DungeonLogic.applyHit(current.health, damage)
	return true, "hit", damage
end

function DungeonService.forget(player: Player)
	local current = run
	if current ~= nil and current.phase == "fight" and table.find(current.party, player) ~= nil then
		eliminatePlayer(current, player)
	end
	pendingTeleports[player] = nil
	returningWhenProfileReady[player] = nil
end

local function userIds(players: { Player }): { number }
	local ids: { number } = {}
	for _, player in players do
		table.insert(ids, player.UserId)
	end
	return ids
end

local function notifyPlayers(players: { Player }, message: string)
	local target = deps
	if target == nil then
		return
	end
	for _, player in players do
		if player.Parent == Players then
			target.notify(player, message)
		end
	end
end

local function publishInactive(players: { Player })
	local target = deps
	if target ~= nil then
		target.publish(players, { active = false })
	end
end

local function attemptEncounterCleanup(label: string, callback: () -> ())
	local ok, problem = pcall(callback)
	if not ok then
		warn(`Dungeon {label} cleanup failed: {problem}`)
	end
end

-- `runFight` contains the yielding encounter loop. Keep one narrow finalizer at
-- its boundary so an unexpected authored-instance, publish, or reward failure
-- cannot strand a party in combat or leave stale callbacks mutating a later run.
local function runFightSafely(party: { Player }, bossId: string, core: BasePart): (string, { Player })
	local outcome: string? = nil
	local survivors: { Player } = {}
	local ok, failure = xpcall(function()
		outcome, survivors = runFight(party, bossId, core)
	end, function(problem)
		return tostring(problem)
	end)
	if ok then
		return outcome or "defeat", survivors
	end

	warn(`Dungeon encounter failed safely:\n{failure}`)
	local current = run
	if current ~= nil then
		current.active = false
		current.telegraphUntil = nil
		current.telegraphCenter = nil
		current.telegraphPhase = nil
		run = nil
		attemptEncounterCleanup("connection", function()
			for _, connection in current.connections do
				connection:Disconnect()
			end
		end)
		attemptEncounterCleanup("presentation", function()
			setBossDanger(current.core, false)
			setSlamTelegraph(current.slamTelegraph, nil, current.phaseIndex)
		end)
	end
	attemptEncounterCleanup("movement", function()
		for _, player in party do
			local _, humanoid = characterRoot(player)
			if humanoid ~= nil then
				humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
			end
		end
	end)
	attemptEncounterCleanup("tool", function()
		clearPartyTools(party)
	end)
	attemptEncounterCleanup("notice", function()
		notifyPlayers(party, "The dungeon encounter stopped safely. Returning to the lobby.")
	end)
	attemptEncounterCleanup("state", function()
		publishInactive(party)
	end)
	return "defeat", presentParty(party)
end

local function terminalTeleportFailure(player: Player, pending: PendingTeleport)
	if pendingTeleports[player] ~= pending then
		return
	end
	pendingTeleports[player] = nil
	notifyPlayers({ player }, pending.terminalMessage)
end

local function retryDelay(attempts: number): number
	return math.min(2 ^ math.max(0, attempts - 1), 8)
end

local function pendingPlayers(players: { Player }, kind: string, launchId: string): { Player }
	local result: { Player } = {}
	local seen: { [Player]: boolean } = {}
	for _, player in players do
		local pending = pendingTeleports[player]
		if
			player.Parent == Players
			and not seen[player]
			and pending ~= nil
			and pending.kind == kind
			and pending.launchId == launchId
		then
			seen[player] = true
			table.insert(result, player)
		end
	end
	return result
end

local function attemptTeleport(
	players: { Player },
	placeId: number,
	options: TeleportOptions,
	kind: string,
	launchId: string
)
	local active = pendingPlayers(players, kind, launchId)
	if #active == 0 then
		return
	end
	local maxAttempts = dungeon.teleportRetries + 1
	local attempted: { Player } = {}
	for _, player in active do
		local pending = pendingTeleports[player]
		if pending ~= nil then
			if pending.attempts >= maxAttempts then
				terminalTeleportFailure(player, pending)
			else
				pending.retryScheduled = false
				pending.attempts += 1
				table.insert(attempted, player)
			end
		end
	end
	if #attempted == 0 then
		return
	end

	local ok, issue = pcall(function()
		return TeleportService:TeleportAsync(placeId, attempted, options)
	end)
	if ok then
		-- The pending entries remain until PlayerRemoving confirms departure or
		-- TeleportInitFailed supplies destination-preserving retry options.
		return
	end
	warn(`Dungeon teleport could not start: {tostring(issue)}`)

	local retry: { Player } = {}
	local delaySeconds = 1
	for _, player in attempted do
		local pending = pendingTeleports[player]
		if pending ~= nil then
			if pending.attempts >= maxAttempts then
				terminalTeleportFailure(player, pending)
			else
				pending.retryScheduled = true
				delaySeconds = math.max(delaySeconds, retryDelay(pending.attempts))
				table.insert(retry, player)
			end
		end
	end
	if #retry > 0 then
		task.delay(delaySeconds, function()
			local stillPending = pendingPlayers(retry, kind, launchId)
			for _, player in stillPending do
				local pending = pendingTeleports[player]
				if pending ~= nil then
					pending.retryScheduled = false
				end
			end
			attemptTeleport(stillPending, placeId, options, kind, launchId)
		end)
	end
end

local function beginTeleport(
	players: { Player },
	options: TeleportOptions,
	kind: string,
	launchId: string,
	terminalMessage: string
): boolean
	if RunService:IsStudio() then
		return false
	end
	local accepted: { Player } = {}
	local seen: { [Player]: boolean } = {}
	for _, player in players do
		if player.Parent == Players and not seen[player] and pendingTeleports[player] == nil then
			seen[player] = true
			pendingTeleports[player] = {
				kind = kind,
				launchId = launchId,
				attempts = 0,
				retryScheduled = false,
				terminalMessage = terminalMessage,
			}
			table.insert(accepted, player)
		end
	end
	if #accepted == 0 then
		return false
	end
	task.spawn(attemptTeleport, accepted, game.PlaceId, options, kind, launchId)
	return true
end

-- Dungeon launches must claim the finalized party atomically. This helper does
-- not yield: it first validates the complete roster, then installs every
-- pending entry before the caller can report success to PortalService. Return
-- teleports intentionally keep beginTeleport's best-effort subset behavior.
local function beginExactTeleport(
	players: { Player },
	options: TeleportOptions,
	kind: string,
	launchId: string,
	terminalMessage: string
): boolean
	if RunService:IsStudio() or #players == 0 then
		return false
	end
	local seen: { [Player]: boolean } = {}
	for _, player in players do
		if player.Parent ~= Players or seen[player] or pendingTeleports[player] ~= nil then
			return false
		end
		seen[player] = true
	end
	for _, player in players do
		pendingTeleports[player] = {
			kind = kind,
			launchId = launchId,
			attempts = 0,
			retryScheduled = false,
			terminalMessage = terminalMessage,
		}
	end
	task.spawn(attemptTeleport, players, game.PlaceId, options, kind, launchId)
	return true
end

local function teleportDataIdentity(options: TeleportOptions): (string?, string?)
	local ok, data = pcall(function()
		return options:GetTeleportData()
	end)
	if
		ok
		and type(data) == "table"
		and data.v == 1
		and type(data.kind) == "string"
		and type(data.launchId) == "string"
	then
		return data.kind, data.launchId
	end
	return nil, nil
end

local function installTeleportFailureHandler()
	if teleportFailureConnection ~= nil or RunService:IsStudio() then
		return
	end
	teleportFailureConnection = TeleportService.TeleportInitFailed:Connect(
		function(
			player: Player,
			result: Enum.TeleportResult,
			message: string,
			placeId: number,
			options: TeleportOptions
		)
			local pending = pendingTeleports[player]
			if pending == nil then
				return
			end
			local kind, launchId = teleportDataIdentity(options)
			if placeId ~= game.PlaceId or kind ~= pending.kind or launchId ~= pending.launchId then
				warn(`Ignoring unrelated teleport failure for {player.Name}: {message}`)
				return
			end
			if result ~= Enum.TeleportResult.Failure and result ~= Enum.TeleportResult.Flooded then
				warn(`Dungeon teleport failed permanently for {player.Name} ({result.Name}): {message}`)
				terminalTeleportFailure(player, pending)
				return
			end
			if player.Parent ~= Players or pending.attempts >= dungeon.teleportRetries + 1 then
				terminalTeleportFailure(player, pending)
				return
			end
			if pending.retryScheduled then
				return
			end
			pending.retryScheduled = true
			local expected = pending
			local delaySeconds = if result == Enum.TeleportResult.Flooded
				then 15
				else retryDelay(pending.attempts)
			task.delay(delaySeconds, function()
				if pendingTeleports[player] ~= expected or player.Parent ~= Players then
					return
				end
				expected.retryScheduled = false
				attemptTeleport({ player }, placeId, options, expected.kind, expected.launchId)
			end)
		end
	)
end

local function teleportToLobby(players: { Player }): boolean
	local options = Instance.new("TeleportOptions")
	local launchId = HttpService:GenerateGUID(false)
	options:SetTeleportData({
		kind = "DungeonReturn",
		v = 1,
		launchId = launchId,
	})
	return beginTeleport(
		players,
		options,
		"DungeonReturn",
		launchId,
		"The return portal could not open. Please rejoin the game."
	)
end

local function queueReturnWhenProfileReady(player: Player)
	if player.Parent ~= Players or pendingTeleports[player] ~= nil or returningWhenProfileReady[player] then
		return
	end
	returningWhenProfileReady[player] = true
	task.spawn(function()
		-- ProfileService may already be inside UpdateAsync and acquiring the
		-- session lock. Teleporting before it publishes the loaded profile can
		-- orphan that lock, so remain here until loading succeeds or init removes
		-- the player after a terminal load failure.
		while returningWhenProfileReady[player] and player.Parent == Players do
			local target = deps
			if target ~= nil and target.ready(player) then
				break
			end
			task.wait(0.2)
		end
		if not returningWhenProfileReady[player] then
			return
		end
		returningWhenProfileReady[player] = nil
		local target = deps
		if player.Parent == Players and target ~= nil and target.ready(player) then
			teleportToLobby({ player })
		end
	end)
end

local function returnPlayersWhenProfileReady(players: { Player })
	local target = deps
	if target == nil then
		return
	end
	local ready: { Player } = {}
	local seen: { [Player]: boolean } = {}
	for _, player in players do
		if
			player.Parent == Players
			and not seen[player]
			and pendingTeleports[player] == nil
			and not returningWhenProfileReady[player]
		then
			seen[player] = true
			if target.ready(player) then
				table.insert(ready, player)
			else
				queueReturnWhenProfileReady(player)
			end
		end
	end
	if #ready > 0 then
		teleportToLobby(ready)
	end
end

local function readManifest(player: Player): DungeonLogic.PartyManifest?
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		return nil
	end
	return DungeonLogic.normalizePartyManifest(joinData.TeleportData, dungeon.partyMax)
end

local function sameManifest(left: DungeonLogic.PartyManifest, right: DungeonLogic.PartyManifest): boolean
	if left.launchId ~= right.launchId or #left.party ~= #right.party then
		return false
	end
	for index, userId in left.party do
		if right.party[index] ~= userId then
			return false
		end
	end
	return true
end

local function manifestFromAnyArrival(): DungeonLogic.PartyManifest?
	for _, player in Players:GetPlayers() do
		local manifest = readManifest(player)
		if manifest ~= nil and table.find(manifest.party, player.UserId) ~= nil then
			return manifest
		end
	end
	return nil
end

local function matchingParty(manifest: DungeonLogic.PartyManifest): { Player }
	local party: { Player } = {}
	for _, userId in manifest.party do
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil and player.Parent == Players then
			local arrivalManifest = readManifest(player)
			if arrivalManifest ~= nil and sameManifest(manifest, arrivalManifest) then
				table.insert(party, player)
			end
		end
	end
	return party
end

local function waitForManifest(): DungeonLogic.PartyManifest?
	local deadline = os.clock() + dungeon.arrivalTimeoutSeconds
	repeat
		local manifest = manifestFromAnyArrival()
		if manifest ~= nil then
			return manifest
		end
		task.wait(0.2)
	until os.clock() >= deadline
	return nil
end

local function waitForParty(manifest: DungeonLogic.PartyManifest): { Player }
	local deadline = os.clock() + dungeon.arrivalTimeoutSeconds
	local party = matchingParty(manifest)
	while #party < #manifest.party and os.clock() < deadline do
		task.wait(0.2)
		party = matchingParty(manifest)
	end
	return party
end

local function waitForReadyParty(party: { Player }): { Player }
	local target = deps
	if target == nil then
		return {}
	end
	local deadline = os.clock() + dungeon.profileReadyTimeoutSeconds
	while os.clock() < deadline do
		local present: { Player } = {}
		local allReady = true
		for _, player in party do
			if player.Parent == Players then
				table.insert(present, player)
				if not target.ready(player) then
					allReady = false
				end
			end
		end
		if allReady then
			return present
		end
		task.wait(0.2)
	end

	-- One slow or departing member must not strand everyone else. The run can
	-- safely continue with only the connected members whose profiles are owned.
	local ready: { Player } = {}
	for _, player in party do
		if player.Parent == Players and target.ready(player) then
			table.insert(ready, player)
		end
	end
	return ready
end

local function isAdmittedArrival(player: Player): boolean
	local admitted = admittedUserIds
	if admitted == nil or admitted[player.UserId] ~= true then
		return false
	end
	local manifest = lockedManifest
	if manifest == nil then
		return false
	end
	local arrivalManifest = readManifest(player)
	return arrivalManifest ~= nil and sameManifest(manifest, arrivalManifest)
end

local function returnUnadmittedPlayer(player: Player)
	if player.Parent ~= Players or pendingTeleports[player] ~= nil or returningWhenProfileReady[player] then
		return
	end
	notifyPlayers({ player }, "This dungeon party has already departed. Returning to the lobby.")
	returnPlayersWhenProfileReady({ player })
end

local function returnUnadmittedPlayers()
	for _, player in Players:GetPlayers() do
		if not isAdmittedArrival(player) then
			returnUnadmittedPlayer(player)
		end
	end
end

local function lockDungeonRoster(manifest: DungeonLogic.PartyManifest?, party: { Player })
	lockedManifest = manifest
	local admitted: { [number]: boolean } = {}
	for _, player in party do
		if player.Parent == Players then
			admitted[player.UserId] = true
		end
	end
	admittedUserIds = admitted
	returnUnadmittedPlayers()
end

local function closeDungeonAdmission()
	lockedManifest = nil
	admittedUserIds = {}
end

local function installDungeonArrivalHandler()
	if dungeonArrivalConnection ~= nil or RunService:IsStudio() then
		return
	end
	dungeonArrivalConnection = Players.PlayerAdded:Connect(function(player)
		-- Deferring closes the tiny boundary where PlayerAdded fires after the
		-- final collection scan but immediately before the roster is locked.
		task.defer(function()
			if admittedUserIds ~= nil and not isAdmittedArrival(player) then
				returnUnadmittedPlayer(player)
			end
		end)
	end)
end

local function abortDungeon(message: string)
	-- An aborted reserved server admits nobody. This also ensures arrivals that
	-- complete after the abort are immediately sent back instead of being stuck.
	closeDungeonAdmission()
	local players = Players:GetPlayers()
	notifyPlayers(players, message)
	publishInactive(players)
	returnPlayersWhenProfileReady(players)
	runInProgress = false
end

local function studioDungeonParty(): { Player }
	local deadline = os.clock() + dungeon.arrivalTimeoutSeconds
	while #Players:GetPlayers() == 0 and os.clock() < deadline do
		task.wait(0.2)
	end
	local party: { Player } = {}
	for _, player in Players:GetPlayers() do
		if #party >= dungeon.partyMax then
			break
		end
		table.insert(party, player)
	end
	return party
end

-- Reserved dungeon server: validate the server-created manifest, wait for the
-- expected users and their profiles, run the fight, then return to public lobby.
local function runDungeonServer()
	if runInProgress then
		return
	end
	runInProgress = true
	if RunService:IsStudio() then
		local party = studioDungeonParty()
		local core = findBossCore(findArena())
		party = waitForReadyParty(party)
		if #party == 0 or core == nil then
			abortDungeon("The simulated dungeon could not start safely.")
			return
		end
		runFightSafely(party, dungeon.defaultBossId, core)
		task.wait(4)
		publishInactive(party)
		clearPartyTools(party)
		runInProgress = false
		return
	end

	local manifest = waitForManifest()
	if manifest == nil then
		abortDungeon("This reserved server is not a valid dungeon session.")
		return
	end
	local party = waitForParty(manifest)
	if #party == 0 then
		abortDungeon("No valid dungeon party arrived. Returning to the lobby.")
		return
	end
	-- Freeze the arrival roster before any further waits. Matching players whose
	-- teleport completes later are returned by the arrival handler.
	lockDungeonRoster(manifest, party)
	local core = findBossCore(findArena())
	if core == nil then
		abortDungeon("The dungeon arena is unavailable. Returning to the lobby.")
		return
	end
	party = waitForReadyParty(party)
	if #party == 0 then
		abortDungeon("Party data was not ready safely. Returning to the lobby.")
		return
	end
	-- Profile loading can outlive a departing party member. Narrow admission to
	-- the ready, connected subset and return anyone who could not safely join.
	lockDungeonRoster(manifest, party)

	-- The boss is resolved server-authoritatively on the lobby and handed over in
	-- a store keyed by the server-generated launch id -- never via client-visible
	-- TeleportData. Re-validate the record shape, launch identity, and boss id;
	-- anything off falls back to the default.
	local bossId = dungeon.defaultBossId
	local record = DungeonBossSelection.normalizeSessionRecord(DungeonSessionStore.read(manifest.launchId))
	if
		record ~= nil
		and record.launchId == manifest.launchId
		and DungeonConfig.bossById(dungeon, record.bossId) ~= nil
	then
		bossId = record.bossId
	end
	-- The session read yields. A party member can depart during it, so refresh the
	-- ready connected subset and admission lock before boss health/rewards are
	-- sized from the party table.
	party = waitForReadyParty(party)
	if #party == 0 then
		abortDungeon("The dungeon party left before the encounter began.")
		return
	end
	lockDungeonRoster(manifest, party)
	runFightSafely(party, bossId, core)
	task.wait(4)
	publishInactive(party)
	clearPartyTools(party)
	closeDungeonAdmission()
	returnPlayersWhenProfileReady(Players:GetPlayers())
	runInProgress = false
end

-- Studio-only: run the same fight in-place (no teleport), then set characters
-- back where they were so the loop is testable without a published place. The
-- boss is passed in-process (no reserve/store) so selection is testable in Studio.
local function simulateInPlace(players: { Player }, bossId: string)
	local requestedPlayers = players
	local returnStates: { [Player]: StudioReturnState } = {}
	for _, player in players do
		local character = player.Character
		if character ~= nil then
			local humanoid = character:FindFirstChildWhichIsA("Humanoid")
			returnStates[player] = {
				pivot = character:GetPivot(),
				walkSpeed = if humanoid ~= nil then humanoid.WalkSpeed else nil,
				health = if humanoid ~= nil then humanoid.Health else nil,
			}
		end
	end
	local core = findBossCore(findArena())
	if core == nil then
		notifyPlayers(players, "The dungeon arena is unavailable.")
		publishInactive(players)
		runInProgress = false
		return
	end
	players = waitForReadyParty(players)
	if #players == 0 then
		notifyPlayers(requestedPlayers, "Party data was not ready safely.")
		publishInactive(requestedPlayers)
		runInProgress = false
		return
	end

	runFightSafely(players, bossId, core)
	task.wait(4)
	publishInactive(players)
	clearPartyTools(players)

	for _, player in players do
		local character = player.Character
		local returnState = returnStates[player]
		if character ~= nil and returnState ~= nil then
			character:PivotTo(returnState.pivot)
			local humanoid = character:FindFirstChildWhichIsA("Humanoid")
			if humanoid ~= nil then
				if returnState.walkSpeed ~= nil then
					humanoid.WalkSpeed = returnState.walkSpeed
				end
				if returnState.health ~= nil then
					humanoid.Health = math.clamp(returnState.health, 0, humanoid.MaxHealth)
				end
			end
		end
	end
	runInProgress = false
end

local function launchablePlayers(players: { Player }): { Player }?
	local result: { Player } = {}
	local seen: { [Player]: boolean } = {}
	local target = deps
	if target == nil then
		return nil
	end
	local selectedCount = #players
	if selectedCount == 0 or selectedCount > dungeon.partyMax then
		return nil
	end
	for index = 1, selectedCount do
		local player = players[index]
		-- The roster shown on the portal is atomic: if any selected member is
		-- disconnected, duplicated, already teleporting, or not profile-ready,
		-- keep the whole roster on the pad and retry after the short backoff.
		if
			player == nil
			or player.Parent ~= Players
			or seen[player]
			or pendingTeleports[player] ~= nil
			or not target.ready(player)
		then
			return nil
		end
		seen[player] = true
		table.insert(result, player)
	end
	return result
end

local function teleportPartyToReservedServer(players: { Player }, bossId: string): boolean
	-- Preserve one exact roster while the session write yields. This first
	-- validation also copies the caller-owned table so the post-write check
	-- cannot be weakened by a mutation of that table.
	local roster = launchablePlayers(players)
	if roster == nil then
		return false
	end
	local launchId = HttpService:GenerateGUID(false)
	-- Store the boss under an opaque server-generated launch id before teleport.
	-- A write failure is non-fatal: the destination safely falls back to its
	-- configured default boss. The write may yield, so revalidate the complete
	-- roster before deriving the manifest and claiming pending teleport state.
	DungeonSessionStore.write(launchId, { v = 1, bossId = bossId, launchId = launchId })
	local finalRoster = launchablePlayers(roster)
	if finalRoster == nil then
		return false
	end
	local ids = DungeonLogic.normalizePartyIds(userIds(finalRoster), dungeon.partyMax)
	if ids == nil or #ids ~= #finalRoster then
		return false
	end

	local options = Instance.new("TeleportOptions")
	-- Keep reservation and teleport in Roblox's proven atomic path. The previous
	-- split reserve/access-code handoff regressed the countdown rune by putting a
	-- separate reservation request on its launch path.
	options.ShouldReserveServer = true
	options:SetTeleportData({
		kind = "DungeonParty",
		v = 1,
		launchId = launchId,
		party = ids,
	})
	return beginExactTeleport(
		finalRoster,
		options,
		"DungeonParty",
		launchId,
		"The dungeon portal is busy. Please try again."
	)
end

-- Lobby-server entry point used by PortalService when the pad countdown ends.
-- `bossId` is the boss the lobby resolved for this run (event > party > personal
-- > default); runFight re-validates it against the catalog on the destination.
function DungeonService.launchParty(players: { Player }, bossId: string): boolean
	local accepted = launchablePlayers(players)
	if accepted == nil then
		return false
	end
	if RunService:IsStudio() then
		if runInProgress then
			return false
		end
		runInProgress = true
		task.spawn(simulateInPlace, accepted, bossId)
		return true
	end
	return teleportPartyToReservedServer(accepted, bossId)
end

-- Lobby request entry: a player picked a boss on the portal. Persist it as their
-- personal default and, when they lead the pad, apply it as the party's pick.
function DungeonService.selectBoss(player: Player, bossId: any): (boolean, string)
	if type(bossId) ~= "string" or DungeonConfig.bossById(dungeon, bossId) == nil then
		return false, "unknownBoss"
	end
	local target = deps
	if target == nil then
		return false, "unavailable"
	end
	if not target.setSavedBossId(player, bossId) then
		return false, "profileUnavailable"
	end
	target.notePadBossPick(player, bossId)
	return true, bossId
end

-- Admin-only: force (or clear) the global event boss. The allowlist is enforced
-- here on the server, so a non-admin request is always rejected regardless of how
-- it was triggered. A nil/empty/"off" id clears the event; `durationMinutes`
-- optionally auto-expires it (capped at a week).
function DungeonService.setEventBoss(
	userId: number,
	bossId: string?,
	durationMinutes: number?
): (boolean, string)
	local allowed = false
	for _, adminId in dungeon.eventAdminUserIds do
		if adminId == userId then
			allowed = true
			break
		end
	end
	if not allowed then
		return false, "You are not allowed to set the dungeon event boss."
	end
	if
		durationMinutes ~= nil
		and (
			type(durationMinutes) ~= "number"
			or durationMinutes ~= durationMinutes
			or durationMinutes == math.huge
			or durationMinutes == -math.huge
			or durationMinutes <= 0
		)
	then
		return false, "Duration must be a finite number greater than zero."
	end
	if bossId == nil or bossId == "" or bossId == "off" then
		if not DungeonEventStore.set(nil, nil) then
			return false, "The dungeon event store could not be cleared."
		end
		return true, "Dungeon event boss cleared."
	end
	if DungeonConfig.bossById(dungeon, bossId) == nil then
		return false, `Unknown boss "{bossId}".`
	end
	local untilTime: number? = nil
	if durationMinutes ~= nil then
		untilTime = os.time() + math.max(1, math.floor(math.min(durationMinutes, 10080) * 60))
	end
	if not DungeonEventStore.set(bossId, untilTime) then
		return false, "The dungeon event store could not be written."
	end
	return true, `Dungeon event boss set to {bossId}.`
end

function DungeonService.start(dependencies: Deps)
	deps = dependencies
	installTeleportFailureHandler()
	if not DungeonService.isDungeonServer() then
		return
	end
	installDungeonArrivalHandler()
	task.spawn(runDungeonServer)
end

return DungeonService
