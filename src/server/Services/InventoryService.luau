--!strict

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Catalogs = require(Shared.Catalogs)
local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)

local InventoryService = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function storedQuantity(entry: any): number?
	if type(entry) ~= "table" then
		return nil
	end
	local quantity = entry.quantity
	if not isFiniteNumber(quantity) or quantity < 0 or quantity % 1 ~= 0 then
		return nil
	end
	return quantity
end

local function clearEquippedSlot(profile: any, slot: string, exceptItemId: string): boolean
	local changed = false
	for ownedItemId, rawEntry in profile.inventory do
		if ownedItemId ~= exceptItemId and type(rawEntry) == "table" then
			local ownedDefinition = Catalogs.items[ownedItemId]
			if
				ownedDefinition ~= nil
				and ownedDefinition.category == "Equipment"
				and ownedDefinition.equipmentSlot == slot
				and rawEntry.equipped == true
			then
				rawEntry.equipped = false
				changed = true
			end
		end
	end
	return changed
end

function InventoryService.grant(player: Player, itemId: string, quantity: number): (boolean, number)
	local profile = ProfileService.get(player)
	local definition = Catalogs.items[itemId]
	if
		profile == nil
		or definition == nil
		or not isFiniteNumber(quantity)
		or quantity < 1
		or quantity % 1 ~= 0
	then
		return false, 0
	end

	local rawEntry: any = profile.inventory[itemId]
	local currentQuantity = if rawEntry == nil then 0 else storedQuantity(rawEntry)
	if currentQuantity == nil then
		return false, 0
	end
	local actualAdded = math.min(quantity, math.max(definition.maxStack - currentQuantity, 0))
	if actualAdded < 1 then
		return false, 0
	end

	if rawEntry == nil then
		rawEntry = { quantity = actualAdded }
		profile.inventory[itemId] = rawEntry
	else
		rawEntry.quantity = currentQuantity + actualAdded
	end
	ProfileService.markDirty(player, `inventory:grant:{itemId}`)
	return true, actualAdded
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
	local entry: any = profile.inventory[itemId]
	local quantity = if entry == nil then 0 else storedQuantity(entry)
	if quantity == nil then
		return false, "Item data is unavailable"
	end
	if quantity >= definition.maxStack then
		return false, "Inventory stack is full"
	end
	if not EconomyService.spend(player, definition.priceCoins, `shop:{itemId}`) then
		return false, "Not enough Coins"
	end
	local granted = InventoryService.grant(player, itemId, 1)
	if not granted then
		return false, "Purchase could not be delivered"
	end
	return true, `Purchased {definition.name}`
end

function InventoryService.consume(player: Player, itemId: string): (boolean, string)
	local profile = ProfileService.get(player)
	local definition = Catalogs.items[itemId]
	local entry: any = if profile then profile.inventory[itemId] else nil
	local quantity = if entry == nil then nil else storedQuantity(entry)
	if profile == nil or definition == nil or entry == nil or quantity == nil or quantity < 1 then
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
	local entry: any = if profile then profile.inventory[itemId] else nil
	local quantity = if entry == nil then nil else storedQuantity(entry)
	if profile == nil or definition == nil or entry == nil or quantity == nil or quantity < 1 then
		return false, "Item is unavailable"
	end
	if definition.category ~= "Equipment" then
		return false, "Item is not equipment"
	end
	local nextEquipped = entry.equipped ~= true
	if nextEquipped and definition.equipmentSlot ~= nil then
		clearEquippedSlot(profile, definition.equipmentSlot, itemId)
	end
	entry.equipped = nextEquipped
	ProfileService.markDirty(player, `inventory:equip:{itemId}`)
	return true, if entry.equipped then "Equipped" else "Unequipped"
end

function InventoryService.equippedItemId(player: Player, slot: string): string?
	local profile = ProfileService.get(player)
	if profile == nil or slot == "" then
		return nil
	end
	local selected: string? = nil
	for itemId, rawEntry in profile.inventory do
		local definition = Catalogs.items[itemId]
		local quantity = storedQuantity(rawEntry)
		if
			definition ~= nil
			and definition.category == "Equipment"
			and definition.equipmentSlot == slot
			and quantity ~= nil
			and quantity >= 1
			and rawEntry.equipped == true
			and (selected == nil or itemId < selected)
		then
			selected = itemId
		end
	end
	return selected
end

function InventoryService.ensureEquipped(player: Player, slot: string, fallbackItemId: string): string?
	local equipped = InventoryService.equippedItemId(player, slot)
	if equipped ~= nil then
		return equipped
	end

	local profile = ProfileService.get(player)
	local definition = Catalogs.items[fallbackItemId]
	if
		profile == nil
		or slot == ""
		or definition == nil
		or definition.category ~= "Equipment"
		or definition.equipmentSlot ~= slot
		or definition.maxStack < 1
	then
		return nil
	end

	local entry: any = profile.inventory[fallbackItemId]
	local quantity = if entry == nil then 0 else storedQuantity(entry)
	if quantity == nil then
		return nil
	end
	local changed = clearEquippedSlot(profile, slot, fallbackItemId)
	if entry == nil then
		entry = { quantity = 1 }
		profile.inventory[fallbackItemId] = entry
		changed = true
	elseif quantity < 1 then
		entry.quantity = 1
		changed = true
	end
	if entry.equipped ~= true then
		entry.equipped = true
		changed = true
	end
	if changed then
		ProfileService.markDirty(player, `inventory:ensureEquipped:{fallbackItemId}`)
	end
	return fallbackItemId
end

return InventoryService
