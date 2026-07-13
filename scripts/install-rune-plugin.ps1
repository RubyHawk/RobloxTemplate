[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $root "plugins\rune-config-editor.project.json"
$buildDirectory = Join-Path $root "build"
$pluginOutput = Join-Path $buildDirectory "Runewright.rbxm"
$pluginDirectory = Join-Path $env:LOCALAPPDATA "Roblox\Plugins"
$pluginDestination = Join-Path $pluginDirectory "Runewright.rbxm"

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

Push-Location $root
try {
    Write-Host "Private Runewright plugin installer" -ForegroundColor Yellow
    Write-Host "This does not publish anything to Roblox."
    Write-Host "It only builds the rune workbench from this private repo and copies it into your local Studio Plugins folder."

    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
        throw "Could not find $projectFile. Make sure you are running this from the repo folder."
    }

    if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
        if (Get-Command rokit -ErrorAction SilentlyContinue) {
            Write-Step "Installing pinned project tools with Rokit"
            Invoke-Checked "Rokit install" { rokit install }
        }
        else {
            throw "Rojo is not installed yet. Double-click 1_SETUP.cmd first, then run this installer again."
        }
    }

    if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
        throw "Rojo is still not available. Double-click 1_SETUP.cmd first, close this window, then try again."
    }

    Write-Step "Building the private Studio plugin"
    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
    Invoke-Checked "Rojo plugin build" {
        rojo build $projectFile --output $pluginOutput
    }

    Write-Step "Installing into your local Roblox Studio Plugins folder"
    New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null
    Copy-Item -LiteralPath $pluginOutput -Destination $pluginDestination -Force

    $installed = Get-Item -LiteralPath $pluginDestination
    Write-Host "[OK] Installed: $($installed.FullName)" -ForegroundColor Green
    Write-Host "[OK] Size: $($installed.Length) bytes"

    if (Get-Process -Name "RobloxStudioBeta" -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "[ACTION NEEDED] Roblox Studio is currently open." -ForegroundColor Yellow
        Write-Host "Close and reopen Studio so it loads the updated local plugin."
    }

    Write-Host ""
    Write-Host "DONE" -ForegroundColor Green
    Write-Host "Open Roblox Studio, then go to Plugins > Runewright > Runewright."
    Write-Host "Open a place built from this repo so the workbench can read the live rune values."
    Write-Host "Nothing was uploaded or made public."
}
catch {
    Write-Host ""
    Write-Host "INSTALL STOPPED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}
