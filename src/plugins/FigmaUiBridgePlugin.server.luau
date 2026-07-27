--!strict

-- Read-only Studio companion for the Figma -> repository -> Rojo UI pipeline.
-- It never imports UI, edits the place, or publishes. It only compares the
-- currently synced authored instances with the generated repository manifest.

local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")

local Validator = require(script.Parent.FigmaUiBridge.Validator)
local Manifest = require(script.Parent.FigmaUiBridge.Manifest)

local PLUGIN_NAME = "Figma UI"
local PLUGIN_WIDGET_ID = "RNGDefenderFigmaUiDelivery"
local PLUGIN_BUTTON_ID = "OpenFigmaUiDelivery"
local PLUGIN_ICON = "rbxasset://textures/StudioSharedUI/insert.png"

local BACKGROUND = Color3.fromRGB(31, 33, 37)
local SURFACE = Color3.fromRGB(39, 42, 47)
local BORDER = Color3.fromRGB(66, 70, 78)
local TEXT = Color3.fromRGB(235, 237, 241)
local MUTED = Color3.fromRGB(165, 170, 181)
local GOOD = Color3.fromRGB(76, 175, 112)
local WARNING = Color3.fromRGB(222, 169, 65)
local BAD = Color3.fromRGB(218, 91, 91)
local ACCENT = Color3.fromRGB(72, 139, 214)

local toolbar = plugin:CreateToolbar(PLUGIN_NAME)
local toolbarButton = toolbar:CreateButton(
	PLUGIN_BUTTON_ID,
	"Inspect the Rojo-synced RNG Defender UI delivery",
	PLUGIN_ICON,
	"Figma UI"
)
toolbarButton.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGuiAsync(
	PLUGIN_WIDGET_ID,
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 430, 620, 350, 420)
)
widget.Title = "Figma UI Delivery"
widget.Name = PLUGIN_WIDGET_ID

local function makeLabel(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.BuilderSans
	label.Text = text
	label.TextColor3 = TEXT
	label.TextSize = 14
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Size = size
	label.Position = position
	label.Parent = parent
	return label
end

local function makeButton(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = true
	button.BackgroundColor3 = SURFACE
	button.BorderSizePixel = 0
	button.Font = Enum.Font.BuilderSansBold
	button.Text = text
	button.TextColor3 = TEXT
	button.TextSize = 14
	button.Size = size
	button.Position = position
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER
	stroke.Thickness = 1
	stroke.Parent = button
	return button
end

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundColor3 = BACKGROUND
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = widget

local title =
	makeLabel(root, "Title", "RNG Defender UI delivery", UDim2.new(1, -32, 0, 28), UDim2.fromOffset(16, 14))
title.Font = Enum.Font.BuilderSansBold
title.TextSize = 18

local sourceLabel = makeLabel(root, "Source", "", UDim2.new(1, -32, 0, 52), UDim2.fromOffset(16, 46))
sourceLabel.TextColor3 = MUTED
sourceLabel.TextSize = 12

local status =
	makeLabel(root, "Status", "Not checked yet.", UDim2.new(1, -32, 0, 52), UDim2.fromOffset(16, 102))
status.Font = Enum.Font.BuilderSansBold
status.TextSize = 14

local refreshButton =
	makeButton(root, "Refresh", "Refresh", UDim2.new(0.34, -14, 0, 34), UDim2.fromOffset(16, 158))
refreshButton.BackgroundColor3 = ACCENT
local selectButton = makeButton(
	root,
	"SelectIssue",
	"Select first issue",
	UDim2.new(0.33, -10, 0, 34),
	UDim2.new(0.34, 8, 0, 158)
)
local printButton =
	makeButton(root, "PrintReport", "Print report", UDim2.new(0.33, -14, 0, 34), UDim2.new(0.67, 0, 0, 158))

local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.BackgroundColor3 = BORDER
divider.BorderSizePixel = 0
divider.Size = UDim2.new(1, -32, 0, 1)
divider.Position = UDim2.fromOffset(16, 207)
divider.Parent = root

local issuesTitle =
	makeLabel(root, "IssuesTitle", "Issues", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 220))
issuesTitle.Font = Enum.Font.BuilderSansBold

local issues = Instance.new("ScrollingFrame")
issues.Name = "Issues"
issues.AutomaticCanvasSize = Enum.AutomaticSize.Y
issues.BackgroundColor3 = SURFACE
issues.BorderSizePixel = 0
issues.CanvasSize = UDim2.new()
issues.ScrollBarThickness = 6
issues.Size = UDim2.new(1, -32, 1, -268)
issues.Position = UDim2.fromOffset(16, 250)
issues.Parent = root

local issuesCorner = Instance.new("UICorner")
issuesCorner.CornerRadius = UDim.new(0, 5)
issuesCorner.Parent = issues

local issuesPadding = Instance.new("UIPadding")
issuesPadding.PaddingTop = UDim.new(0, 10)
issuesPadding.PaddingBottom = UDim.new(0, 10)
issuesPadding.PaddingLeft = UDim.new(0, 10)
issuesPadding.PaddingRight = UDim.new(0, 10)
issuesPadding.Parent = issues

local issueText =
	makeLabel(issues, "Text", "Run Refresh after Rojo is connected.", UDim2.fromScale(1, 0), UDim2.new())
issueText.AutomaticSize = Enum.AutomaticSize.Y
issueText.TextColor3 = MUTED
issueText.TextSize = 12

local currentReport: Validator.Report? = nil

local function shortChecksum(checksum: string): string
	if checksum == "" then
		return "baseline"
	end
	return string.sub(checksum, 1, 12)
end

local function renderReport(report: Validator.Report)
	currentReport = report
	local issueCount = #report.issues
	if issueCount == 0 then
		status.Text =
			`MATCHED · {report.checkedRoots}/{Manifest.rootCount} roots · {report.checkedInstances} instances`
		status.TextColor3 = GOOD
		issueText.Text = "The stopped Studio place matches the repository delivery manifest."
		issueText.TextColor3 = GOOD
		return
	end

	status.Text =
		`{issueCount} ISSUE{if issueCount == 1 then "" else "S"} · {report.checkedRoots}/{Manifest.rootCount} roots checked`
	status.TextColor3 = if report.checkedRoots == 0 then BAD else WARNING
	local lines = {}
	for index, issue in report.issues do
		table.insert(lines, `{index}. [{issue.kind}] {issue.path}\n   {issue.message}`)
		if index >= 100 then
			table.insert(lines, `\n...and {issueCount - index} more. Use Print report for the complete list.`)
			break
		end
	end
	issueText.Text = table.concat(lines, "\n\n")
	issueText.TextColor3 = TEXT
end

local function refresh()
	if RunService:IsRunning() then
		status.Text = "Stop the playtest before validating authored UI."
		status.TextColor3 = WARNING
		issueText.Text =
			"Runtime controllers intentionally change visibility and content. Validation is edit-mode only."
		issueText.TextColor3 = MUTED
		currentReport = nil
		return
	end
	renderReport(Validator.validate(Manifest))
end

sourceLabel.Text =
	`Figma: {Manifest.source.exportedAt} · {shortChecksum(Manifest.source.checksum)}\nRepo model: {shortChecksum(
		Manifest.modelChecksum
	)} · {Manifest.entryCount} instances`

refreshButton.Activated:Connect(refresh)
selectButton.Activated:Connect(function()
	local report = currentReport
	if not report then
		refresh()
		report = currentReport
	end
	if not report then
		return
	end
	for _, issue in report.issues do
		if issue.instance then
			Selection:Set({ issue.instance })
			return
		end
	end
end)
printButton.Activated:Connect(function()
	local report = currentReport
	if not report then
		refresh()
		report = currentReport
	end
	if not report then
		return
	end
	print(
		`[Figma UI] {Manifest.workspace.name} · source {shortChecksum(Manifest.source.checksum)} · model {shortChecksum(
			Manifest.modelChecksum
		)}`
	)
	if #report.issues == 0 then
		print(`[Figma UI] MATCHED: {report.checkedRoots} roots, {report.checkedInstances} instances.`)
		return
	end
	for index, issue in report.issues do
		warn(`[Figma UI] {index}. [{issue.kind}] {issue.path}: {issue.message}`)
	end
end)

toolbarButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	if widget.Enabled then
		refresh()
	end
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toolbarButton:SetActive(widget.Enabled)
end)
