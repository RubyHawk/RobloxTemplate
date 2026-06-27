[CmdletBinding()]
param(
    [switch]$NoStudio
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $root "build"
$project = Get-Content -LiteralPath (Join-Path $root "default.project.json") -Raw | ConvertFrom-Json
$projectName = [string]$project.name
$safeProjectName = $projectName -replace '[^A-Za-z0-9._-]', '_'
$placeFile = Join-Path $buildDirectory "$safeProjectName.rbxlx"

function Find-RobloxStudio {
    $localVersions = Join-Path $env:LOCALAPPDATA "Roblox\Versions"
    if (-not (Test-Path $localVersions -PathType Container)) {
        return $null
    }
    return Get-ChildItem -LiteralPath $localVersions -Filter "RobloxStudioBeta.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Stop-StaleRojoServer {
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        return
    }

    $listeners = @(Get-NetTCPConnection -LocalPort 34872 -State Listen -ErrorAction SilentlyContinue)
    foreach ($processId in ($listeners.OwningProcess | Sort-Object -Unique)) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if (-not $process) {
            continue
        }
        if ($process.ProcessName -ne "rojo") {
            throw "Port 34872 is being used by $($process.ProcessName). Close that program, then run 2_START.cmd again."
        }

        Write-Host "Closing an older Rojo session so it cannot load the previous branch..." -ForegroundColor Yellow
        Stop-Process -Id $processId -Force
        $process.WaitForExit(3000) | Out-Null
    }
}

Push-Location $root
try {
    $rojoPlugin = Join-Path $env:LOCALAPPDATA "Roblox\Plugins\RojoManagedPlugin.rbxm"
    if (-not (Get-Command rojo -ErrorAction SilentlyContinue) -or -not (Test-Path $rojoPlugin -PathType Leaf)) {
        Write-Host "The template needs its first-time setup. Running it now..." -ForegroundColor Yellow
        & (Join-Path $PSScriptRoot "setup.ps1") -SkipWorker
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

    $branch = "not using Git"
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $detectedBranch = (& git branch --show-current 2>$null).Trim()
        if ($detectedBranch) {
            $branch = $detectedBranch
        }
    }

    Write-Host "Preparing the place from your current branch..." -ForegroundColor Cyan
    Write-Host "  Branch:  $branch"
    Write-Host "  Project: $projectName"
    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
    & rojo build default.project.json --output $placeFile
    if ($LASTEXITCODE -ne 0) {
        throw "Rojo could not build $projectName. Run 3_CHECK.cmd for details."
    }
    Stop-StaleRojoServer

    if (-not $NoStudio) {
        $studio = Find-RobloxStudio
        if ($null -eq $studio) {
            Write-Host "Roblox Studio is not installed. Install it, then run 2_START.cmd again:" -ForegroundColor Red
            Write-Host "https://create.roblox.com/docs/studio/setup"
            exit 1
        }
        Write-Host "Opening $projectName in a new Roblox Studio window..." -ForegroundColor Cyan
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
