--!strict

local Validator = {}

export type Segment = {
	name: string,
	className: string,
	ordinal: number,
}

export type Entry = {
	path: string,
	segments: { Segment },
	className: string,
	properties: { [string]: any },
}

export type Root = {
	name: string,
	studioPath: string,
	scope: string,
	entries: { Entry },
}

export type Manifest = {
	format: string,
	workspace: { id: string, name: string },
	source: { exportedAt: string, checksum: string, fileName: string },
	modelChecksum: string,
	rootCount: number,
	entryCount: number,
	roots: { Root },
}

export type Issue = {
	kind: string,
	path: string,
	message: string,
	instance: Instance?,
}

export type Report = {
	checkedRoots: number,
	checkedInstances: number,
	issues: { Issue },
}

local EPSILON = 1e-4

local function normalizedNumber(value: number): number
	if math.abs(value) < EPSILON then
		return 0
	end
	return value
end

local function normalize(value: any): any
	local valueType = typeof(value)
	if valueType == "EnumItem" then
		return (value :: EnumItem).Name
	elseif valueType == "Color3" then
		local color = value :: Color3
		return { normalizedNumber(color.R), normalizedNumber(color.G), normalizedNumber(color.B) }
	elseif valueType == "Vector2" then
		local vector = value :: Vector2
		return { normalizedNumber(vector.X), normalizedNumber(vector.Y) }
	elseif valueType == "Vector3" then
		local vector = value :: Vector3
		return { normalizedNumber(vector.X), normalizedNumber(vector.Y), normalizedNumber(vector.Z) }
	elseif valueType == "UDim" then
		local dimension = value :: UDim
		return { UDim = { normalizedNumber(dimension.Scale), dimension.Offset } }
	elseif valueType == "UDim2" then
		local dimension = value :: UDim2
		return {
			UDim2 = {
				{ normalizedNumber(dimension.X.Scale), dimension.X.Offset },
				{ normalizedNumber(dimension.Y.Scale), dimension.Y.Offset },
			},
		}
	elseif valueType == "Rect" then
		local rectangle = value :: Rect
		return {
			Rect = {
				{ rectangle.Min.X, rectangle.Min.Y },
				{ rectangle.Max.X, rectangle.Max.Y },
			},
		}
	elseif valueType == "ColorSequence" then
		local sequence = value :: ColorSequence
		local keypoints = {}
		for _, keypoint in sequence.Keypoints do
			table.insert(keypoints, {
				time = normalizedNumber(keypoint.Time),
				color = normalize(keypoint.Value),
			})
		end
		return { ColorSequence = { keypoints = keypoints } }
	elseif valueType == "NumberSequence" then
		local sequence = value :: NumberSequence
		local keypoints = {}
		for _, keypoint in sequence.Keypoints do
			table.insert(keypoints, {
				time = normalizedNumber(keypoint.Time),
				value = normalizedNumber(keypoint.Value),
				envelope = normalizedNumber(keypoint.Envelope),
			})
		end
		return { NumberSequence = { keypoints = keypoints } }
	elseif valueType == "NumberRange" then
		local range = value :: NumberRange
		return { NumberRange = { normalizedNumber(range.Min), normalizedNumber(range.Max) } }
	elseif valueType == "Font" then
		local font = value :: Font
		return {
			family = font.Family,
			weight = font.Weight.Name,
			style = font.Style.Name,
		}
	end
	return value
end

local function valuesMatch(actual: any, expected: any): boolean
	if type(actual) == "number" and type(expected) == "number" then
		return math.abs(actual - expected) <= EPSILON
	end
	if type(actual) ~= type(expected) then
		return false
	end
	if type(expected) ~= "table" then
		return actual == expected
	end
	for key, expectedValue in expected do
		if not valuesMatch(actual[key], expectedValue) then
			return false
		end
	end
	for key in actual do
		if expected[key] == nil then
			return false
		end
	end
	return true
end

local function describe(value: any): string
	if type(value) == "table" then
		local parts = {}
		for key, child in value do
			table.insert(parts, `{tostring(key)}={describe(child)}`)
			if #parts >= 4 then
				table.insert(parts, "...")
				break
			end
		end
		return `{ { table.concat(parts, ", ") }}`
	end
	return tostring(value)
end

local function resolveStudioRoot(studioPath: string): (Instance?, string?)
	local pieces = string.split(studioPath, "/")
	local serviceName = pieces[1]
	if not serviceName or serviceName == "" then
		return nil, "studioPath has no service"
	end
	local ok, current = pcall(function()
		return game:GetService(serviceName)
	end)
	if not ok then
		return nil, `service '{serviceName}' does not exist`
	end
	for index = 2, #pieces do
		local childName = pieces[index]
		local child = (current :: Instance):FindFirstChild(childName)
		if not child then
			return nil, `missing '{table.concat(pieces, "/", 1, index)}'`
		end
		current = child
	end
	return current :: Instance, nil
end

local function resolveEntry(root: Instance, segments: { Segment }): (Instance?, Instance)
	local current = root
	for _, segment in segments do
		local ordinal = 0
		local match = nil
		for _, child in current:GetChildren() do
			if child.Name == segment.name then
				ordinal += 1
				if ordinal == segment.ordinal then
					match = child
					break
				end
			end
		end
		if not match then
			return nil, current
		end
		current = match
	end
	return current, current
end

local function addIssue(issues: { Issue }, kind: string, path: string, message: string, instance: Instance?)
	table.insert(issues, {
		kind = kind,
		path = path,
		message = message,
		instance = instance,
	})
end

function Validator.validate(manifest: Manifest): Report
	local report: Report = {
		checkedRoots = 0,
		checkedInstances = 0,
		issues = {},
	}

	for _, rootDefinition in manifest.roots do
		local root, rootError = resolveStudioRoot(rootDefinition.studioPath)
		if not root then
			addIssue(
				report.issues,
				"missing-root",
				rootDefinition.studioPath,
				rootError or "root is missing",
				nil
			)
			continue
		end
		report.checkedRoots += 1

		for _, entry in rootDefinition.entries do
			local instance, nearest = resolveEntry(root, entry.segments)
			local fullPath = if entry.path == ""
				then rootDefinition.studioPath
				else `{rootDefinition.studioPath}/{entry.path}`
			if not instance then
				addIssue(report.issues, "missing-instance", fullPath, "authored instance is missing", nearest)
				continue
			end
			report.checkedInstances += 1

			if instance.ClassName ~= entry.className then
				addIssue(
					report.issues,
					"class-mismatch",
					fullPath,
					`expected {entry.className}, found {instance.ClassName}`,
					instance
				)
				continue
			end

			for propertyName, expectedValue in entry.properties do
				local ok, rawActual = pcall(function()
					return (instance :: any)[propertyName]
				end)
				if not ok then
					addIssue(
						report.issues,
						"property-unavailable",
						fullPath,
						`cannot read {propertyName}`,
						instance
					)
					continue
				end
				local actualValue = normalize(rawActual)
				if not valuesMatch(actualValue, expectedValue) then
					addIssue(
						report.issues,
						"property-mismatch",
						fullPath,
						`{propertyName}: expected {describe(expectedValue)}, found {describe(actualValue)}`,
						instance
					)
				end
			end
		end
	end

	return report
end

return Validator
