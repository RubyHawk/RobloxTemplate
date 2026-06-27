[CmdletBinding()]
param(
    [switch]$NoStudio
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$placeFile = Join-Path $root "build\RobloxTemplate.rbxlx"

function Find-RobloxStudio {
    $localVersions = Join-Path $env:LOCALAPPDATA "Roblox\Versions"
    if (-not (Test-Path $localVersions -PathType Container)) {
        return $null
    }
    return Get-ChildItem -LiteralPath $localVersions -Filter "RobloxStudioBeta.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

Push-Location $root
try {
    if (-not (Get-Command rojo -ErrorAction SilentlyContinue) -or -not (Test-Path $placeFile -PathType Leaf)) {
        Write-Host "The template needs its first-time setup. Running it now..." -ForegroundColor Yellow
        & (Join-Path $PSScriptRoot "setup.ps1") -SkipWorker
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

    if (-not $NoStudio) {
        $studio = Find-RobloxStudio
        if ($null -eq $studio) {
            Write-Host "Roblox Studio is not installed. Install it, then run 2_START.cmd again:" -ForegroundColor Red
            Write-Host "https://create.roblox.com/docs/studio/setup"
            exit 1
        }
        Write-Host "Opening the generated place in Roblox Studio..." -ForegroundColor Cyan
        Start-Process -FilePath $studio.FullName -ArgumentList ('"{0}"' -f $placeFile)
    }

    Write-Host ""
    Write-Host "ROJO IS READY" -ForegroundColor Green
    Write-Host "In Studio:"
    Write-Host "  1. Open the Plugins tab."
    Write-Host "  2. Click Rojo, then Connect."
    Write-Host "  3. Press Play."
    Write-Host ""
    Write-Host "Keep this window open while editing. Press Ctrl+C here when finished." -ForegroundColor Yellow
    rojo serve default.project.json
    exit $LASTEXITCODE
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Run 3_CHECK.cmd for a full diagnosis."
    exit 1
}
finally {
    Pop-Location
}
