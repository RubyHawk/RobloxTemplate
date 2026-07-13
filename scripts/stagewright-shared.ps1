[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [switch]$SkipPluginInstall
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root "experiences.config.json"
$expectedPlaceId = [long]128136881672145

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

Push-Location $root
try {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "experiences.config.json is missing."
    }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ($config.PSObject.Properties.Name -contains "towerDefense")) {
        throw "experiences.config.json needs the existing shared game under towerDefense."
    }
    $experience = $config.towerDefense
    $placeId = [long]$experience.placeId
    $universeId = [long]$experience.universeId
    if ($placeId -ne $expectedPlaceId) {
        throw "Stagewright shared-place guard refused place $placeId; expected $expectedPlaceId."
    }
    if ($universeId -le 0) {
        throw "The towerDefense universeId is missing from experiences.config.json."
    }

    if ($SmokeTest) {
        Write-Host "Stagewright shared source verified: $($experience.name) | universe $universeId | place $placeId"
        exit 0
    }

    if (-not $SkipPluginInstall) {
        & (Join-Path $PSScriptRoot "install-grid-plugin.ps1")
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

    $studio = Find-RobloxStudio
    if ($null -eq $studio) {
        throw "Roblox Studio is not installed."
    }

    Write-Host "Opening the existing shared tower-defense experience. No experience is created." -ForegroundColor Green
    Write-Host "Rojo is intentionally not started: Team Create data may not exist in the repository." -ForegroundColor Yellow
    Start-Process -FilePath $studio.FullName -ArgumentList @(
        "-task", "EditPlace",
        "-placeId", [string]$placeId,
        "-universeId", [string]$universeId
    )

    Write-Host ""
    Write-Host "STAGEWRIGHT SHARED MIGRATION READY" -ForegroundColor Cyan
    Write-Host "  1. In Studio, open Plugins > Stagewright."
    Write-Host "  2. Confirm imported legacy cells and route controls before changing them."
    Write-Host "  3. Resolve validation errors, then use Validate > Export Bundle."
    Write-Host "  4. Run: lune run scripts/stagewright-import.luau <exported-rbxm>"
    Write-Host "  5. Review diffs and use playerTest for runtime QA before publishing code."
}
finally {
    Pop-Location
}
