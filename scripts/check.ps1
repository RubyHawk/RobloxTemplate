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

Invoke-Checked "StyLua" { stylua --check src tests }
Invoke-Checked "Selene" { selene src tests }
Invoke-Checked "Wally" { wally install }
Invoke-Checked "Rojo build" { rojo build bootstrap.project.json --output RobloxTemplate.rbxlx }
Invoke-Checked "Luau tests" { lune run tests/run }
Invoke-Checked "Worker type check" { npm --prefix worker run typecheck }
Invoke-Checked "Worker tests" { npm --prefix worker test }
Invoke-Checked "Skill validation" { python scripts\validate_skill.py ".agents\skills\roblox-template" }

Write-Host "All template checks passed."
