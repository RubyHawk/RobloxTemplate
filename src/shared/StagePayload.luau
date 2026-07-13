--!strict

local StagePayload = {}

StagePayload.CHUNK_SIZE = 180_000
StagePayload.MAX_PAYLOAD_SIZE = 50_000_000
StagePayload.FORMAT = "StagewrightChunked:v1"
StagePayload.AUTHORING_VALUE_NAME = "StagewrightPayload"
StagePayload.AUTHORING_CHUNKS_NAME = "StagewrightPayloadChunks"
StagePayload.RUNTIME_VALUE_NAME = "StagewrightRuntime"
StagePayload.RUNTIME_CHUNKS_NAME = "StagewrightRuntimeChunks"

export type Manifest = {
	chunkCount: number,
	length: number,
	checksum: string,
}

function StagePayload.chunkName(index: number): string
	return `Chunk_{string.format("%04d", index)}`
end

function StagePayload.chunksName(valueName: string): string
	if valueName == StagePayload.AUTHORING_VALUE_NAME then
		return StagePayload.AUTHORING_CHUNKS_NAME
	end
	if valueName == StagePayload.RUNTIME_VALUE_NAME then
		return StagePayload.RUNTIME_CHUNKS_NAME
	end
	return `{valueName}Chunks`
end

local function expectedChunkCount(length: number): number
	return math.max(1, math.ceil(length / StagePayload.CHUNK_SIZE))
end

function StagePayload.split(encoded: string): { string }
	local chunks: { string } = {}
	local offset = 1
	while offset <= #encoded do
		table.insert(chunks, string.sub(encoded, offset, offset + StagePayload.CHUNK_SIZE - 1))
		offset += StagePayload.CHUNK_SIZE
	end
	if #chunks == 0 then
		table.insert(chunks, "")
	end
	return chunks
end

function StagePayload.manifest(checksum: string, chunkCount: number, length: number): string
	assert(chunkCount > 0 and chunkCount % 1 == 0, "chunk count must be a positive integer")
	assert(
		length >= 0 and length % 1 == 0 and length <= StagePayload.MAX_PAYLOAD_SIZE,
		"payload length is invalid"
	)
	assert(chunkCount == expectedChunkCount(length), "chunk count does not match payload length")
	assert(string.match(checksum, "^[%w%-]+$") ~= nil, "payload checksum has invalid characters")
	return `{StagePayload.FORMAT}:{chunkCount}:{length}:{checksum}`
end

function StagePayload.parseManifest(value: string): Manifest?
	local chunkCountText, lengthText, checksum =
		string.match(value, "^StagewrightChunked:v1:(%d+):(%d+):([%w%-]+)$")
	if chunkCountText == nil or lengthText == nil or checksum == nil then
		return nil
	end
	local chunkCount = tonumber(chunkCountText)
	local length = tonumber(lengthText)
	if
		chunkCount == nil
		or chunkCount < 1
		or length == nil
		or length < 0
		or length > StagePayload.MAX_PAYLOAD_SIZE
		or chunkCount ~= expectedChunkCount(length)
	then
		return nil
	end
	return {
		chunkCount = chunkCount,
		length = length,
		checksum = checksum,
	}
end

function StagePayload.join(
	chunks: { string },
	expectedCount: number,
	expectedLength: number
): (string?, string?)
	if expectedCount < 1 or expectedCount % 1 ~= 0 then
		return nil, "Chunk count is invalid"
	end
	if expectedLength < 0 or expectedLength % 1 ~= 0 then
		return nil, "Payload length is invalid"
	end
	if
		expectedLength > StagePayload.MAX_PAYLOAD_SIZE
		or expectedCount ~= expectedChunkCount(expectedLength)
	then
		return nil, "Chunk count does not match payload length"
	end
	local ordered: { string } = {}
	for index = 1, expectedCount do
		local chunk = chunks[index]
		if type(chunk) ~= "string" then
			return nil, `Payload chunk {index} is missing`
		end
		if index < expectedCount and #chunk ~= StagePayload.CHUNK_SIZE then
			return nil, `Payload chunk {index} has an invalid length`
		end
		table.insert(ordered, chunk)
	end
	local encoded = table.concat(ordered)
	if #encoded ~= expectedLength then
		return nil, `Payload length mismatch: expected {expectedLength}, got {#encoded}`
	end
	return encoded, nil
end

return table.freeze(StagePayload)
