[CmdletBinding()]
param(
    [string]$RecipePath,
    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$sandboxPath = Join-Path $root "sandbox.config.json"
$sandbox = Get-Content -LiteralPath $sandboxPath -Raw -Encoding UTF8 | ConvertFrom-Json
$universeId = [long]$sandbox.universeId
$placeId = [long]$sandbox.placeId
if ($universeId -le 0 -or $placeId -le 0) {
    throw "sandbox.config.json needs the permanent sandbox universeId and placeId."
}

if (-not $RecipePath) {
    Write-Host "Choose what the shared sandbox should load:" -ForegroundColor Cyan
    Write-Host "  1. Incremental / Simulator"
    Write-Host "  2. RPG"
    $choice = Read-Host "Choice"
    $preset = if ($choice -eq "2") { "rpg" } else { [string]$sandbox.defaultPreset }
    $RecipePath = Join-Path $root "config-presets\$preset.json"
}
if (-not [System.IO.Path]::IsPathRooted($RecipePath)) {
    $RecipePath = Join-Path $root $RecipePath
}
if (-not (Test-Path -LiteralPath $RecipePath -PathType Leaf)) {
    throw "Recipe not found: $RecipePath"
}

$recipe = Get-Content -LiteralPath $RecipePath -Raw -Encoding UTF8 | ConvertFrom-Json
$preset = [string]$recipe.preset
if ($preset -notmatch '^[a-z][a-z0-9_-]{0,39}$') {
    throw "The selected recipe has an invalid preset name."
}

function Find-RobloxStudio {
    $localVersions = Join-Path $env:LOCALAPPDATA "Roblox\Versions"
    if (-not (Test-Path -LiteralPath $localVersions -PathType Container)) { return $null }
    return Get-ChildItem -LiteralPath $localVersions -Filter "RobloxStudioBeta.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Stop-StaleRojoServer {
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) { return }
    $listeners = @(Get-NetTCPConnection -LocalPort 34872 -State Listen -ErrorAction SilentlyContinue)
    foreach ($listener in $listeners) {
        $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
        if (-not $process) { continue }
        if ($process.ProcessName -ne "rojo") {
            throw "Port 34872 is used by $($process.ProcessName). Close it before opening the sandbox."
        }
        Write-Host "Closing the previous Rojo sandbox connection..." -ForegroundColor Yellow
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(3000) | Out-Null
    }
}

Push-Location $root
try {
    $rojoPlugin = Join-Path $env:LOCALAPPDATA "Roblox\Plugins\RojoManagedPlugin.rbxm"
    $setupNeeded = -not (Get-Command rojo -ErrorAction SilentlyContinue) `
        -or -not (Get-Command lune -ErrorAction SilentlyContinue) `
        -or -not (Test-Path -LiteralPath $rojoPlugin -PathType Leaf)
    if ($setupNeeded) {
        Write-Host "Installing the pinned project tools first..." -ForegroundColor Yellow
        & (Join-Path $PSScriptRoot "setup.ps1") -SkipWorker
        if ($LASTEXITCODE -ne 0) { throw "First-time setup failed." }
    }

    Write-Host "Building $preset for the permanent sandbox..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "build-game-preset.ps1") `
        -RecipePath $RecipePath `
        -NoStudio `
        -UniverseId $universeId `
        -PlaceId $placeId
    if ($LASTEXITCODE -ne 0) { throw "The sandbox build failed." }

    $projectPath = Join-Path $root "build\designer\$preset\SelectedExperience.project.json"
    $project = Get-Content -LiteralPath $projectPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $allowedPlaces = @($project.servePlaceIds)
    if ($allowedPlaces -notcontains $placeId) {
        throw "The generated Rojo project is not restricted to sandbox place $placeId."
    }

    if ($SmokeTest) {
        Write-Host "Sandbox verified: $($sandbox.name) | universe $universeId | place $placeId | preset $preset"
        exit 0
    }

    $studio = Find-RobloxStudio
    if (-not $studio) { throw "Roblox Studio is not installed." }
    Stop-StaleRojoServer

    Write-Host "Opening the existing cloud sandbox. No new experience is created." -ForegroundColor Green
    Start-Process -FilePath $studio.FullName -ArgumentList @(
        "-task", "EditPlace",
        "-placeId", [string]$placeId,
        "-universeId", [string]$universeId
    )

    Write-Host ""
    Write-Host "SHARED SANDBOX READY" -ForegroundColor Green
    Write-Host "  Experience: $($sandbox.name)"
    Write-Host "  Preset:     $preset"
    Write-Host "  Save space: $preset (isolated from other presets)"
    Write-Host ""
    Write-Host "In Studio, click Plugins > Rojo > Connect, then press Play." -ForegroundColor Cyan
    Write-Host "Use File > Publish to Roblox to update this same sandbox; do not use Publish As." -ForegroundColor Yellow
    Write-Host "Keep this window open while editing. Press Ctrl+C when finished."

    & rojo serve $projectPath
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
