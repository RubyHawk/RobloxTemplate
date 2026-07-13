--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local inputPath = process.args[1]
assert(
	inputPath ~= nil and fs.isFile(inputPath),
	"Usage: lune run scripts/inspect-stagewright-source.luau <model.rbxm>"
)

local roots = roblox.deserializeModel(fs.readFile(inputPath))

local function vector(value: Vector3): string
	return string.format("(%.3f, %.3f, %.3f)", value.X, value.Y, value.Z)
end

local function frame(value: CFrame): string
	local x, y, z = value:ToOrientation()
	return string.format(
		"pos=%s rot=(%.2f, %.2f, %.2f deg)",
		vector(value.Position),
		math.deg(x),
		math.deg(y),
		math.deg(z)
	)
end

local interestingTokens = {
	"island",
	"platform",
	"socket",
	"origin",
	"anchor",
	"center",
	"circle",
	"spawn",
	"map",
	"base",
	"plot",
	"slot",
}

local function isInteresting(name: string): boolean
	local lowerName = string.lower(name)
	for _, token in interestingTokens do
		if string.find(lowerName, token, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function printTree(instance: Instance, depth: number)
	if depth > 5 then
		return
	end
	local children = instance:GetChildren()
	local suffix = ""
	if instance:IsA("Model") then
		local success, pivot = pcall(function()
			return instance.WorldPivot
		end)
		if success then
			suffix = ` · {frame(pivot)}`
		end
	elseif instance:IsA("BasePart") then
		suffix = ` · {frame(instance.CFrame)} size={vector(instance.Size)}`
	elseif
		instance:IsA("IntValue")
		or instance:IsA("NumberValue")
		or instance:IsA("StringValue")
		or instance:IsA("BoolValue")
	then
		if instance:IsA("StringValue") and #instance.Value > 80 then
			suffix = ` · value-length={#instance.Value}`
		else
			suffix = ` · value={tostring(instance.Value)}`
		end
	end
	print(`{string.rep("  ", depth)}{instance.Name} [{instance.ClassName}]{suffix} · children={#children}`)
	for _, child in children do
		if
			depth < 2
			or child:IsA("Model")
			or child:IsA("Folder")
			or child:IsA("ValueBase")
			or isInteresting(child.Name)
		then
			printTree(child, depth + 1)
		end
	end
end

for _, root in roots do
	printTree(root, 0)
end

print("\nInteresting world parts/models:")
for _, root in roots do
	local instances = { root }
	for _, descendant in root:GetDescendants() do
		table.insert(instances, descendant)
	end
	for _, instance in instances do
		if isInteresting(instance.Name) then
			if instance:IsA("BasePart") then
				print(
					`{instance:GetFullName()} [{instance.ClassName}] {frame(instance.CFrame)} size={vector(
						instance.Size
					)}`
				)
			elseif instance:IsA("Model") then
				local success, pivot = pcall(function()
					return instance.WorldPivot
				end)
				if success then
					print(`{instance:GetFullName()} [Model] {frame(pivot)}`)
				end
			end
		end
	end
end

print("\nAuthored route controls:")
for _, root in roots do
	for _, descendant in root:GetDescendants() do
		if descendant.Name == "PathPoints" then
			local controls: { BasePart } = {}
			for _, child in descendant:GetChildren() do
				if child:IsA("BasePart") then
					table.insert(controls, child)
				end
			end
			table.sort(controls, function(left, right)
				return left.Name < right.Name
			end)
			local platform = descendant.Parent
			local base = if platform ~= nil then platform:FindFirstChild("PlatformBase") else nil
			local origin = if platform ~= nil then platform:FindFirstChild("PlatformOrigin") else nil
			for _, control in controls do
				local controlPosition = control.CFrame.Position
				local baseLocal = if base ~= nil and base:IsA("BasePart")
					then base.CFrame:PointToObjectSpace(controlPosition)
					else controlPosition
				local originLocal = if origin ~= nil and origin:IsA("BasePart")
					then origin.CFrame:PointToObjectSpace(controlPosition)
					else controlPosition
				print(
					`{control.Name}: world={vector(controlPosition)} base-local={vector(baseLocal)} origin-local={vector(
						originLocal
					)}`
				)
			end
		end
	end
end

print("\nLegacy cell summary:")
for _, root in roots do
	for _, descendant in root:GetDescendants() do
		if descendant.Name == "CellMap" then
			local rows: { StringValue } = {}
			for _, child in descendant:GetChildren() do
				if child:IsA("StringValue") then
					table.insert(rows, child)
				end
			end
			table.sort(rows, function(left, right)
				return left.Name < right.Name
			end)
			local counts: { [string]: number } = {}
			for rowIndex, row in rows do
				for column = 1, #row.Value do
					local code = string.sub(row.Value, column, column)
					counts[code] = (counts[code] or 0) + 1
					if code == "P" or code == "G" or code == "A" then
						print(`{code}: column={column} row={rowIndex}`)
					end
				end
			end
			for code, count in counts do
				print(`code {code}: {count}`)
			end
		end
	end
end
