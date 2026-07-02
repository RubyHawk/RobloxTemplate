--!strict

local MarketplaceService = game:GetService("MarketplaceService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Config = require(Shared.TemplateConfig)
local ReceiptLedger = require(Shared.ReceiptLedger)
local DataStoreRuntime = require(script.Parent.Parent.Util.DataStoreRuntime)
local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)

local StoreService = {}

local function amountForProduct(productId: number): number?
	if productId == Config.products.coinPackSmall.id and productId > 0 then
		return Config.products.coinPackSmall.coins
	elseif productId == Config.products.coinPackLarge.id and productId > 0 then
		return Config.products.coinPackLarge.coins
	end
	return nil
end

function StoreService.refreshEntitlements(player: Player)
	local profile = ProfileService.get(player)
	if profile == nil then
		return
	end
	if Config.economy.extendedOfflineGamePassId <= 0 then
		profile.entitlements.extendedOffline = false
		return
	end
	local success, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(
			player.UserId,
			Config.economy.extendedOfflineGamePassId
		)
	end)
	if success then
		profile.entitlements.extendedOffline = owns
		ProfileService.markDirty(player, "entitlement:offline")
	else
		DataStoreRuntime.failure("Entitlements", `check pass for user {player.UserId}`, owns)
	end
end

function StoreService.initialize()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = game:GetService("Players"):GetPlayerByUserId(receiptInfo.PlayerId)
		if player == nil then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local profile = ProfileService.get(player)
		local amount = amountForProduct(receiptInfo.ProductId)
		if profile == nil or amount == nil then
			if amount == nil then
				warn(`[Template Store] No grant is configured for product {receiptInfo.ProductId}.`)
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local receiptKey = ReceiptLedger.key(receiptInfo.PurchaseId)
		if ReceiptLedger.claim(profile.redemptions, receiptInfo.PurchaseId) then
			EconomyService.awardRaw(player, amount, `product:{receiptInfo.ProductId}`)
			ProfileService.markDirty(player, receiptKey)
		end
		if not ProfileService.save(player) then
			DataStoreRuntime.failure(
				"Receipts",
				`persist purchase {receiptInfo.PurchaseId}`,
				"the player profile save did not complete"
			)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if purchased and gamePassId == Config.economy.extendedOfflineGamePassId then
			StoreService.refreshEntitlements(player)
		end
	end)
end

return StoreService
