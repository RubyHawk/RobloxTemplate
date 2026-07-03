param(
    [ValidateSet("incremental", "rpg")]
    [string]$Preset,
    [string]$PatchPath
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

if (-not $Preset) {
    Write-Host "Choose the UI preset to update:"
    Write-Host "  1. Incremental"
    Write-Host "  2. RPG"
    $choice = Read-Host "Choice"
    $Preset = if ($choice -eq "2") { "rpg" } else { "incremental" }
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
    $model = Join-Path $repo "src\ui\presets\$Preset\$modelName.model.json"
    node (Join-Path $repo "scripts\figma-ui-bridge.mjs") apply --model $model --patch $PatchPath
    if ($LASTEXITCODE -ne 0) { throw "Figma patch failed validation for $modelName." }
    $appliedModels += 1
}
if ($appliedModels -eq 0) {
    throw "The patch does not contain TemplateUI, TemplateLoading, or StarterSignUI edits."
}

& (Join-Path $repo "scripts\build-game-preset.ps1") -RecipePath (Join-Path $repo "config-presets\$Preset.json") -NoStudio
if ($LASTEXITCODE -ne 0) { throw "Preset rebuild failed." }

Write-Host ""
Write-Host "Done. Updated $appliedModels authored $Preset model(s) and rebuilt the playable export." -ForegroundColor Green
