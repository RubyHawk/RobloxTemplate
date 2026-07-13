--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local StageExport = require("../src/shared/StageExport")
local StageLegacy = require("../src/shared/StageLegacy")
local StagePayload = require("../src/shared/StagePayload")
local StageSchema = require("../src/shared/StageSchema")

local inputPath = process.args[1] or "stage-data/stagewright-project.json"
local checkOnly = process.args[2] == "--check"
local projectPath = "stage-data/stagewright-project.json"
local generatedPath = "src/shared/StageCatalog.generated.luau"

local function readPayload(payload: StringValue): string
	local manifest = StagePayload.parseManifest(payload.Value)
	if manifest == nil then
		return payload.Value
	end
	local parent = payload.Parent
	assert(parent ~= nil, "Chunked Stagewright payload has no parent")
	local folder = parent:FindFirstChild(StagePayload.chunksName(payload.Name))
	assert(folder ~= nil and folder:IsA("Folder"), "Chunked Stagewright payload folder is missing")
	local chunks: { string } = {}
	for index = 1, manifest.chunkCount do
		local child = folder:FindFirstChild(StagePayload.chunkName(index))
		assert(child ~= nil and child:IsA("StringValue"), `Stagewright payload chunk {index} is missing`)
		chunks[index] = child.Value
	end
	local encoded, message = StagePayload.join(chunks, manifest.chunkCount, manifest.length)
	assert(encoded ~= nil, message)
	local decoded = serde.decode("json", encoded)
	assert(
		StageSchema.checksum(decoded) == manifest.checksum,
		"Stagewright payload checksum does not match its chunk manifest"
	)
	return encoded
end

local function payloadFromRoots(roots: { Instance }): string?
	for _, root in roots do
		if root.Name == StagePayload.AUTHORING_VALUE_NAME and root:IsA("StringValue") then
			return readPayload(root)
		end
		for _, descendant in root:GetDescendants() do
			if descendant.Name == StagePayload.AUTHORING_VALUE_NAME and descendant:IsA("StringValue") then
				return readPayload(descendant)
			end
		end
	end
	return nil
end

local function findGamePlatform(roots: { Instance }): Instance?
	for _, root in roots do
		if root.Name == "GamePlatform" then
			return root
		end
		local platform = root:FindFirstChild("GamePlatform", true)
		if platform ~= nil then
			return platform
		end
	end
	return nil
end

local function intValue(parent: Instance, name: string, fallback: number): number
	local value = parent:FindFirstChild(name)
	return if value ~= nil and value:IsA("IntValue") and value.Value > 0 then value.Value else fallback
end

local function rounded(value: number): number
	local result = math.round(value * 1_000_000) / 1_000_000
	return if math.abs(result) < 0.0000005 then 0 else result
end

local function legacyProject(roots: { Instance }): (any, { string })
	local platform = findGamePlatform(roots)
	assert(platform ~= nil, "RBXM has neither StagewrightPayload nor a legacy GamePlatform")
	local columns = intValue(platform, "Columns", 32)
	local rowCount = intValue(platform, "Rows", 27)
	local cellSize = intValue(platform, "CellSize", 4)
	local rows: { string } = {}
	local cellMap = platform:FindFirstChild("CellMap")
	for row = 1, rowCount do
		local rowNode = if cellMap ~= nil
			then cellMap:FindFirstChild(`Row_{string.format("%02d", row)}`)
			else nil
		rows[row] = if rowNode ~= nil and rowNode:IsA("StringValue") then rowNode.Value else ""
	end

	local origin = platform:FindFirstChild("PlatformOrigin")
	local base = platform:FindFirstChild("PlatformBase")
	local coordinateFrame = if origin ~= nil and origin:IsA("BasePart")
		then origin.CFrame
		elseif base ~= nil and base:IsA("BasePart") then base.CFrame
		else nil
	assert(coordinateFrame ~= nil, "Legacy GamePlatform has no PlatformOrigin or PlatformBase")
	local controls: { BasePart } = {}
	local pathPoints = platform:FindFirstChild("PathPoints")
	if pathPoints ~= nil then
		for _, child in pathPoints:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(controls, child)
			end
		end
	end
	table.sort(controls, function(left, right)
		return left.Name < right.Name
	end)
	local controlPositions: { StageLegacy.Vec3 } = {}
	for _, control in controls do
		local position = coordinateFrame:PointToObjectSpace(control.CFrame.Position)
		table.insert(controlPositions, {
			x = rounded(position.X),
			y = rounded(position.Y),
			z = rounded(position.Z),
		})
	end

	return StageLegacy.project({
		columns = columns,
		rows = rowCount,
		cellSize = cellSize,
		rowValues = rows,
		controlPositions = controlPositions,
		stageId = "stage_default",
		graphId = "graph_main",
		stageName = "First Island Stage",
		blankFallback = false,
	})
end

local project: any
local importNotices: { string } = {}
if string.match(string.lower(inputPath), "%.rbxmx?$") then
	local roots = roblox.deserializeModel(fs.readFile(inputPath))
	local payload = payloadFromRoots(roots)
	if payload ~= nil then
		project = StageSchema.migrateProject(serde.decode("json", payload))
	else
		project, importNotices = legacyProject(roots)
	end
else
	project = StageSchema.migrateProject(serde.decode("json", fs.readFile(inputPath)))
end
for _, notice in importNotices do
	print(`[Legacy] {notice}`)
end
-- Normalize Lua table/number representations before baking so direct legacy
-- imports and later JSON parity checks produce the same runtime checksum.
project = StageSchema.migrateProject(serde.decode("json", StageSchema.encodeCanonical(project)))
local result = StageExport.bake(project)
for _, issue in result.issues do
	print(string.format("[%s] %s: %s", issue.severity, issue.code, issue.message))
end
assert(result.bundle ~= nil, "Stagewright export validation failed")

local canonicalProject = StageSchema.encodeCanonical(project)
local canonicalRuntime = StageSchema.encodeCanonical(result.bundle)
local generated = table.concat({
	"--!strict",
	"-- Generated by scripts/stagewright-import.luau. Do not edit by hand.",
	`-- Stagewright checksum: {result.bundle.checksum}`,
	'local HttpService = game:GetService("HttpService")',
	"local catalog = HttpService:JSONDecode([====[",
	canonicalRuntime,
	"]====])",
	"return table.freeze(catalog)",
	"",
}, "\n")

local function verify(path: string, expected: string)
	assert(fs.isFile(path), `Missing generated file {path}`)
	assert(fs.readFile(path) == expected, `Stagewright artifact drift: regenerate {path}`)
end

if checkOnly then
	verify(projectPath, canonicalProject .. "\n")
	verify(generatedPath, generated)
	print(`Stagewright parity verified: {result.bundle.checksum}`)
else
	fs.writeFile(projectPath, canonicalProject .. "\n")
	fs.writeFile(generatedPath, generated)
	print(`Imported {#result.bundle.stageOrder} stage(s): {result.bundle.checksum}`)
end
