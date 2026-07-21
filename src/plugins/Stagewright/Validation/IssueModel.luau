--!strict

export type Summary = {
	errorCount: number,
	warningCount: number,
	blockedLevelCount: number,
	readyLevelCount: number,
	selectedErrorCount: number,
	selectedWarningCount: number,
}

export type Group = {
	first: any,
	count: number,
}

local IssueModel = {}

function IssueModel.summarize(issues: { any }, stageIds: { string }, selectedStageId: string): Summary
	local errorCount = 0
	local warningCount = 0
	local selectedErrorCount = 0
	local selectedWarningCount = 0
	local blockedStageIds: { [string]: boolean } = {}
	for _, issue in issues do
		if issue.severity == "Error" then
			errorCount += 1
			if issue.stageId ~= nil then
				blockedStageIds[issue.stageId] = true
			end
		else
			warningCount += 1
		end
		if issue.stageId == selectedStageId then
			if issue.severity == "Error" then
				selectedErrorCount += 1
			else
				selectedWarningCount += 1
			end
		end
	end
	local blockedLevelCount = 0
	for _, stageId in stageIds do
		if blockedStageIds[stageId] then
			blockedLevelCount += 1
		end
	end
	return {
		errorCount = errorCount,
		warningCount = warningCount,
		blockedLevelCount = blockedLevelCount,
		readyLevelCount = math.max(#stageIds - blockedLevelCount, 0),
		selectedErrorCount = selectedErrorCount,
		selectedWarningCount = selectedWarningCount,
	}
end

function IssueModel.group(issues: { any }, filter: string, stageOrderById: { [string]: number }): { Group }
	local groups: { Group } = {}
	local groupedByKey: { [string]: Group } = {}
	for _, issue in issues do
		if (filter == "Error" or filter == "Warning") and issue.severity ~= filter then
			continue
		end
		local key = `{issue.mapId or "project"}|{issue.stageId or "project"}|{issue.severity}|{issue.code}`
		local group = groupedByKey[key]
		if group == nil then
			group = { first = issue, count = 0 }
			groupedByKey[key] = group
			table.insert(groups, group)
		end
		group.count += 1
	end
	table.sort(groups, function(left, right)
		local leftIssue = left.first
		local rightIssue = right.first
		local leftOrder = stageOrderById[leftIssue.stageId] or 0
		local rightOrder = stageOrderById[rightIssue.stageId] or 0
		if leftOrder ~= rightOrder then
			return leftOrder < rightOrder
		end
		if leftIssue.severity ~= rightIssue.severity then
			return leftIssue.severity < rightIssue.severity
		end
		return leftIssue.code < rightIssue.code
	end)
	return groups
end

return table.freeze(IssueModel)
