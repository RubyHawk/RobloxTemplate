--!strict

local Provider = {}

function Provider.getMembership(_player: Player): { status: string, value: any?, reason: string? }
	return {
		status = "disabled",
		value = nil,
		reason = "Guilds are reserved but disabled",
	}
end

return Provider
