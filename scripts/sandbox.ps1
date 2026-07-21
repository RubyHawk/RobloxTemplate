[CmdletBinding()]
param(
    [string]$RecipePath,
    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "rojo-plugin-state.ps1")
$configPath = Join-Path $root "experiences.config.json"
$experiences = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($requiredEntry in @("template", "playerTest")) {
    if (-not ($experiences.PSObject.Properties.Name -contains $requiredEntry)) {
        throw "experiences.config.json must define `"$requiredEntry`" with name, universeId, and placeId."
    }
}
$playerTest = $experiences.playerTest
$universeId = [long]$playerTest.universeId
$placeId = [long]$playerTest.placeId
if ($universeId -le 0 -or $placeId -le 0) {
    throw "experiences.config.json needs the permanent player-test universeId and placeId under `"playerTest`"."
}

if (-not $RecipePath) {
    $recipes = @(Get-ChildItem -LiteralPath (Join-Path $root "config-presets") -Filter "*.json" -File | Sort-Object Name)
    if ($recipes.Count -eq 0) {
        throw "No recipes exist under config-presets."
    }
    $defaultIndex = 1
    Write-Host "Choose what the shared player-test experience should load:" -ForegroundColor Cyan
    for ($index = 0; $index -lt $recipes.Count; $index++) {
        if ($recipes[$index].BaseName -eq [string]$playerTest.defaultPreset) {
            $defaultIndex = $index + 1
        }
        Write-Host ("  {0}. {1}" -f ($index + 1), $recipes[$index].BaseName)
    }
    $choice = Read-Host "Choice (Enter = $defaultIndex)"
    $selectedIndex = if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $recipes.Count) {
        [int]$choice
    }
    else {
        $defaultIndex
    }
    $RecipePath = $recipes[$selectedIndex - 1].FullName
}
if (-not [System.IO.Path]::IsPathRooted($RecipePath)) {
    $RecipePath = Join-Path $root $RecipePath
}
if (-not (Test-Path -LiteralPath $RecipePath -PathType Leaf)) {
    throw "Recipe not found: $RecipePath"
}

$recipe = Get-Content -LiteralPath $RecipePath -Raw -Encoding UTF8 | ConvertFrom-Json
$recipeId = [System.IO.Path]::GetFileNameWithoutExtension($RecipePath)
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
    if (-not $SmokeTest) {
        $rojoPluginState = Get-RojoStudioPluginState
        if ($rojoPluginState.HasConflict) {
            throw (Get-RojoStudioPluginConflictMessage)
        }
        $setupNeeded = -not (Get-Command rojo -ErrorAction SilentlyContinue) `
            -or -not (Get-Command lune -ErrorAction SilentlyContinue) `
            -or -not $rojoPluginState.HasAny
        if ($setupNeeded) {
            Write-Host "Installing the pinned project tools first..." -ForegroundColor Yellow
            & (Join-Path $PSScriptRoot "setup.ps1") -SkipWorker
            if ($LASTEXITCODE -ne 0) { throw "First-time setup failed." }
        }
    }

    Write-Host "Building recipe $recipeId with UI preset $preset for the permanent sandbox..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "build-game-preset.ps1") `
        -RecipePath $RecipePath `
        -NoStudio `
        -UniverseId $universeId `
        -PlaceId $placeId
    if ($LASTEXITCODE -ne 0) { throw "The sandbox build failed." }

    $projectPath = Join-Path $root "build/designer/$recipeId/SelectedExperience.project.json"
    $project = Get-Content -LiteralPath $projectPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $allowedPlaces = @($project.servePlaceIds)
    if ($allowedPlaces -notcontains $placeId) {
        throw "The generated Rojo project is not restricted to sandbox place $placeId."
    }

    if ($SmokeTest) {
        Write-Host "Sandbox verified: $($playerTest.name) | universe $universeId | place $placeId | recipe $recipeId | UI $preset"
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
    Write-Host "  Experience: $($playerTest.name)"
    Write-Host "  Recipe:     $recipeId"
    Write-Host "  UI preset:  $preset"
    Write-Host "  Save space: $([string]$recipe.dataNamespace) (isolated from other recipes)"
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
