[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $root "plugins\figma-ui-bridge.project.json"
$buildDirectory = Join-Path $root "build"
$pluginOutput = Join-Path $buildDirectory "FigmaUiBridge.rbxm"
$pluginDirectory = Join-Path $env:LOCALAPPDATA "Roblox\Plugins"
$pluginDestination = Join-Path $pluginDirectory "FigmaUiBridge.rbxm"

function Invoke-Checked([string]$Name, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

Push-Location $root
try {
    Write-Host "Private Figma UI delivery plugin installer" -ForegroundColor Yellow
    Write-Host "This plugin is read-only. It validates the stopped Studio place and never imports, edits, or publishes UI."

    if (Get-Process -Name "RobloxStudioBeta" -ErrorAction SilentlyContinue) {
        throw "Roblox Studio is open. Save and close every Studio window before replacing the local plugin."
    }
    if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
        throw "Rojo is not installed. Double-click 1_SETUP.cmd first."
    }

    Invoke-Checked "Figma Studio manifest generation" {
        node scripts\generate-figma-studio-manifest.mjs --manifest-only
    }

    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
    Invoke-Checked "Figma UI plugin build" {
        rojo build $projectFile --output $pluginOutput
    }

    New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null
    Copy-Item -LiteralPath $pluginOutput -Destination $pluginDestination -Force

    $installed = Get-Item -LiteralPath $pluginDestination
    Write-Host "[OK] Installed: $($installed.FullName)" -ForegroundColor Green
    Write-Host "[OK] The toolbar button is Plugins > Figma UI." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "FIGMA UI PLUGIN INSTALL STOPPED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}
