--!strict

local StagePlatformLayout = {}

export type Vec3 = { x: number, y: number, z: number }

function StagePlatformLayout.slotOffset(firstOffset: Vec3, slot: number, slotCount: number): (Vec3, number)
	assert(slotCount >= 1, "slot count must be positive")
	assert(slot >= 1 and slot <= slotCount, "slot is outside the platform layout")
	local yaw = ((slot - 1) * math.pi * 2) / slotCount
	local cosine = math.cos(yaw)
	local sine = math.sin(yaw)
	return {
		x = cosine * firstOffset.x + sine * firstOffset.z,
		y = firstOffset.y,
		z = -sine * firstOffset.x + cosine * firstOffset.z,
	},
		yaw
end

return table.freeze(StagePlatformLayout)
