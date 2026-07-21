[CmdletBinding()]
param(
    [switch]$NoStudio,
    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$placeDirectory = Join-Path $root "places"
$project = Get-Content -LiteralPath (Join-Path $root "default.project.json") -Raw | ConvertFrom-Json
$projectName = [string]$project.name
$safeProjectName = $projectName -replace '[^A-Za-z0-9._-]', '_'
$placeFile = Join-Path $placeDirectory "$safeProjectName.rbxlx"
$bootstrapProject = Join-Path $root "bootstrap.project.json"
. (Join-Path $PSScriptRoot "rojo-plugin-state.ps1")

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
    if ($listeners.Count -eq 0) {
        return
    }

    $processIds = @($listeners | Select-Object -ExpandProperty OwningProcess | Sort-Object -Unique)
    foreach ($processId in $processIds) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if (-not $process) {
            continue
        }
        if ($process.ProcessName -ne "rojo") {
            throw "Port 34872 is being used by $($process.ProcessName). Close that program, then run 2_START.cmd again."
        }

        Write-Host "Closing an older Rojo session so it cannot load the previous mode..." -ForegroundColor Yellow
        Stop-Process -Id $processId -Force
        $process.WaitForExit(3000) | Out-Null
    }
}

function Update-ProjectPaths($Node) {
    if ($null -eq $Node -or $Node -is [string] -or $Node -is [System.ValueType]) {
        return
    }
    if ($Node -is [System.Collections.IEnumerable]) {
        foreach ($item in $Node) {
            Update-ProjectPaths $item
        }
        return
    }
    foreach ($property in @($Node.PSObject.Properties)) {
        if ($property.Name -eq '$path' -and $property.Value -is [string]) {
            $property.Value = "../../" + ($property.Value -replace '\\', '/')
        }
        else {
            Update-ProjectPaths $property.Value
        }
    }
}

Push-Location $root
try {
    $configPath = Join-Path $root "experiences.config.json"
    $experiences = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($requiredEntry in @("template", "playerTest")) {
        if (-not ($experiences.PSObject.Properties.Name -contains $requiredEntry)) {
            throw "experiences.config.json must define `"$requiredEntry`" with name, universeId, and placeId."
        }
    }
    $template = $experiences.template
    $templateUniverseId = [long]$template.universeId
    $templatePlaceId = [long]$template.placeId
    $cloudConfigured = ($templateUniverseId -gt 0 -and $templatePlaceId -gt 0)

    if (-not $SmokeTest) {
        $rojoPluginState = Get-RojoStudioPluginState
        if ($rojoPluginState.HasConflict) {
            throw (Get-RojoStudioPluginConflictMessage)
        }
        if (-not (Get-Command rojo -ErrorAction SilentlyContinue) -or -not $rojoPluginState.HasAny) {
            Write-Host "The template needs its first-time setup. Running it now..." -ForegroundColor Yellow
            & (Join-Path $PSScriptRoot "setup.ps1") -SkipWorker
            if ($LASTEXITCODE -ne 0) {
                exit $LASTEXITCODE
            }
        }
    }

    Write-Host "Opening the template workbench..." -ForegroundColor Cyan
    Write-Host "  Mode:    Template workbench (mock data only)"
    Write-Host "  Project: $projectName"

    if ($cloudConfigured) {
        $generatedDirectory = Join-Path $root "build/template"
        New-Item -ItemType Directory -Path $generatedDirectory -Force | Out-Null
        $serveProject = Get-Content -LiteralPath (Join-Path $root "default.project.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        $serveProject.name = "TemplateWorkbench"
        Update-ProjectPaths $serveProject.tree
        $serveProject | Add-Member -MemberType NoteProperty -Name servePlaceIds -Value @($templatePlaceId) -Force
        $serveProjectPath = Join-Path $generatedDirectory "TemplateWorkbench.project.json"
        [System.IO.File]::WriteAllText(
            $serveProjectPath,
            ($serveProject | ConvertTo-Json -Depth 12),
            [System.Text.UTF8Encoding]::new($false)
        )

        $written = Get-Content -LiteralPath $serveProjectPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (@($written.servePlaceIds) -notcontains $templatePlaceId) {
            throw "The generated template project is not restricted to template place $templatePlaceId."
        }

        if ($SmokeTest) {
            Write-Host "Template experience verified: $($template.name) | universe $templateUniverseId | place $templatePlaceId"
            exit 0
        }

        Stop-StaleRojoServer
        if (-not $NoStudio) {
            $studio = Find-RobloxStudio
            if ($null -eq $studio) {
                Write-Host "Roblox Studio is not installed. Install it, then run 2_START.cmd again:" -ForegroundColor Red
                Write-Host "https://create.roblox.com/docs/studio/setup"
                exit 1
            }
            Write-Host "Opening the existing template experience. No new experience is created." -ForegroundColor Green
            Start-Process -FilePath $studio.FullName -ArgumentList @(
                "-task", "EditPlace",
                "-placeId", [string]$templatePlaceId,
                "-universeId", [string]$templateUniverseId
            )
        }

        Write-Host ""
        Write-Host "ROJO IS READY" -ForegroundColor Green
        Write-Host "In Studio:"
        Write-Host "  1. Open the Plugins tab."
        Write-Host "  2. Click Rojo, then Connect."
        Write-Host "  3. Edit UI objects under StarterGui."
        Write-Host "  4. Press Play to test connected systems."
        Write-Host "Use File > Publish to Roblox to save workbench changes to this same experience; never use Publish As." -ForegroundColor Yellow
        Write-Host "If Studio opens an empty place, publish the local workbench into it once: docs/SETUP.md > 'Seed the template experience'." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Keep this window open while editing. Press Ctrl+C here when finished." -ForegroundColor Yellow
        rojo serve $serveProjectPath
        exit $LASTEXITCODE
    }

    Write-Host "No permanent template experience is linked yet." -ForegroundColor Yellow
    Write-Host "  experiences.config.json > template.universeId/placeId are 0."
    Write-Host "  Using the local workbench file instead: $placeFile"
    Write-Host "  To link your permanent template experience, follow docs/SETUP.md > 'Link your two permanent experiences'."
    if ($SmokeTest) {
        Write-Host "Template experience not configured; local-file workbench mode."
        exit 0
    }

    New-Item -ItemType Directory -Path $placeDirectory -Force | Out-Null
    if (-not (Test-Path $placeFile -PathType Leaf)) {
        Write-Host "Creating the editable workbench for the first time..." -ForegroundColor Yellow
        & rojo build $bootstrapProject --output $placeFile
        if ($LASTEXITCODE -ne 0) {
            throw "Rojo could not create $projectName. Run 3_CHECK.cmd for details."
        }
    }
    else {
        Write-Host "  Saved UI: $placeFile" -ForegroundColor DarkGray
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
    Write-Host "  3. Edit UI objects under StarterGui, then press Ctrl+S."
    Write-Host "  4. Press Play to test connected systems."
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
