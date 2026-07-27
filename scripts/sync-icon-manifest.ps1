[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $root "assets\icons\icon-manifest.json"
$outputPath = Join-Path $root "src\shared\IconAssets.luau"
$assetsRoot = [System.IO.Path]::GetFullPath((Join-Path $root "assets\icons"))
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$expectedRoles = @(
    "bag", "cart", "close", "codes", "coin", "community", "daily", "feedback", "friends", "item",
    "leaderboard", "likes", "more", "notifications", "offline", "potionX2", "potionX3", "premium",
    "profile", "rewards", "rollDice", "search", "settings", "shop", "starterTool", "talentUpgrade",
    "verification"
)
$states = @("demo-public", "pending-upload", "uploaded", "game-asset", "disabled")

if ([int]$manifest.schemaVersion -ne 1) { throw "Unsupported icon manifest version." }
$ownerType = [string]$manifest.cloudOwner.type
$ownerId = [long]$manifest.cloudOwner.id
if ($ownerType -notin @("pending", "user", "group")) { throw "cloudOwner.type must be pending, user, or group." }
if (($ownerType -eq "pending" -and $ownerId -ne 0) -or ($ownerType -ne "pending" -and $ownerId -le 0)) {
    throw "cloudOwner.id must be 0 while pending and positive after choosing a user or group."
}
$actualRoles = @($manifest.roles.PSObject.Properties.Name | Sort-Object)
if (($actualRoles -join ',') -ne (($expectedRoles | Sort-Object) -join ',')) {
    throw "Icon manifest roles do not match IconCatalog. Adding a new role requires a programmer to update both."
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("--!strict")
$lines.Add("")
$lines.Add("-- Generated from assets/icons/icon-manifest.json by scripts/sync-icon-manifest.ps1.")
$lines.Add("-- Edit the manifest through ICON_LIBRARY.cmd, not this file.")
$lines.Add("local ids = {")

foreach ($role in $expectedRoles) {
    $entry = $manifest.roles.$role
    $source = [string]$entry.source
    if ($source -notmatch '^assets/icons/[A-Za-z0-9_./-]+\.png$') {
        throw "Icon '$role' has an unsafe source path: $source"
    }
    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $root ($source -replace '/', '\')))
    if (-not $sourcePath.StartsWith($assetsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Icon '$role' points outside assets/icons."
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Icon '$role' source file is missing: $source"
    }
    $hash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne [string]$entry.sourceSha256) {
        throw "Icon '$role' changed without using ICON_LIBRARY.cmd. Expected hash $($entry.sourceSha256), got $hash."
    }

    $state = [string]$entry.state
    if ($state -notin $states) { throw "Icon '$role' has invalid state '$state'." }
    $content = [string]$entry.content
    $contentValid = $content -eq "" `
        -or $content -match '^\d+$' `
        -or $content -match '^rbxassetid://\d+$' `
        -or $content -match '^rbxgameasset://Images/[A-Za-z0-9_-]+$'
    if (-not $contentValid) {
        throw "Icon '$role' has invalid Roblox content '$content'."
    }
    if ($state -in @("pending-upload", "disabled") -and $content -ne "") {
        throw "Icon '$role' must have empty content while state is '$state'."
    }
    if ($state -in @("uploaded", "game-asset") -and $content -eq "") {
        throw "Icon '$role' needs Roblox content while state is '$state'."
    }
    $lines.Add("`t$role = `"$content`",")
}

$lines.Add("}")
$lines.Add("")
$lines.Add("return table.freeze({ ids = table.freeze(ids) })")
$expected = ($lines -join "`n") + "`n"

if ($Check) {
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw "Generated IconAssets.luau is missing." }
    $actual = (Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8) -replace "`r`n", "`n"
    if ($actual -ne $expected) { throw "IconAssets.luau is stale. Run ICON_LIBRARY.cmd and choose Validate/save." }
    Write-Host "Icon manifest and generated Luau are synchronized."
    exit 0
}

[System.IO.File]::WriteAllText($outputPath, $expected, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated $outputPath" -ForegroundColor Green
