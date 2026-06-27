--!strict

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Catalogs = require(Shared.Catalogs)
local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)

local InventoryService = {}

function InventoryService.grant(player: Player, itemId: string, quantity: number): boolean
	local profile = ProfileService.get(player)
	local definition = Catalogs.items[itemId]
	if profile == nil or definition == nil or quantity < 1 then
		return false
	end
	local entry = profile.inventory[itemId] or { quantity = 0 }
	entry.quantity = math.clamp(entry.quantity + math.floor(quantity), 0, definition.maxStack)
	profile.inventory[itemId] = entry
	ProfileService.markDirty(player, `inventory:grant:{itemId}`)
	return true
end

function InventoryService.buy(player: Player, itemId: string): (boolean, string)
	local definition = Catalogs.items[itemId]
	if definition == nil or definition.priceCoins == nil then
		return false, "Item is unavailable"
	end
	local profile = ProfileService.get(player)
	if profile == nil then
		return false, "Profile is not loaded"
	end
	local entry = profile.inventory[itemId]
	if entry and entry.quantity >= definition.maxStack then
		return false, "Inventory stack is full"
	end
	if not EconomyService.spend(player, definition.priceCoins, `shop:{itemId}`) then
		return false, "Not enough Coins"
	end
	InventoryService.grant(player, itemId, 1)
	return true, `Purchased {definition.name}`
end

function InventoryService.consume(player: Player, itemId: string): (boolean, string)
	local profile = ProfileService.get(player)
	local definition = Catalogs.items[itemId]
	local entry = if profile then profile.inventory[itemId] else nil
	if profile == nil or definition == nil or entry == nil or entry.quantity < 1 then
		return false, "Item is unavailable"
	end
	if
		definition.category ~= "Consumable"
		or definition.boostMultiplier == nil
		or definition.boostDurationSeconds == nil
	then
		return false, "Item cannot be consumed"
	end

	entry.quantity -= 1
	local now = os.time()
	local found = false
	for _, boost in profile.boosts do
		if boost.id == itemId then
			boost.expiresAt = math.max(boost.expiresAt, now) + definition.boostDurationSeconds
			boost.multiplier = definition.boostMultiplier
			found = true
			break
		end
	end
	if not found then
		table.insert(profile.boosts, {
			id = itemId,
			expiresAt = now + definition.boostDurationSeconds,
			multiplier = definition.boostMultiplier,
		})
	end
	ProfileService.markDirty(player, `inventory:consume:{itemId}`)
	return true, `Activated {definition.name}`
end

function InventoryService.toggleEquip(player: Player, itemId: string): (boolean, string)
	local profile = ProfileService.get(player)
	local definition = Catalogs.items[itemId]
	local entry = if profile then profile.inventory[itemId] else nil
	if profile == nil or definition == nil or entry == nil or entry.quantity < 1 then
		return false, "Item is unavailable"
	end
	if definition.category ~= "Equipment" then
		return false, "Item is not equipment"
	end
	entry.equipped = not entry.equipped
	ProfileService.markDirty(player, `inventory:equip:{itemId}`)
	return true, if entry.equipped then "Equipped" else "Unequipped"
end

return InventoryService
