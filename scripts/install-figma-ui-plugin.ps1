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
$workspacePath = Join-Path $root "figma\workspaces\rng-defender.json"
$runtimeModulePath = Join-Path $root "src\plugins\FigmaUiBridge\Runtime.generated.luau"
$sessionPath = Join-Path $buildDirectory "figma-ui-bridge-session.json"

function Invoke-Checked([string]$Name, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

function Get-DownloadsFolder {
    try {
        $shell = New-Object -ComObject Shell.Application
        $downloads = $shell.NameSpace("shell:Downloads")
        if ($downloads -and $downloads.Self) {
            $resolved = [string]$downloads.Self.Path
            if ($resolved -and (Test-Path -LiteralPath $resolved -PathType Container)) {
                return $resolved
            }
        }
    }
    catch { }
    if ($env:USERPROFILE) {
        $fallback = Join-Path $env:USERPROFILE "Downloads"
        if (Test-Path -LiteralPath $fallback -PathType Container) {
            return $fallback
        }
    }
    throw "The Windows Downloads folder could not be found."
}

Push-Location $root
try {
    Write-Host "Private Figma UI delivery plugin installer" -ForegroundColor Yellow
    Write-Host "The plugin calls the loopback-only repository helper started by 8_RNG_DEFENDER.cmd."

    if (Get-Process -Name "RobloxStudioBeta" -ErrorAction SilentlyContinue) {
        throw "Roblox Studio is open. Save and close every Studio window before replacing the local plugin."
    }
    if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
        throw "Rojo is not installed. Double-click 1_SETUP.cmd first."
    }

    $workspace = Get-Content -LiteralPath $workspacePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ($workspace.PSObject.Properties.Name -contains "studioBridge")) {
        throw "The RNG Defender Figma workspace does not define studioBridge."
    }
    $bridgeHost = [string]$workspace.studioBridge.host
    $bridgePort = [int]$workspace.studioBridge.port
    if ($bridgeHost -notin @("127.0.0.1", "localhost")) {
        throw "The Figma Studio bridge must bind only to localhost."
    }
    if ($bridgePort -le 1024 -or $bridgePort -gt 65535) {
        throw "The Figma Studio bridge port must be between 1025 and 65535."
    }

    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
    $sessionToken = [guid]::NewGuid().ToString("N")
    $bridgeUrl = "http://${bridgeHost}:$bridgePort"
    Invoke-Checked "Figma UI plugin runtime generation" {
        node scripts\generate-figma-plugin-runtime.mjs `
            --workspace $workspacePath `
            --output $runtimeModulePath `
            --token $sessionToken
    }

    $session = [ordered]@{
        format = "figma-ui-bridge-session-v1"
        repository = $root
        workspace = [string]$workspace.id
        host = $bridgeHost
        port = $bridgePort
        token = $sessionToken
        downloads = (Get-DownloadsFolder)
        manifest = (Join-Path $buildDirectory "FigmaUiBridgeManifest.json")
    }
    $session | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sessionPath -Encoding UTF8

    Invoke-Checked "Figma Studio manifest generation" {
        node scripts\generate-figma-studio-manifest.mjs --manifest-only
    }

    Invoke-Checked "Figma UI plugin build" {
        rojo build $projectFile --output $pluginOutput
    }

    New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null
    Copy-Item -LiteralPath $pluginOutput -Destination $pluginDestination -Force

    $installed = Get-Item -LiteralPath $pluginDestination
    Write-Host "[OK] Installed: $($installed.FullName)" -ForegroundColor Green
    Write-Host "[OK] The toolbar button is Plugins > Figma UI." -ForegroundColor Green
    Write-Host "[OK] Prepared one-click bridge session: $bridgeUrl" -ForegroundColor Green
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
