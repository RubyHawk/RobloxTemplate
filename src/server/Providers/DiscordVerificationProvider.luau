--!strict

local Provider = {}

function Provider.verify(_player: Player): { status: string, value: boolean?, reason: string? }
	return {
		status = "disabled",
		value = false,
		reason = "Discord verification requires the future one-time-code backend",
	}
end

return Provider
