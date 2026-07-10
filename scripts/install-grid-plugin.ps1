[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $root "plugins\grid-platform-editor.project.json"
$buildDirectory = Join-Path $root "build"
$pluginOutput = Join-Path $buildDirectory "GridPlatformEditPlugin.rbxm"
$pluginDirectory = Join-Path $env:LOCALAPPDATA "Roblox\Plugins"
$pluginDestination = Join-Path $pluginDirectory "GridPlatformEditPlugin.rbxm"

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
    Write-Host "Private Grid Platform plugin installer" -ForegroundColor Yellow
    Write-Host "This does not publish anything to Roblox."
    Write-Host "It only builds the plugin from this private repo and copies it into your local Studio Plugins folder."

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

    # Older local builds of this same tool were saved as Stagewright.rbxm and
    # broke with a Luau "Out of local registers" compile error on every Studio
    # start. Rename them out of the way (Studio only loads .rbxm/.rbxmx) so the
    # error stops, but keep the bytes as a backup instead of deleting them.
    $stalePluginNames = @("Stagewright.rbxm", "Stagewright.rbxmx")
    foreach ($staleName in $stalePluginNames) {
        $stalePath = Join-Path $pluginDirectory $staleName
        if (Test-Path -LiteralPath $stalePath -PathType Leaf) {
            $retiredPath = "$stalePath.retired-" + (Get-Date -Format "yyyyMMdd-HHmmss")
            Move-Item -LiteralPath $stalePath -Destination $retiredPath -Force
            Write-Host "[OK] Retired the broken $staleName (kept as $(Split-Path -Leaf $retiredPath))" -ForegroundColor Yellow
        }
    }

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
    Write-Host "Open Roblox Studio, then go to Plugins > Grid Platform > Grid Editor."
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
