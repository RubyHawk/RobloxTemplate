--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProjectStorage = require(script.Parent.Persistence.ProjectStorage)
local ProjectStore = require(script.Parent.ProjectStore)
local StagePlaytestArtifact = require(script.Parent.Shared.StagePlaytestArtifact)
local StageSchema = require(script.Parent.Shared.StageSchema)

local PlaytestPreparation = {}

export type Status = "Blocked" | "Validate" | "Ready"

function PlaytestPreparation.prepare(
	selectedStageId: string,
	selectedStageName: string
): (boolean, string, Status)
	if not ProjectStore.isWritable() then
		return false, "", "Blocked"
	end
	ProjectStore.save()
	local result = ProjectStore.export()
	if result.bundle == nil then
		return false, "Playtest preparation blocked by validation errors.", "Validate"
	end
	local template = ReplicatedStorage:FindFirstChild("Template")
	if template == nil or not template:IsA("Folder") then
		return false, "Connect the RNG Defender Rojo project before preparing a playtest.", "Ready"
	end
	local root = template:FindFirstChild(StagePlaytestArtifact.ROOT_NAME)
	if root ~= nil and not root:IsA("Folder") then
		return false, "StagewrightPlaytestRuntime must be a Folder.", "Ready"
	end
	if root == nil then
		root = Instance.new("Folder")
		root.Name = StagePlaytestArtifact.ROOT_NAME
		root.Parent = template
	end

	local runtime = StageSchema.encodeCanonical(result.bundle)
	local runtimeChecksum = result.bundle.checksum
	local transportChecksum = StageSchema.checksum(result.bundle)
	root:SetAttribute(StagePlaytestArtifact.FORMAT_ATTRIBUTE, nil)
	local success, problem = pcall(function()
		ProjectStorage.writePayload(
			root :: Folder,
			StagePlaytestArtifact.VALUE_NAME,
			runtime,
			transportChecksum
		)
	end)
	if not success then
		return false, `Playtest preparation failed: {tostring(problem)}`, "Ready"
	end
	local verifiedRuntime, readError =
		ProjectStorage.readPayload(root :: Folder, StagePlaytestArtifact.VALUE_NAME)
	if verifiedRuntime ~= runtime then
		return false, `Playtest verification failed: {readError or "runtime payload mismatch"}`, "Ready"
	end

	local sourceChecksum = ProjectStore.workingChecksum()
	root:SetAttribute(StagePlaytestArtifact.SOURCE_CHECKSUM_ATTRIBUTE, sourceChecksum)
	root:SetAttribute(StagePlaytestArtifact.RUNTIME_CHECKSUM_ATTRIBUTE, runtimeChecksum)
	root:SetAttribute(StagePlaytestArtifact.SELECTED_STAGE_ATTRIBUTE, selectedStageId)
	root:SetAttribute(StagePlaytestArtifact.FORMAT_ATTRIBUTE, StagePlaytestArtifact.FORMAT)
	return true, `Playtest prepared for {selectedStageName}; press Play - {sourceChecksum}`, "Ready"
end

return table.freeze(PlaytestPreparation)
