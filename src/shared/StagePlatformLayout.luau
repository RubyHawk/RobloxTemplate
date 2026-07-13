--!strict

local StagePlatformLayout = {}

export type Vec3 = { x: number, y: number, z: number }

function StagePlatformLayout.alignDirectionYaw(firstOffset: Vec3, localCenterDirection: Vec3): number
	local offsetMagnitude = math.sqrt(firstOffset.x * firstOffset.x + firstOffset.z * firstOffset.z)
	local directionMagnitude = math.sqrt(
		localCenterDirection.x * localCenterDirection.x + localCenterDirection.z * localCenterDirection.z
	)
	assert(offsetMagnitude > 1e-6, "first platform offset must have a horizontal direction")
	assert(directionMagnitude > 1e-6, "local center direction must have a horizontal direction")
	local worldCenterAngle = math.atan2(-firstOffset.x, -firstOffset.z)
	local localDirectionAngle = math.atan2(localCenterDirection.x, localCenterDirection.z)
	local yaw = worldCenterAngle - localDirectionAngle
	return math.atan2(math.sin(yaw), math.cos(yaw))
end

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
