$ErrorActionPreference = "Stop"

function Invoke-Checked([string]$Name, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

$requiredIcons = @(
    "bag.png", "cart.png", "close.png", "codes.png", "coin.png", "community.png", "daily.png",
    "feedback.png", "friends.png", "item.png", "leaderboard.png", "likes.png", "more.png",
    "notifications.png", "offline.png", "potion_x2.png", "potion_x3.png", "premium.png",
    "profile.png", "rewards.png", "search.png", "settings.png", "shop.png", "starter_tool.png",
    "verification.png"
)
foreach ($icon in $requiredIcons) {
    $iconPath = Join-Path $PSScriptRoot "..\assets\icons\gvesster-basic\$icon"
    if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
        throw "Required icon source is missing: $icon"
    }
}

$runtimeUiFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "..\src\client\UI") -Filter "*.luau" -File
    Get-Item -LiteralPath (Join-Path $PSScriptRoot "..\src\client\init.client.luau")
    Get-Item -LiteralPath (Join-Path $PSScriptRoot "..\src\ReplicatedFirst\Loading.client.luau")
    Get-Item -LiteralPath (Join-Path $PSScriptRoot "..\src\starter\StarterExample.server.luau")
    Get-Item -LiteralPath (Join-Path $PSScriptRoot "..\src\starter-client\StarterExample.client.luau")
    Get-Item -LiteralPath (Join-Path $PSScriptRoot "..\ui-packages\PackagePreview.client.luau")
)
$runtimeUiConstructors = @(
    $runtimeUiFiles | Select-String -Pattern 'Instance\.new|:Clone\(|:Destroy\('
)
if ($runtimeUiConstructors.Count -gt 0) {
    $locations = $runtimeUiConstructors | ForEach-Object { "$($_.Path):$($_.LineNumber)" }
    throw "Runtime UI must use authored StarterGui instances. Forbidden constructor found at: $($locations -join ', ')"
}

$uiModel = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\src\ui\TemplateUI.model.json") -Raw | ConvertFrom-Json
$uiRoot = $uiModel.Children | Where-Object Name -eq "Root"
$screens = $uiRoot.Children | Where-Object Name -eq "Screens"
$requiredScreens = @(
    "InventoryScreen", "StoreScreen", "RewardsScreen", "ProfileScreen", "SettingsScreen",
    "FeedbackScreen", "CodesScreen", "BoardsScreen", "CommunityScreen", "DynamicScreen"
)
foreach ($screenName in $requiredScreens) {
    if (-not ($screens.Children | Where-Object Name -eq $screenName)) {
        throw "Authored UI screen is missing: $screenName"
    }
}

Invoke-Checked "StyLua" { stylua --check src tests ui-packages }
Invoke-Checked "Selene" { selene src tests ui-packages }
Invoke-Checked "Wally" { wally install }
Invoke-Checked "Rojo build" { rojo build bootstrap.project.json --output RobloxTemplate.rbxlx }
Invoke-Checked "Reusable UI package build" {
    rojo build ui-packages\UI_BrightSimulator.project.json --output build\UI_BrightSimulator.rbxm
}
Invoke-Checked "Incremental preset package build" {
    rojo build ui-packages\UI_Incremental.project.json --output build\UI_Incremental.rbxm
}
Invoke-Checked "RPG preset package build" {
    rojo build ui-packages\UI_RPG.project.json --output build\UI_RPG.rbxm
}
Invoke-Checked "Game Designer UI smoke test" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\game-designer.ps1 -SmokeTest
}
Invoke-Checked "Incremental configured experience build" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-game-preset.ps1 -RecipePath config-presets\incremental.json -NoStudio
}
Invoke-Checked "RPG configured experience build" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-game-preset.ps1 -RecipePath config-presets\rpg.json -NoStudio
}
Invoke-Checked "Figma bridge syntax" { node --check figma\roblox-ui-bridge\code.js }
Invoke-Checked "Figma incremental mapping" {
    node scripts\figma-ui-bridge.mjs verify --model src\ui\presets\incremental\TemplateUI.model.json
}
Invoke-Checked "Figma RPG mapping" {
    node scripts\figma-ui-bridge.mjs verify --model src\ui\presets\rpg\TemplateUI.model.json
}
Invoke-Checked "Figma patch application" {
    node scripts\figma-ui-bridge.mjs self-test --model src\ui\presets\incremental\TemplateUI.model.json
}
Invoke-Checked "Luau tests" { lune run tests/run }
Invoke-Checked "Worker type check" { npm --prefix worker run typecheck }
Invoke-Checked "Worker tests" { npm --prefix worker test }
Invoke-Checked "Skill validation" { python scripts\validate_skill.py ".agents\skills\roblox-template" }

Write-Host "All template checks passed."
