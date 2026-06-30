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
Invoke-Checked "Luau tests" { lune run tests/run }
Invoke-Checked "Worker type check" { npm --prefix worker run typecheck }
Invoke-Checked "Worker tests" { npm --prefix worker test }
Invoke-Checked "Skill validation" { python scripts\validate_skill.py ".agents\skills\roblox-template" }

Write-Host "All template checks passed."
