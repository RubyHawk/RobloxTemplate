param(
    [string]$Preset,
    [string]$PatchPath
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

$requiredModels = @("TemplateUI.model.json", "TemplateLoading.model.json", "StarterSignUI.model.json")
$presetRoot = Join-Path $repo "src/ui/presets"
$available = @(Get-ChildItem -LiteralPath $presetRoot -Directory | Where-Object {
    $folder = $_.FullName
    @($requiredModels | Where-Object { -not (Test-Path -LiteralPath (Join-Path $folder $_) -PathType Leaf) }).Count -eq 0
} | Sort-Object Name)
if ($available.Count -eq 0) {
    throw "No complete UI presets were found under src/ui/presets."
}

if (-not $Preset) {
    Write-Host "Choose the UI preset to update:"
    for ($index = 0; $index -lt $available.Count; $index++) {
        Write-Host ("  {0}. {1}" -f ($index + 1), $available[$index].Name)
    }
    $choice = Read-Host "Choice"
    $Preset = if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $available.Count) {
        $available[[int]$choice - 1].Name
    }
    else {
        $available[0].Name
    }
}
if (@($available.Name) -notcontains $Preset) {
    throw "Unknown preset '$Preset'. Complete presets: $($available.Name -join ', ')"
}

if (-not $PatchPath) {
    $PatchPath = Read-Host "Drag the downloaded *.figma-patch.json here, then press Enter"
}
$PatchPath = $PatchPath.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
    throw "Patch file not found: $PatchPath"
}

$patch = Get-Content -LiteralPath $PatchPath -Raw | ConvertFrom-Json
if ($patch.format -ne "roblox-ui-bridge-v1") { throw "Unsupported Figma patch format." }
$roots = @($patch.roots)
$appliedModels = 0
foreach ($modelName in @("TemplateUI", "TemplateLoading", "StarterSignUI")) {
    if ($roots -notcontains $modelName) { continue }
    $model = Join-Path $repo "src/ui/presets/$Preset/$modelName.model.json"
    node (Join-Path $repo "scripts/figma-ui-bridge.mjs") apply --model $model --patch $PatchPath
    if ($LASTEXITCODE -ne 0) { throw "Figma patch failed validation for $modelName." }
    $appliedModels += 1
}
if ($appliedModels -eq 0) {
    throw "The patch does not contain TemplateUI, TemplateLoading, or StarterSignUI edits."
}

$recipePath = Join-Path $repo "config-presets/$Preset.json"
if (-not (Test-Path -LiteralPath $recipePath -PathType Leaf)) {
    throw "Add config-presets/$Preset.json so the rebuilt playable starter knows its currencies and features."
}
& (Join-Path $repo "scripts/build-game-preset.ps1") -RecipePath $recipePath -NoStudio
if ($LASTEXITCODE -ne 0) { throw "Preset rebuild failed." }

Write-Host ""
Write-Host "Done. Updated $appliedModels authored $Preset model(s) and rebuilt the playable export." -ForegroundColor Green
