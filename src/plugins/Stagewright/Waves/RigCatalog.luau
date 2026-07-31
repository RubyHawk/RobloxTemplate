--!strict

-- Studio-side discovery of the enemy rigs a designer has authored. Whatever
-- Models sit under `ReplicatedStorage.Template.EnemyRigs` are the mobs that can
-- be selected, so adding a character asset to that folder is the whole workflow.
--
-- This module reads the live Studio tree, which is why it is deliberately
-- separate from `Waves/Model.luau`: authored project data stores only the rig's
-- name, and the pure model stays testable with no Roblox service dependency.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RigCatalog = {}

RigCatalog.FOLDER_NAME = "EnemyRigs"
RigCatalog.FALLBACK_RIG_NAME = "Fallback"
RigCatalog.ANIMATION_FOLDER_NAME = "Animations"

export type Rig = {
	name: string,
	hasAnimator: boolean,
	declaredWalkId: string,
	declaredDeathId: string,
	partCount: number,
}

local function rigsFolder(): Folder?
	local template = ReplicatedStorage:FindFirstChild("Template")
	local folder = if template ~= nil then template:FindFirstChild(RigCatalog.FOLDER_NAME) else nil
	return if folder ~= nil and folder:IsA("Folder") then folder else nil
end

local function declaredAnimationId(model: Model, childName: string): string
	local folder = model:FindFirstChild(RigCatalog.ANIMATION_FOLDER_NAME)
	local animation = if folder ~= nil then folder:FindFirstChild(childName) else nil
	if animation ~= nil and animation:IsA("Animation") then
		return animation.AnimationId
	end
	return ""
end

-- A character asset animates through a Humanoid or an AnimationController. The
-- renderer can add a controller when animations exist without one, so this is
-- reported to the designer rather than treated as an error.
local function hasAnimator(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		return true
	end
	return model:FindFirstChildOfClass("AnimationController") ~= nil
end

function RigCatalog.isAvailable(): boolean
	return rigsFolder() ~= nil
end

-- Every selectable rig, ordered by name so the picker cycles predictably.
function RigCatalog.rigs(): { Rig }
	local folder = rigsFolder()
	if folder == nil then
		return {}
	end
	local rigs: { Rig } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local partCount = 0
			for _, descendant in child:GetDescendants() do
				if descendant:IsA("BasePart") then
					partCount += 1
				end
			end
			table.insert(rigs, {
				name = child.Name,
				hasAnimator = hasAnimator(child),
				declaredWalkId = declaredAnimationId(child, "Walk"),
				declaredDeathId = declaredAnimationId(child, "Death"),
				partCount = partCount,
			})
		end
	end
	table.sort(rigs, function(left: Rig, right: Rig): boolean
		return left.name < right.name
	end)
	return rigs
end

function RigCatalog.names(): { string }
	local names: { string } = {}
	for _, rig in RigCatalog.rigs() do
		table.insert(names, rig.name)
	end
	return names
end

function RigCatalog.find(modelId: string): Rig?
	for _, rig in RigCatalog.rigs() do
		if rig.name == modelId then
			return rig
		end
	end
	return nil
end

-- One line describing what the runtime will actually render for this model id,
-- including the fallback case, so a typo is visible while authoring instead of
-- at playtest.
function RigCatalog.describe(modelId: string): string
	if not RigCatalog.isAvailable() then
		return "EnemyRigs folder not found - connect the Rojo project to browse rigs"
	end
	if modelId == "" then
		return `No model selected - renders the {RigCatalog.FALLBACK_RIG_NAME} rig`
	end
	local rig = RigCatalog.find(modelId)
	if rig == nil then
		return `"{modelId}" is not in EnemyRigs - renders the {RigCatalog.FALLBACK_RIG_NAME} rig`
	end
	local animationNote = if rig.declaredWalkId ~= "" or rig.declaredDeathId ~= ""
		then "rig declares its own animations"
		elseif rig.hasAnimator then "animator ready, no declared animations"
		else "no animator - set animation ids below to add one"
	return `{rig.name}: {rig.partCount} part(s), {animationNote}`
end

return table.freeze(RigCatalog)
