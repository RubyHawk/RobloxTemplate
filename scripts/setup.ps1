[CmdletBinding()]
param(
    [switch]$SkipWorker
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $root "build"
$placeFile = Join-Path $buildDirectory "RobloxTemplate.rbxlx"
$tools = @(
    "rojo-rbx/rojo",
    "UpliftGames/wally",
    "Kampfkarren/selene",
    "JohnnyMorganz/StyLua",
    "lune-org/lune"
)

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked([string]$Name, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

function Test-RobloxStudioInstalled {
    $localVersions = Join-Path $env:LOCALAPPDATA "Roblox\Versions"
    return (Test-Path $localVersions -PathType Container) -and
        [bool](Get-ChildItem -LiteralPath $localVersions -Filter "RobloxStudioBeta.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
}

Push-Location $root
try {
    Write-Host "Roblox Template - beginner setup" -ForegroundColor Yellow
    Write-Host "This installs only project tools and the official Rojo Studio plugin."

    if (-not (Get-Command rokit -ErrorAction SilentlyContinue)) {
        Write-Step "Installing Rokit from the official rojo-rbx GitHub repository"
        $installer = Invoke-RestMethod "https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1"
        & ([scriptblock]::Create($installer))
        $env:PATH = "$env:USERPROFILE\.rokit\bin;$env:PATH"
    }

    if (-not (Get-Command rokit -ErrorAction SilentlyContinue)) {
        throw "Rokit could not be found after installation. Close this window, reopen it, and run 1_SETUP.cmd again."
    }

    Write-Step "Trusting the five pinned tool publishers"
    Invoke-Checked "Rokit trust" { rokit trust @tools }

    Write-Step "Installing the exact project tool versions"
    Invoke-Checked "Rokit install" { rokit install }

    Write-Step "Preparing Roblox packages"
    Invoke-Checked "Wally install" { wally install }

    Write-Step "Installing the matching Rojo plugin into Roblox Studio"
    Invoke-Checked "Rojo plugin install" { rojo plugin install }

    if (-not $SkipWorker) {
        if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
            Write-Step "Preparing the optional notification worker"
            try {
                Invoke-Checked "Worker install" { npm ci --prefix worker }
            }
            catch {
                Write-Host "[SKIP] The optional notification worker could not be prepared: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "The Roblox template itself is ready to use."
            }
        }
        else {
            Write-Host "[SKIP] Node.js is not installed. The Roblox template still works; only the optional offline notification worker is unavailable." -ForegroundColor Yellow
        }
    }

    Write-Step "Building a place file that Roblox Studio can open"
    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
    Invoke-Checked "Rojo build" { rojo build default.project.json --output $placeFile }

    if (Test-RobloxStudioInstalled) {
        Write-Host "[OK] Roblox Studio found" -ForegroundColor Green
    }
    else {
        Write-Host "[ACTION NEEDED] Roblox Studio was not found. Install it from https://create.roblox.com/docs/studio/setup" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "SETUP COMPLETE" -ForegroundColor Green
    Write-Host "Next: close this window and double-click 2_START.cmd."
}
catch {
    Write-Host ""
    Write-Host "SETUP STOPPED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Run 3_CHECK.cmd for a clearer diagnosis."
    exit 1
}
finally {
    Pop-Location
}
