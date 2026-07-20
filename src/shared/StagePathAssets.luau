--!strict

export type RgbTriplet = { number }

export type PathAsset = {
	id: string,
	label: string,
	rgb: RgbTriplet,
	materialName: string,
}

local function rgb(red: number, green: number, blue: number): RgbTriplet
	return table.freeze({ red, green, blue })
end

local ASSETS: { PathAsset } = table.freeze({
	table.freeze({
		id = "gravel",
		label = "Gravel",
		rgb = rgb(166, 132, 90),
		materialName = "Pebble",
	}),
	table.freeze({
		id = "dirt",
		label = "Dirt",
		rgb = rgb(126, 83, 48),
		materialName = "Ground",
	}),
	table.freeze({
		id = "stone",
		label = "Stone",
		rgb = rgb(122, 127, 134),
		materialName = "Cobblestone",
	}),
})

local assetsById: { [string]: PathAsset } = {}
for _, asset in ASSETS do
	assetsById[asset.id] = asset
end

local StagePathAssets = {
	DEFAULT_ASSET_ID = "gravel",
	-- Legacy authoring metadata remains stable, but Stagewright is currently a
	-- deterministic 2D route-plane editor. No fake terrain/fixed-height selector
	-- is exposed until a persisted height provider exists.
	DEFAULT_SURFACE_MODE = "FollowTerrain",
	ASSETS = ASSETS,
}

function StagePathAssets.find(assetId: any): PathAsset?
	return if type(assetId) == "string" then assetsById[assetId] else nil
end

function StagePathAssets.isValid(assetId: any): boolean
	return StagePathAssets.find(assetId) ~= nil
end

function StagePathAssets.resolve(assetId: any): PathAsset
	local asset = StagePathAssets.find(assetId) or StagePathAssets.find(StagePathAssets.DEFAULT_ASSET_ID)
	return assert(asset, "Stagewright path asset catalog must include its default asset")
end

function StagePathAssets.forEdge(edge: any): (PathAsset, string)
	local metadata = if type(edge) == "table" and type(edge.metadata) == "table" then edge.metadata else nil
	local requestedId = if metadata ~= nil and type(metadata.pathAssetId) == "string"
		then metadata.pathAssetId
		else StagePathAssets.DEFAULT_ASSET_ID
	return StagePathAssets.resolve(requestedId), requestedId
end

function StagePathAssets.label(assetId: any): string
	local asset = StagePathAssets.find(assetId)
	if asset ~= nil then
		return asset.label
	end
	local defaultLabel = StagePathAssets.resolve(StagePathAssets.DEFAULT_ASSET_ID).label
	-- Preserve custom IDs in saved data while making the visual fallback explicit.
	return if type(assetId) == "string" and assetId ~= ""
		then `{assetId} (missing; using {defaultLabel})`
		else defaultLabel
end

function StagePathAssets.next(assetId: any): string
	for index, asset in ASSETS do
		if asset.id == assetId then
			return ASSETS[(index % #ASSETS) + 1].id
		end
	end
	return StagePathAssets.DEFAULT_ASSET_ID
end

return table.freeze(StagePathAssets)
