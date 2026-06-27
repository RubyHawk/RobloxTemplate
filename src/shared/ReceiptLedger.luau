--!strict

local ReceiptLedger = {}

function ReceiptLedger.key(purchaseId: string): string
	return `receipt:{purchaseId}`
end

function ReceiptLedger.claim(redemptions: { [string]: boolean }, purchaseId: string): boolean
	local receiptKey = ReceiptLedger.key(purchaseId)
	if redemptions[receiptKey] then
		return false
	end
	redemptions[receiptKey] = true
	return true
end

return ReceiptLedger
