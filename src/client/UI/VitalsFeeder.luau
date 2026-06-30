--!strict

-- Optional, pack-gated feed of client-LOCAL UI state (health/stamina) into the
-- Store. Health/MaxHealth mirror the character's Humanoid (real engine data);
-- stamina is local UI state that regenerates over time and drains on ability use.
-- Demonstrates the client/server boundary: this never touches the server profile.

local Players = game:GetService("Players")

local VitalsFeeder = {}
VitalsFeeder.__index = VitalsFeeder

local MAX_STAMINA = 100
local REGEN_PER_TICK = 2
local TICK_SECONDS = 0.2

function VitalsFeeder.start(store: any): any
	local self = setmetatable({
		store = store,
		stamina = MAX_STAMINA,
		running = true,
		connections = {} :: { RBXScriptConnection },
	}, VitalsFeeder)

	store:setLocal("local.maxHealth", 100)
	store:setLocal("local.health", 100)
	store:setLocal("local.maxStamina", MAX_STAMINA)
	store:setLocal("local.stamina", MAX_STAMINA)

	self:bindCharacter(Players.LocalPlayer.Character)
	table.insert(
		self.connections,
		Players.LocalPlayer.CharacterAdded:Connect(function(character)
			self:bindCharacter(character)
		end)
	)

	task.spawn(function()
		while self.running do
			task.wait(TICK_SECONDS)
			if self.stamina < MAX_STAMINA then
				self.stamina = math.min(MAX_STAMINA, self.stamina + REGEN_PER_TICK)
				store:setLocal("local.stamina", math.floor(self.stamina))
			end
		end
	end)

	return self
end

function VitalsFeeder.bindCharacter(self: any, character: Instance?)
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if humanoid == nil then
		return
	end
	local function push()
		self.store:setLocal("local.health", math.floor(humanoid.Health))
		self.store:setLocal("local.maxHealth", math.floor(humanoid.MaxHealth))
	end
	push()
	table.insert(self.connections, humanoid.HealthChanged:Connect(push))
	table.insert(self.connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(push))
end

function VitalsFeeder.drainStamina(self: any, amount: number)
	self.stamina = math.max(0, self.stamina - amount)
	self.store:setLocal("local.stamina", math.floor(self.stamina))
end

function VitalsFeeder.stop(self: any)
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return VitalsFeeder
