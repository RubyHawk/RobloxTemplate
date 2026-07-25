param(
    [string]$Preset,
    [string]$PatchPath,
    [string]$Workspace,
    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot

function Get-DownloadsFolder {
    try {
        $shell = New-Object -ComObject Shell.Application
        $downloads = $shell.NameSpace("shell:Downloads")
        if ($downloads -and $downloads.Self) {
            $downloadsPath = [string]$downloads.Self.Path
            if ($downloadsPath -and (Test-Path -LiteralPath $downloadsPath -PathType Container)) {
                return $downloadsPath
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
    return $null
}

function Resolve-WorkspacePath([string]$RequestedWorkspace) {
    if ([string]::IsNullOrWhiteSpace($RequestedWorkspace)) {
        return $null
    }
    $trimmed = $RequestedWorkspace.Trim().Trim('"')
    if (Test-Path -LiteralPath $trimmed -PathType Leaf) {
        return (Resolve-Path -LiteralPath $trimmed).Path
    }
    $candidate = Join-Path $repo "figma/workspaces/$trimmed.json"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }
    throw "Unknown Figma workspace '$RequestedWorkspace'. Expected figma/workspaces/$RequestedWorkspace.json."
}

function Get-CompletePresets {
    $requiredModels = @("TemplateUI.model.json", "TemplateLoading.model.json", "StarterSignUI.model.json")
    $presetRoot = Join-Path $repo "src/ui/presets"
    return @(Get-ChildItem -LiteralPath $presetRoot -Directory | Where-Object {
        $folder = $_.FullName
        @($requiredModels | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $folder $_) -PathType Leaf)
        }).Count -eq 0
    } | Sort-Object Name)
}

function Resolve-Preset([string]$RequestedPreset) {
    $available = @(Get-CompletePresets)
    if ($available.Count -eq 0) {
        throw "No complete UI presets were found under src/ui/presets."
    }
    if (-not $RequestedPreset) {
        Write-Host "Choose the UI preset to update:"
        for ($index = 0; $index -lt $available.Count; $index++) {
            Write-Host ("  {0}. {1}" -f ($index + 1), $available[$index].Name)
        }
        while (-not $RequestedPreset) {
            $choice = Read-Host "Choice (Enter = 1)"
            if ([string]::IsNullOrWhiteSpace($choice)) {
                $RequestedPreset = $available[0].Name
            }
            elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $available.Count) {
                $RequestedPreset = $available[[int]$choice - 1].Name
            }
            else {
                Write-Host "Type a number between 1 and $($available.Count)." -ForegroundColor Yellow
            }
        }
    }
    if (@($available.Name) -notcontains $RequestedPreset) {
        throw "Unknown preset '$RequestedPreset'. Complete presets: $($available.Name -join ', ')"
    }
    return $RequestedPreset
}

if (-not $PatchPath) {
    $downloadsFolder = Get-DownloadsFolder
    $newestPatch = $null
    if ($downloadsFolder) {
        $newestPatch = Get-ChildItem -LiteralPath $downloadsFolder -Filter "*.figma-patch.json" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }
    if ($newestPatch) {
        Write-Host "Newest Figma export in Downloads: $($newestPatch.Name)"
        $answer = Read-Host "Press Enter to use it, or drag a different *.figma-patch.json here"
        $PatchPath = if ([string]::IsNullOrWhiteSpace($answer)) { $newestPatch.FullName } else { $answer }
    }
    else {
        $PatchPath = Read-Host "Drag the downloaded *.figma-patch.json here, then press Enter"
    }
}
$PatchPath = $PatchPath.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
    throw "Patch file not found: $PatchPath"
}

$patch = Get-Content -LiteralPath $PatchPath -Raw | ConvertFrom-Json
if ($patch.format -ne "roblox-ui-bridge-v1") {
    throw "Unsupported Figma patch format."
}
$roots = @($patch.roots | ForEach-Object { [string]$_ } | Select-Object -Unique)
if ($roots.Count -eq 0) {
    throw "The Figma patch contains no model roots."
}

$presetRoots = @("TemplateUI", "TemplateLoading", "StarterSignUI")
if (-not $Workspace -and $patch.PSObject.Properties.Name -contains "workspace") {
    $Workspace = [string]$patch.workspace
}
$workspacePath = Resolve-WorkspacePath $Workspace
$needsWorkspace = @($roots | Where-Object { $presetRoots -notcontains $_ }).Count -gt 0
if (-not $workspacePath -and $needsWorkspace) {
    $workspaceMatches = @()
    $workspaceFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo "figma/workspaces") -Filter "*.json" -File)
    foreach ($workspaceFile in $workspaceFiles) {
        $candidate = Get-Content -LiteralPath $workspaceFile.FullName -Raw | ConvertFrom-Json
        $candidateRoots = @($candidate.models | ForEach-Object { [string]$_.root })
        if (@($roots | Where-Object { $candidateRoots -notcontains $_ }).Count -eq 0) {
            $workspaceMatches += $workspaceFile
        }
    }
    if ($workspaceMatches.Count -eq 1) {
        $workspacePath = $workspaceMatches[0].FullName
        Write-Host "Detected Figma workspace: $($workspaceMatches[0].BaseName)" -ForegroundColor Cyan
    }
    elseif ($workspaceMatches.Count -eq 0) {
        throw "No Figma workspace maps every exported root: $($roots -join ', ')"
    }
    else {
        throw "More than one Figma workspace maps this patch. Re-run with -Workspace <id>."
    }
}

$modelMap = @{}
$workspaceData = $null
if ($workspacePath) {
    $workspaceData = Get-Content -LiteralPath $workspacePath -Raw | ConvertFrom-Json
    if ($workspaceData.format -ne "roblox-ui-workspace-v1" -or -not $workspaceData.models) {
        throw "Invalid Figma workspace manifest: $workspacePath"
    }
    if (-not $Preset -and $workspaceData.PSObject.Properties.Name -contains "preset") {
        $Preset = [string]$workspaceData.preset
    }
    foreach ($modelDefinition in @($workspaceData.models)) {
        $rootName = [string]$modelDefinition.root
        $relativePath = [string]$modelDefinition.path
        if (-not $rootName -or -not $relativePath) {
            throw "Every workspace model requires root and path."
        }
        $modelMap[$rootName] = Join-Path $repo $relativePath
    }
}
else {
    $Preset = Resolve-Preset $Preset
    foreach ($modelName in $presetRoots) {
        $modelMap[$modelName] = Join-Path $repo "src/ui/presets/$Preset/$modelName.model.json"
    }
}

if ($SmokeTest) {
    foreach ($rootName in $roots) {
        if (-not $modelMap.ContainsKey($rootName)) {
            throw "The selected Figma target does not map exported root '$rootName'."
        }
        $model = [string]$modelMap[$rootName]
        if (-not (Test-Path -LiteralPath $model -PathType Leaf)) {
            throw "Mapped Rojo UI model is missing: $model"
        }
        node (Join-Path $repo "scripts/figma-ui-bridge.mjs") verify --model $model
        if ($LASTEXITCODE -ne 0) {
            throw "Figma mapping validation failed for $rootName."
        }
    }
    $targetName = if ($workspaceData) { [string]$workspaceData.name } else { [string]$Preset }
    Write-Host "Figma UI apply route verified for $targetName ($($roots.Count) roots)." -ForegroundColor Green
    exit 0
}

foreach ($rootName in $roots) {
    if (-not $modelMap.ContainsKey($rootName)) {
        throw "The selected Figma target does not map exported root '$rootName'."
    }
    $model = [string]$modelMap[$rootName]
    if (-not (Test-Path -LiteralPath $model -PathType Leaf)) {
        throw "Mapped Rojo UI model is missing: $model"
    }
    node (Join-Path $repo "scripts/figma-ui-bridge.mjs") apply --model $model --patch $PatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Figma patch failed validation for $rootName."
    }
}

if ($workspaceData) {
    $project = Join-Path $repo ([string]$workspaceData.project)
    $output = Join-Path $repo ([string]$workspaceData.output)
    if (-not (Test-Path -LiteralPath $project -PathType Leaf)) {
        throw "Workspace Rojo project is missing: $project"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
    rojo build $project --output $output
    if ($LASTEXITCODE -ne 0) {
        throw "Workspace Rojo build failed."
    }
    if ([string]$workspaceData.id -eq "rng-defender") {
        & (Join-Path $repo "scripts/rng-defender.ps1") -SmokeTest
        if ($LASTEXITCODE -ne 0) {
            throw "RNG Defender delivery validation failed."
        }
    }
    Write-Host ""
    Write-Host "Done. Updated $($roots.Count) authored $($workspaceData.name) UI model(s) and rebuilt the safe Rojo patch." -ForegroundColor Green
}
else {
    $recipePath = Join-Path $repo "config-presets/$Preset.json"
    if (-not (Test-Path -LiteralPath $recipePath -PathType Leaf)) {
        throw "Add config-presets/$Preset.json so the rebuilt playable starter knows its currencies and features."
    }
    & (Join-Path $repo "scripts/build-game-preset.ps1") -RecipePath $recipePath -NoStudio
    if ($LASTEXITCODE -ne 0) {
        throw "Preset rebuild failed."
    }
    Write-Host ""
    Write-Host "Done. Updated $($roots.Count) authored $Preset model(s) and rebuilt the playable export." -ForegroundColor Green
}
