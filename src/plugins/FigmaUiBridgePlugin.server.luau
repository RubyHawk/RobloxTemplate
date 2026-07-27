--!strict

-- Studio companion for the Figma -> repository -> Rojo UI pipeline.
-- Import requests are sent to a token-authenticated, loopback-only helper.
-- The helper invokes the repository's canonical upserter; this plugin never
-- creates, destroys, or rewrites gameplay UI instances in the DataModel.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")

local Validator = require(script.Parent.FigmaUiBridge.Validator)
local Manifest = require(script.Parent.FigmaUiBridge.Manifest)
local Runtime = require(script.Parent.FigmaUiBridge.Runtime)

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
local ACCENT_DISABLED = Color3.fromRGB(54, 72, 91)

local toolbar = plugin:CreateToolbar(PLUGIN_NAME)
local toolbarButton = toolbar:CreateButton(
	PLUGIN_BUTTON_ID,
	"Import and verify the latest authoritative RNG Defender Figma export",
	PLUGIN_ICON,
	"Figma UI"
)
toolbarButton.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGuiAsync(
	PLUGIN_WIDGET_ID,
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 430, 680, 350, 470)
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

local importButton = makeButton(
	root,
	"ImportLatest",
	"Import latest Figma",
	UDim2.new(1, -32, 0, 42),
	UDim2.fromOffset(16, 104)
)
importButton.BackgroundColor3 = ACCENT
importButton.TextSize = 15

local helperLabel = makeLabel(
	root,
	"Helper",
	"Uses the newest authoritative export in Downloads, then waits for Rojo.",
	UDim2.new(1, -32, 0, 34),
	UDim2.fromOffset(16, 154)
)
helperLabel.TextColor3 = MUTED
helperLabel.TextSize = 11

local status =
	makeLabel(root, "Status", "Not checked yet.", UDim2.new(1, -32, 0, 48), UDim2.fromOffset(16, 194))
status.Font = Enum.Font.BuilderSansBold
status.TextSize = 14

local refreshButton =
	makeButton(root, "Refresh", "Refresh", UDim2.new(0.34, -14, 0, 34), UDim2.fromOffset(16, 246))
local selectButton = makeButton(
	root,
	"SelectIssue",
	"Select first issue",
	UDim2.new(0.33, -10, 0, 34),
	UDim2.new(0.34, 8, 0, 246)
)
local printButton =
	makeButton(root, "PrintReport", "Print report", UDim2.new(0.33, -14, 0, 34), UDim2.new(0.67, 0, 0, 246))

local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.BackgroundColor3 = BORDER
divider.BorderSizePixel = 0
divider.Size = UDim2.new(1, -32, 0, 1)
divider.Position = UDim2.fromOffset(16, 295)
divider.Parent = root

local issuesTitle =
	makeLabel(root, "IssuesTitle", "Delivery report", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 308))
issuesTitle.Font = Enum.Font.BuilderSansBold

local issues = Instance.new("ScrollingFrame")
issues.Name = "Issues"
issues.AutomaticCanvasSize = Enum.AutomaticSize.Y
issues.BackgroundColor3 = SURFACE
issues.BorderSizePixel = 0
issues.CanvasSize = UDim2.new()
issues.ScrollBarThickness = 6
issues.Size = UDim2.new(1, -32, 1, -356)
issues.Position = UDim2.fromOffset(16, 338)
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

local currentManifest: Validator.Manifest = Manifest
local currentReport: Validator.Report? = nil
local importing = false

local function shortChecksum(checksum: string): string
	if checksum == "" then
		return "baseline"
	end
	return string.sub(checksum, 1, 12)
end

local function renderSource()
	sourceLabel.Text = `Figma: {currentManifest.source.exportedAt} | {shortChecksum(
		currentManifest.source.checksum
	)}\nRepo model: {shortChecksum(currentManifest.modelChecksum)} | {currentManifest.entryCount} instances`
end

local function renderReport(report: Validator.Report)
	currentReport = report
	local issueCount = #report.issues
	if issueCount == 0 then
		status.Text =
			`MATCHED | {report.checkedRoots}/{currentManifest.rootCount} roots | {report.checkedInstances} instances`
		status.TextColor3 = GOOD
		issueText.Text = "The stopped Studio place matches the latest repository delivery manifest."
		issueText.TextColor3 = GOOD
		return
	end

	status.Text =
		`{issueCount} ISSUE{if issueCount == 1 then "" else "S"} | {report.checkedRoots}/{currentManifest.rootCount} roots checked`
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

local function rejectPlayMode(action: string): boolean
	if not RunService:IsRunning() then
		return false
	end
	status.Text = `Stop the playtest before {action}.`
	status.TextColor3 = WARNING
	issueText.Text =
		"Runtime controllers intentionally change visibility and content. Figma delivery runs in edit mode only."
	issueText.TextColor3 = MUTED
	currentReport = nil
	return true
end

local function refresh()
	if rejectPlayMode("validating authored UI") then
		return
	end
	renderReport(Validator.validate(currentManifest))
end

local function requestJson(method: string, route: string): (boolean, any)
	local requestOk, responseOrError = pcall(function()
		return HttpService:RequestAsync({
			Url = Runtime.baseUrl .. route,
			Method = method,
			Headers = {
				["Content-Type"] = "application/json",
				["x-figma-ui-token"] = Runtime.token,
			},
			Body = if method == "POST" then "{}" else nil,
		})
	end)
	if not requestOk then
		return false, {
			error = tostring(responseOrError),
			connection = true,
		}
	end

	local response = responseOrError :: any
	local decodeOk, decodedOrError = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not decodeOk then
		return false, {
			error = `Local bridge returned unreadable JSON (HTTP {response.StatusCode}).`,
		}
	end
	local decoded = decodedOrError :: any
	if not response.Success or decoded.ok ~= true then
		return false, decoded
	end
	return true, decoded
end

local function setImporting(value: boolean)
	importing = value
	importButton.Active = not value
	importButton.AutoButtonColor = not value
	importButton.BackgroundColor3 = if value then ACCENT_DISABLED else ACCENT
	importButton.Text = if value then "Importing..." else "Import latest Figma"
end

local function showBridgeError(payload: any)
	status.Text = "FIGMA IMPORT STOPPED"
	status.TextColor3 = BAD
	local details = if type(payload) == "table" then tostring(payload.details or "") else ""
	local message = if type(payload) == "table"
		then tostring(payload.error or "Unknown bridge error.")
		else tostring(payload)
	if type(payload) == "table" and payload.connection == true then
		message ..= "\n\nKeep 8_RNG_DEFENDER.cmd running. On the first request, allow this plugin to access 127.0.0.1."
	end
	issueText.Text = if details == "" then message else `{message}\n\n{details}`
	issueText.TextColor3 = TEXT
end

local function importLatest()
	if importing or rejectPlayMode("importing Figma UI") then
		return
	end

	setImporting(true)
	currentReport = nil
	status.Text = "Applying the newest authoritative Figma export..."
	status.TextColor3 = WARNING
	issueText.Text =
		"The repository upserter is rebuilding all mapped UI roots. Do not start Play until this finishes."
	issueText.TextColor3 = MUTED

	local applyOk, applyPayload = requestJson("POST", "/apply")
	if not applyOk then
		showBridgeError(applyPayload)
		setImporting(false)
		return
	end

	local jobId = if type(applyPayload.job) == "table" then tostring(applyPayload.job.id or "") else ""
	if jobId == "" then
		showBridgeError({ error = "The local bridge did not start an import job." })
		setImporting(false)
		return
	end

	local importResult: any = nil
	for _ = 1, 240 do
		local statusOk, statusPayload = requestJson("GET", "/status")
		if not statusOk or type(statusPayload.job) ~= "table" then
			showBridgeError(statusPayload)
			setImporting(false)
			return
		end
		local job = statusPayload.job
		if tostring(job.id or "") ~= jobId then
			showBridgeError({ error = "The local bridge changed import jobs unexpectedly." })
			setImporting(false)
			return
		end
		if job.state == "failed" then
			showBridgeError(job)
			setImporting(false)
			return
		elseif job.state == "succeeded" then
			importResult = job.result
			break
		end
		task.wait(0.5)
	end
	if type(importResult) ~= "table" then
		showBridgeError({ error = "The repository import did not finish within two minutes." })
		setImporting(false)
		return
	end

	local manifestOk, manifestPayload = requestJson("GET", "/manifest")
	if not manifestOk or type(manifestPayload.manifest) ~= "table" then
		showBridgeError(
			if manifestOk
				then { error = "The local bridge returned no delivery manifest." }
				else manifestPayload
		)
		setImporting(false)
		return
	end

	currentManifest = manifestPayload.manifest :: Validator.Manifest
	renderSource()
	status.Text = "Repository updated. Waiting for Rojo to sync..."
	status.TextColor3 = WARNING
	issueText.Text =
		`Imported {tostring(importResult.patchName)}. Checking the authored Studio hierarchy now.`

	local latestReport: Validator.Report? = nil
	for _ = 1, 40 do
		latestReport = Validator.validate(currentManifest)
		if #latestReport.issues == 0 then
			renderReport(latestReport)
			issueText.Text =
				`Imported {tostring(importResult.patchName)} and verified the complete Rojo-synced hierarchy.`
			issueText.TextColor3 = GOOD
			setImporting(false)
			return
		end
		task.wait(0.5)
	end

	if latestReport then
		renderReport(latestReport)
	end
	status.Text = "REPOSITORY UPDATED | STUDIO NOT MATCHED"
	status.TextColor3 = WARNING
	issueText.Text = "Figma was imported into the repository, but Studio did not match within 20 seconds. Connect/reconnect Rojo, then click Refresh.\n\n"
		.. issueText.Text
	setImporting(false)
end

renderSource()

importButton.Activated:Connect(function()
	task.spawn(importLatest)
end)
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
		`[Figma UI] {currentManifest.workspace.name} | source {shortChecksum(currentManifest.source.checksum)} | model {shortChecksum(
			currentManifest.modelChecksum
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
