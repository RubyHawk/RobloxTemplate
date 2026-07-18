--!strict

local ServerStorage = game:GetService("ServerStorage")

local ProjectLoadPolicy = require(script.Parent.ProjectLoadPolicy)
local StagePayload = require(script.Parent.Parent.Shared.StagePayload)

local ProjectStorage = {}

local PROJECT_NAME = "StagewrightProject"
local PAYLOAD_NAME = "Payload"
local observerConnections: { RBXScriptConnection } = {}

local function childrenNamed(parent: Instance, name: string): { Instance }
	local result: { Instance } = {}
	for _, child in parent:GetChildren() do
		if child.Name == name then
			table.insert(result, child)
		end
	end
	return result
end

local function missingSnapshot(): ProjectLoadPolicy.PayloadSnapshot
	return {
		containerState = "Missing",
		containerClassName = nil,
		valueState = "Missing",
		valueClassName = nil,
		value = nil,
		chunksState = "Missing",
		chunksClassName = nil,
		chunks = {},
		chunkCountAttribute = nil,
		payloadLengthAttribute = nil,
		payloadChecksumAttribute = nil,
		workingChecksumAttribute = nil,
		schemaVersionAttribute = nil,
	}
end

local function snapshotForParent(
	parent: Instance,
	valueName: string,
	workingChecksumAttribute: any?,
	schemaVersionAttribute: any?
): ProjectLoadPolicy.PayloadSnapshot
	local valueMatches = childrenNamed(parent, valueName)
	local value = valueMatches[1]
	local chunksName = StagePayload.chunksName(valueName)
	local chunksMatches = childrenNamed(parent, chunksName)
	local chunksFolder = chunksMatches[1]
	local chunks: { ProjectLoadPolicy.ChunkSnapshot } = {}
	if chunksFolder ~= nil and chunksFolder:IsA("Folder") then
		for _, child in chunksFolder:GetChildren() do
			table.insert(chunks, {
				name = child.Name,
				className = child.ClassName,
				value = if child:IsA("StringValue") then child.Value else nil,
			})
		end
	end
	return {
		containerState = "Present",
		containerClassName = parent.ClassName,
		valueState = if #valueMatches == 0
			then "Missing"
			elseif #valueMatches == 1 and value ~= nil and value:IsA("StringValue") then "Present"
			else "Invalid",
		valueClassName = if #valueMatches > 1
			then "Multiple"
			elseif value ~= nil then value.ClassName
			else nil,
		value = if #valueMatches == 1 and value ~= nil and value:IsA("StringValue") then value.Value else nil,
		chunksState = if #chunksMatches == 0
			then "Missing"
			elseif #chunksMatches == 1 and chunksFolder ~= nil and chunksFolder:IsA("Folder") then "Present"
			else "Invalid",
		chunksClassName = if #chunksMatches > 1
			then "Multiple"
			elseif chunksFolder ~= nil then chunksFolder.ClassName
			else nil,
		chunks = chunks,
		chunkCountAttribute = if chunksFolder ~= nil then chunksFolder:GetAttribute("ChunkCount") else nil,
		payloadLengthAttribute = if chunksFolder ~= nil
			then chunksFolder:GetAttribute("PayloadLength")
			else nil,
		payloadChecksumAttribute = if chunksFolder ~= nil
			then chunksFolder:GetAttribute("PayloadChecksum")
			else nil,
		workingChecksumAttribute = workingChecksumAttribute,
		schemaVersionAttribute = schemaVersionAttribute,
	}
end

function ProjectStorage.projectSnapshot(): ProjectLoadPolicy.PayloadSnapshot
	local folderMatches = childrenNamed(ServerStorage, PROJECT_NAME)
	local folder = folderMatches[1]
	if #folderMatches == 0 then
		return missingSnapshot()
	end
	if #folderMatches ~= 1 or folder == nil or not folder:IsA("Folder") then
		local snapshot = missingSnapshot()
		snapshot.containerState = "Invalid"
		snapshot.containerClassName = if #folderMatches > 1
			then "Multiple"
			elseif folder ~= nil then folder.ClassName
			else nil
		return snapshot
	end
	return snapshotForParent(
		folder,
		PAYLOAD_NAME,
		folder:GetAttribute("WorkingChecksum"),
		folder:GetAttribute("SchemaVersion")
	)
end

local function takeUniqueChild(parent: Instance, name: string, className: string): Instance?
	local matches = childrenNamed(parent, name)
	local candidate = matches[1]
	if #matches == 1 and candidate ~= nil and candidate.ClassName == className then
		return candidate
	end
	for _, match in matches do
		match:Destroy()
	end
	return nil
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = takeUniqueChild(parent, name, "Folder")
	if existing ~= nil then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureStringValue(parent: Instance, name: string): StringValue
	local existing = takeUniqueChild(parent, name, "StringValue")
	if existing ~= nil then
		return existing :: StringValue
	end
	local value = Instance.new("StringValue")
	value.Name = name
	value.Parent = parent
	return value
end

local function ensureProjectRoot(): Folder
	return ensureFolder(ServerStorage, PROJECT_NAME)
end

function ProjectStorage.writePayload(
	parent: Instance,
	valueName: string,
	encoded: string,
	checksum: string
): StringValue
	local chunkCount = math.max(1, math.ceil(#encoded / StagePayload.CHUNK_SIZE))
	local manifest = StagePayload.manifest(checksum, chunkCount, #encoded)
	local chunks = StagePayload.split(encoded)
	local value = ensureStringValue(parent, valueName)
	local chunksName = StagePayload.chunksName(valueName)
	if #encoded <= StagePayload.CHUNK_SIZE then
		value.Value = encoded
		for _, existingChunks in childrenNamed(parent, chunksName) do
			existingChunks:Destroy()
		end
		return value
	end

	local chunksFolder = ensureFolder(parent, chunksName)
	for index, chunk in chunks do
		local chunkName = StagePayload.chunkName(index)
		local child = ensureStringValue(chunksFolder, chunkName)
		child.Value = chunk
	end
	for _, child in chunksFolder:GetChildren() do
		local indexText = string.match(child.Name, "^Chunk_(%d+)$")
		local index = if indexText ~= nil then tonumber(indexText) else nil
		if index == nil or index < 1 or index > #chunks or not child:IsA("StringValue") then
			child:Destroy()
		end
	end
	chunksFolder:SetAttribute("ChunkCount", #chunks)
	chunksFolder:SetAttribute("PayloadLength", #encoded)
	chunksFolder:SetAttribute("PayloadChecksum", checksum)
	value.Value = manifest
	return value
end

function ProjectStorage.readPayload(parent: Instance, valueName: string): (string?, string?, string?)
	local snapshot = snapshotForParent(parent, valueName, parent:GetAttribute("WorkingChecksum"), nil)
	-- Embedded authoring/runtime payloads may live in a Model. The policy's
	-- container class check applies to the ServerStorage project root only.
	snapshot.containerClassName = "Folder"
	local payload = ProjectLoadPolicy.readPayload(snapshot)
	if payload.kind == "Encoded" then
		return payload.encoded, nil, payload.expectedChecksum
	end
	return nil, payload.message, nil
end

function ProjectStorage.writeProject(encoded: string, checksum: string, schemaVersion: number)
	local folder = ensureProjectRoot()
	ProjectStorage.writePayload(folder, PAYLOAD_NAME, encoded, checksum)
	folder:SetAttribute("SchemaVersion", schemaVersion)
	folder:SetAttribute("WorkingChecksum", checksum)
end

function ProjectStorage.disconnectRelevantConnections()
	for _, connection in observerConnections do
		connection:Disconnect()
	end
	table.clear(observerConnections)
end

function ProjectStorage.refreshRelevantConnections(onRelevantChange: () -> ())
	ProjectStorage.disconnectRelevantConnections()
	local function connect(signal: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection
		local connection = signal:Connect(callback)
		table.insert(observerConnections, connection)
		return connection
	end
	local function disconnectTracked(connection: RBXScriptConnection)
		connection:Disconnect()
		local index = table.find(observerConnections, connection)
		if index ~= nil then
			table.remove(observerConnections, index)
		end
	end
	local function forgetNameWatcher(watchers: { [Instance]: RBXScriptConnection }, child: Instance)
		local connection = watchers[child]
		watchers[child] = nil
		if connection ~= nil then
			disconnectTracked(connection)
		end
	end
	local function watchRelevantName(
		parent: Instance,
		child: Instance,
		relevant: (string) -> boolean,
		watchers: { [Instance]: RBXScriptConnection }
	)
		forgetNameWatcher(watchers, child)
		local wasRelevant = relevant(child.Name)
		watchers[child] = connect(child:GetPropertyChangedSignal("Name"), function()
			if child.Parent ~= parent then
				return
			end
			local isRelevant = relevant(child.Name)
			if wasRelevant or isRelevant then
				onRelevantChange()
			end
			wasRelevant = isRelevant
		end)
	end
	local function isProjectName(name: string): boolean
		return name == PROJECT_NAME
	end
	local projectNameWatchers: { [Instance]: RBXScriptConnection } = {}
	connect(ServerStorage.ChildAdded, function(child)
		watchRelevantName(ServerStorage, child, isProjectName, projectNameWatchers)
		if isProjectName(child.Name) then
			onRelevantChange()
		end
	end)
	connect(ServerStorage.ChildRemoved, function(child)
		forgetNameWatcher(projectNameWatchers, child)
		if isProjectName(child.Name) then
			onRelevantChange()
		end
	end)
	for _, child in ServerStorage:GetChildren() do
		watchRelevantName(ServerStorage, child, isProjectName, projectNameWatchers)
	end
	local folderMatches = childrenNamed(ServerStorage, PROJECT_NAME)
	local folder = folderMatches[1]
	if #folderMatches ~= 1 or folder == nil then
		return
	end
	if not folder:IsA("Folder") then
		return
	end
	connect(folder:GetAttributeChangedSignal("WorkingChecksum"), onRelevantChange)
	connect(folder:GetAttributeChangedSignal("SchemaVersion"), onRelevantChange)
	local chunksName = StagePayload.chunksName(PAYLOAD_NAME)
	local function isPayloadStorageName(name: string): boolean
		return name == PAYLOAD_NAME or name == chunksName
	end
	local payloadNameWatchers: { [Instance]: RBXScriptConnection } = {}
	connect(folder.ChildAdded, function(child)
		watchRelevantName(folder, child, isPayloadStorageName, payloadNameWatchers)
		if isPayloadStorageName(child.Name) then
			onRelevantChange()
		end
	end)
	connect(folder.ChildRemoved, function(child)
		forgetNameWatcher(payloadNameWatchers, child)
		if isPayloadStorageName(child.Name) then
			onRelevantChange()
		end
	end)
	for _, child in folder:GetChildren() do
		watchRelevantName(folder, child, isPayloadStorageName, payloadNameWatchers)
	end
	local payloadMatches = childrenNamed(folder, PAYLOAD_NAME)
	local payload = payloadMatches[1]
	if #payloadMatches == 1 and payload ~= nil then
		if payload:IsA("StringValue") then
			connect(payload:GetPropertyChangedSignal("Value"), onRelevantChange)
		end
	end
	local chunksMatches = childrenNamed(folder, chunksName)
	local chunksFolder = chunksMatches[1]
	if #chunksMatches ~= 1 or chunksFolder == nil then
		return
	end
	if not chunksFolder:IsA("Folder") then
		return
	end
	connect(chunksFolder:GetAttributeChangedSignal("ChunkCount"), onRelevantChange)
	connect(chunksFolder:GetAttributeChangedSignal("PayloadLength"), onRelevantChange)
	connect(chunksFolder:GetAttributeChangedSignal("PayloadChecksum"), onRelevantChange)
	connect(chunksFolder.ChildAdded, onRelevantChange)
	connect(chunksFolder.ChildRemoved, onRelevantChange)
	for _, child in chunksFolder:GetChildren() do
		connect(child:GetPropertyChangedSignal("Name"), onRelevantChange)
		if child:IsA("StringValue") then
			connect(child:GetPropertyChangedSignal("Value"), onRelevantChange)
		end
	end
end

return ProjectStorage
