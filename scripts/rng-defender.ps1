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
$uiAssetManifestPath = Join-Path $root "assets\icons\icon-manifest.json"
$figmaBridgeScriptPath = Join-Path $root "scripts\figma-studio-bridge-server.mjs"
$figmaBridgeSessionPath = Join-Path $root "build\figma-ui-bridge-session.json"
$figmaBridgePidPath = Join-Path $root "build\figma-ui-bridge-server.pid"
$figmaBridgeProcess = $null
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

function Stop-StaleFigmaUiBridge {
    if (-not (Test-Path -LiteralPath $figmaBridgePidPath -PathType Leaf)) {
        return
    }
    $rawPid = (Get-Content -LiteralPath $figmaBridgePidPath -Raw).Trim()
    if ($rawPid -notmatch '^\d+$') {
        throw "The local Figma UI bridge PID file is invalid: $figmaBridgePidPath"
    }
    $processId = [int]$rawPid
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        Remove-Item -LiteralPath $figmaBridgePidPath -Force
        return
    }
    $processDetails = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
    $commandLine = if ($processDetails) { [string]$processDetails.CommandLine } else { "" }
    if ($process.ProcessName -ne "node" -or $commandLine -notlike "*figma-studio-bridge-server.mjs*") {
        throw "The saved Figma UI bridge PID belongs to another process. Close PID $processId manually, then retry."
    }
    Write-Host "Closing the previous local Figma UI bridge..." -ForegroundColor Yellow
    Stop-Process -Id $processId -Force
    $process.WaitForExit(3000) | Out-Null
    Remove-Item -LiteralPath $figmaBridgePidPath -Force -ErrorAction SilentlyContinue
}

function Start-FigmaUiBridge {
    if (-not (Test-Path -LiteralPath $figmaBridgeSessionPath -PathType Leaf)) {
        throw "The Figma UI bridge session is missing. Re-run the plugin installer."
    }
    if (-not (Test-Path -LiteralPath $figmaBridgeScriptPath -PathType Leaf)) {
        throw "The Figma UI bridge helper is missing: $figmaBridgeScriptPath"
    }
    $session = Get-Content -LiteralPath $figmaBridgeSessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $bridgeUrl = "http://$($session.host):$($session.port)"
    $node = (Get-Command node -ErrorAction Stop).Source
    $stdoutPath = Join-Path $root "build\figma-ui-bridge.stdout.log"
    $stderrPath = Join-Path $root "build\figma-ui-bridge.stderr.log"
    $process = Start-Process -FilePath $node -ArgumentList @(
        "`"$figmaBridgeScriptPath`"",
        "--session",
        "`"$figmaBridgeSessionPath`""
    ) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru

    $headers = @{ "x-figma-ui-token" = [string]$session.token }
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($process.HasExited) {
            $details = if (Test-Path -LiteralPath $stderrPath) {
                (Get-Content -LiteralPath $stderrPath -Raw).Trim()
            }
            else {
                "no error log was written"
            }
            throw "The Figma UI bridge stopped during startup: $details"
        }
        try {
            $response = Invoke-RestMethod -Uri "$bridgeUrl/health" -Headers $headers -Method Get -TimeoutSec 1
            if ($response.ok) {
                $ready = $true
                break
            }
        }
        catch { }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "The Figma UI bridge did not become ready at $bridgeUrl."
    }
    Write-Host "Figma UI one-click import ready: $bridgeUrl" -ForegroundColor Green
    return $process
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

    if (Test-Path -LiteralPath $uiAssetManifestPath -PathType Leaf) {
        $iconManifest = Get-Content -LiteralPath $uiAssetManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $pendingUiAssets = @(
            $iconManifest.roles.PSObject.Properties | Where-Object {
                [string]$_.Value.state -eq "pending-upload"
            } | ForEach-Object {
                $_.Name
            }
        )
        if ($pendingUiAssets.Count -gt 0) {
            Write-Host ""
            Write-Host "UI ASSET STEP STILL REQUIRED" -ForegroundColor Yellow
            Write-Host "  Pending: $($pendingUiAssets -join ', ')"
            Write-Host "  Run RNG_DEFENDER_UI_ASSETS.cmd, upload the configured pending PNGs in Studio Asset Manager, and paste their IDs." -ForegroundColor Yellow
            Write-Host ""
        }
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

        Write-Host "Installing the Figma UI import and delivery plugin..." -ForegroundColor Yellow
        & (Join-Path $PSScriptRoot "install-figma-ui-plugin.ps1")
        if ($LASTEXITCODE -ne 0) {
            throw "The Figma UI delivery validator could not be installed. Save your work, close every Studio window, and try again."
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
        Stop-StaleFigmaUiBridge
        $figmaBridgeProcess = Start-FigmaUiBridge
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
    Write-Host "In Studio, connect Plugins > Rojo. After exporting in Figma, click Plugins > Figma UI > Import latest Figma." -ForegroundColor Cyan
    Write-Host "Use File > Publish to Roblox to update this same place; never use Publish As." -ForegroundColor Yellow
    Write-Host "Do not open or publish build\RNGDefenderSafePatch.rbxlx; this structural build intentionally omits unknown Team Create world data." -ForegroundColor Yellow
    Write-Host "Keep this window open while editing. Press Ctrl+C when finished."

    & rojo serve $patchProjectPath --port $rojoPort
    exit $LASTEXITCODE
}
finally {
    if ($null -ne $figmaBridgeProcess -and -not $figmaBridgeProcess.HasExited) {
        Stop-Process -Id $figmaBridgeProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $figmaBridgePidPath -PathType Leaf) {
        Remove-Item -LiteralPath $figmaBridgePidPath -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
