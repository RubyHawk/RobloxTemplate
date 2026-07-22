[CmdletBinding()]
param(
    [switch]$NoStudio,
    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root "experiences.config.json"
$patchProjectPath = Join-Path $root "patches\rng-defender-grid-demo.project.json"
$expectedUniverseId = [long]10479279603
$expectedPlaceId = [long]128136881672145
$rojoPort = 34872
. (Join-Path $PSScriptRoot "rojo-plugin-state.ps1")

function Find-RobloxStudio {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Roblox\Versions"),
        (Join-Path $env:PROGRAMFILES "Roblox")
    )
    foreach ($directory in $candidates) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            continue
        }
        $studio = Get-ChildItem -LiteralPath $directory -Filter "RobloxStudioBeta.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($null -ne $studio) {
            return $studio
        }
    }
    return $null
}

function Stop-StaleRojoServer {
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        return
    }
    $listeners = @(Get-NetTCPConnection -LocalPort $rojoPort -State Listen -ErrorAction SilentlyContinue)
    foreach ($listener in $listeners) {
        $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }
        if ($process.ProcessName -ne "rojo") {
            throw "Port $rojoPort is used by $($process.ProcessName). Close it before serving RNG Defender."
        }
        Write-Host "Closing the previous Rojo session so the wrong project cannot reconnect..." -ForegroundColor Yellow
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(3000) | Out-Null
    }
}

Push-Location $root
try {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "experiences.config.json is missing."
    }
    if (-not (Test-Path -LiteralPath $patchProjectPath -PathType Leaf)) {
        throw "The RNG Defender Rojo patch is missing: $patchProjectPath"
    }

    $experiences = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ($experiences.PSObject.Properties.Name -contains "towerDefense")) {
        throw "experiences.config.json must define the permanent RNG Defender place under towerDefense."
    }
    $experience = $experiences.towerDefense
    $universeId = [long]$experience.universeId
    $placeId = [long]$experience.placeId
    if ($universeId -ne $expectedUniverseId -or $placeId -ne $expectedPlaceId) {
        throw "RNG Defender guard refused universe $universeId / place $placeId; expected universe $expectedUniverseId / place $expectedPlaceId."
    }

    $patchProject = Get-Content -LiteralPath $patchProjectPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $allowedPlaces = @($patchProject.servePlaceIds)
    if ($allowedPlaces.Count -ne 1 -or [long]$allowedPlaces[0] -ne $expectedPlaceId) {
        throw "The RNG Defender patch must allow only place $expectedPlaceId through servePlaceIds."
    }

    if ($SmokeTest) {
        Write-Host "RNG Defender delivery verified: $($experience.name) | universe $universeId | place $placeId | port $rojoPort"
        exit 0
    }

    if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
        Write-Host "Installing the pinned project tools first..." -ForegroundColor Yellow
        & (Join-Path $PSScriptRoot "setup.ps1") -SkipWorker
        if ($LASTEXITCODE -ne 0) {
            throw "First-time setup failed."
        }
    }

    $studio = if ($NoStudio) { $null } else { Find-RobloxStudio }
    if (-not $NoStudio -and $null -eq $studio) {
        throw "Roblox Studio is not installed."
    }

    if (-not $NoStudio) {
        Write-Host "Installing the current private Stagewright Studio plugin..." -ForegroundColor Yellow
        & (Join-Path $PSScriptRoot "install-grid-plugin.ps1")
        if ($LASTEXITCODE -ne 0) {
            throw "Stagewright could not be installed. Save your work, close every Studio window, and try again."
        }

        $rojoPluginState = Get-RojoStudioPluginState
        if ($rojoPluginState.HasConflict) {
            throw (Get-RojoStudioPluginConflictMessage)
        }
        if ($rojoPluginState.HasCreatorStore) {
            Write-Host "Using the single installed Creator Store Rojo plugin." -ForegroundColor Green
        }
        else {
            Write-Host "Installing or refreshing the matching local Rojo Studio plugin..." -ForegroundColor Yellow
            & rojo plugin install
            if ($LASTEXITCODE -ne 0) {
                throw "The matching Rojo Studio plugin could not be installed. Close Studio and try again."
            }
        }
    }

    Stop-StaleRojoServer

    if (-not $NoStudio) {
        Write-Host "Opening the permanent RNG Defender experience. No experience is created." -ForegroundColor Green
        Start-Process -FilePath $studio.FullName -ArgumentList @(
            "-task", "EditPlace",
            "-placeId", [string]$placeId,
            "-universeId", [string]$universeId
        )
    }

    Write-Host ""
    Write-Host "RNG DEFENDER DELIVERY READY" -ForegroundColor Green
    Write-Host "  Experience: $($experience.name)"
    Write-Host "  Universe:   $universeId"
    Write-Host "  Place:      $placeId"
    Write-Host "  Rojo port:  $rojoPort"
    Write-Host ""
    Write-Host "In Studio, connect Plugins > Rojo, stop and restart Play, then verify the portal." -ForegroundColor Cyan
    Write-Host "Use File > Publish to Roblox to update this same place; never use Publish As." -ForegroundColor Yellow
    Write-Host "Do not open or publish build\RNGDefenderSafePatch.rbxlx; this structural build intentionally omits unknown Team Create world data." -ForegroundColor Yellow
    Write-Host "Keep this window open while editing. Press Ctrl+C when finished."

    & rojo serve $patchProjectPath --port $rojoPort
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
