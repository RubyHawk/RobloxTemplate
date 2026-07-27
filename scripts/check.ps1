$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

try {

function Invoke-Checked([string]$Name, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

$requiredIcons = @(
    "bag.png", "cart.png", "close.png", "codes.png", "coin.png", "community.png", "daily.png",
    "feedback.png", "friends.png", "item.png", "leaderboard.png", "likes.png", "more.png",
    "notifications.png", "offline.png", "potion_x2.png", "potion_x3.png", "premium.png",
    "profile.png", "rewards.png", "search.png", "settings.png", "shop.png", "starter_tool.png",
    "verification.png"
)
foreach ($icon in $requiredIcons) {
    $iconPath = Join-Path $PSScriptRoot "..\assets\icons\gvesster-basic\$icon"
    if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
        throw "Required icon source is missing: $icon"
    }
}

$runtimeUiFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "..\src\client\UI") -Filter "*.luau" -File
    Get-Item -LiteralPath (Join-Path $PSScriptRoot "..\src\client\init.client.luau")
    Get-Item -LiteralPath (Join-Path $PSScriptRoot "..\src\ReplicatedFirst\Loading.client.luau")
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "..\src\starter") -Filter "*.luau" -File
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "..\src\starter-client") -Filter "*.luau" -File
    Get-Item -LiteralPath (Join-Path $PSScriptRoot "..\ui-packages\PackagePreview.client.luau")
)
$runtimeUiConstructors = @(
    $runtimeUiFiles | Select-String -Pattern 'Instance\.new|:Clone\(|:Destroy\('
)
if ($runtimeUiConstructors.Count -gt 0) {
    $locations = $runtimeUiConstructors | ForEach-Object { "$($_.Path):$($_.LineNumber)" }
    throw "Runtime UI must use authored StarterGui instances. Forbidden constructor found at: $($locations -join ', ')"
}

$uiModel = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\src\ui\TemplateUI.model.json") -Raw | ConvertFrom-Json
$uiRoot = $uiModel.Children | Where-Object Name -eq "Root"
$screens = $uiRoot.Children | Where-Object Name -eq "Screens"
$requiredScreens = @(
    "InventoryScreen", "StoreScreen", "RewardsScreen", "ProfileScreen", "SettingsScreen",
    "FeedbackScreen", "CodesScreen", "BoardsScreen", "CommunityScreen", "DynamicScreen"
)
foreach ($screenName in $requiredScreens) {
    if (-not ($screens.Children | Where-Object Name -eq $screenName)) {
        throw "Authored UI screen is missing: $screenName"
    }
}

Invoke-Checked "StyLua" { stylua --check src tests ui-packages }
Invoke-Checked "Selene" { selene src tests ui-packages }
Invoke-Checked "Stagewright repository parity" { lune run scripts/stagewright-import.luau stage-data/stagewright-project.json --check }
Invoke-Checked "Wally" { wally install }
Invoke-Checked "Rojo build" { rojo build bootstrap.project.json --output RobloxTemplate.rbxlx }
New-Item -ItemType Directory -Path build -Force | Out-Null
Invoke-Checked "Reusable UI package build" {
    rojo build ui-packages\UI_BrightSimulator.project.json --output build\UI_BrightSimulator.rbxm
}
Invoke-Checked "Incremental preset package build" {
    rojo build ui-packages\UI_Incremental.project.json --output build\UI_Incremental.rbxm
}
Invoke-Checked "RPG preset package build" {
    rojo build ui-packages\UI_RPG.project.json --output build\UI_RPG.rbxm
}
Invoke-Checked "Grid platform plugin build" {
    rojo build plugins\grid-platform-editor.project.json --output build\GridPlatformEditPlugin.rbxm
}
Invoke-Checked "Shared tower-defense safe patch build" {
    rojo build patches\rng-defender-grid-demo.project.json --output build\RNGDefenderSafePatch.rbxlx
}
Invoke-Checked "Runewright plugin build" {
    rojo build plugins\rune-config-editor.project.json --output build\RunewrightPlugin.rbxm
}
Invoke-Checked "Figma Studio plugin manifest generation" {
    node scripts\generate-figma-studio-manifest.mjs --manifest-only
}
Invoke-Checked "Figma UI delivery plugin build" {
    rojo build plugins\figma-ui-bridge.project.json --output build\FigmaUiBridge.rbxm
}
Invoke-Checked "Game Designer UI smoke test" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\game-designer.ps1 -SmokeTest
}
Invoke-Checked "Launcher app smoke test" {
    powershell -NoProfile -ExecutionPolicy Bypass -STA -File scripts\launcher.ps1 -SmokeTest
}
$recipeFiles = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "..\config-presets") -Filter "*.json" -File | Sort-Object Name)
if ($recipeFiles.Count -eq 0) {
    throw "No recipes exist under config-presets."
}
foreach ($recipeFile in $recipeFiles) {
    $recipeName = $recipeFile.BaseName
    Invoke-Checked "Configured experience build ($recipeName)" {
        powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-game-preset.ps1 -RecipePath "config-presets\$recipeName.json" -NoStudio
    }
}
Invoke-Checked "Shared icon manifest" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sync-icon-manifest.ps1 -Check
}
Invoke-Checked "Shared icon manager" {
    powershell -NoProfile -ExecutionPolicy Bypass -STA -File scripts\icon-library.ps1 -SmokeTest
}
Invoke-Checked "Permanent sandbox configuration" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sandbox.ps1 -RecipePath config-presets\incremental.json -SmokeTest
}
Invoke-Checked "Template experience configuration" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start.ps1 -SmokeTest
}
Invoke-Checked "Stagewright built artifact validation" { lune run scripts/validate-stagewright-artifact.luau }
Invoke-Checked "Stagewright shared source configuration" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\stagewright-shared.ps1 -SmokeTest
}
Invoke-Checked "RNG Defender gameplay delivery configuration" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\rng-defender.ps1 -SmokeTest
}
Invoke-Checked "Rojo Studio plugin install-state detector" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-rojo-plugin-state.ps1
}
Invoke-Checked "Figma bridge syntax" { node --check figma\roblox-ui-bridge\code.js }
Invoke-Checked "Figma Studio manifest generator syntax" { node --check scripts\generate-figma-studio-manifest.mjs }
Invoke-Checked "Figma Studio delivery manifest parity" {
    node scripts\generate-figma-studio-manifest.mjs --check
}
Invoke-Checked "Figma Studio manifest tests" {
    node tests\figma-studio-manifest.test.cjs
}
Invoke-Checked "Figma bridge world-space containers" { node tests\figma-ui-bridge.test.cjs }
Invoke-Checked "Figma RNG Defender apply route" {
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\figma-ui.ps1 `
        -PatchPath tests\fixtures\rng-defender-workspace.figma-patch.json `
        -SmokeTest
}
$presetDirectories = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "..\src\ui\presets") -Directory | Sort-Object Name)
foreach ($presetDirectory in $presetDirectories) {
    $presetName = $presetDirectory.Name
    Invoke-Checked "Figma mapping ($presetName)" {
        node scripts\figma-ui-bridge.mjs verify --model "src\ui\presets\$presetName\TemplateUI.model.json"
    }
}
Invoke-Checked "Figma patch application" {
    node scripts\figma-ui-bridge.mjs self-test --model src\ui\presets\incremental\TemplateUI.model.json
}
$figmaWorkspaces = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "..\figma\workspaces") -Filter "*.json" -File)
$figmaWorkspaceIds = @{}
foreach ($figmaWorkspaceFile in $figmaWorkspaces) {
    $figmaWorkspace = Get-Content -LiteralPath $figmaWorkspaceFile.FullName -Raw | ConvertFrom-Json
    $requiredWorkspaceFields = @("id", "name", "project", "output")
    $missingWorkspaceFields = @($requiredWorkspaceFields | Where-Object {
        -not ($figmaWorkspace.PSObject.Properties.Name -contains $_) -or
        [string]::IsNullOrWhiteSpace([string]$figmaWorkspace.$_)
    })
    if (
        $figmaWorkspace.format -ne "roblox-ui-workspace-v1" -or
        $missingWorkspaceFields.Count -gt 0 -or
        -not $figmaWorkspace.models -or
        @($figmaWorkspace.models).Count -eq 0
    ) {
        throw "Invalid Figma workspace manifest: $($figmaWorkspaceFile.FullName)"
    }
    $workspaceId = [string]$figmaWorkspace.id
    if ($figmaWorkspaceIds.ContainsKey($workspaceId)) {
        throw "Duplicate Figma workspace ID '$workspaceId': $($figmaWorkspaceIds[$workspaceId]) and $($figmaWorkspaceFile.FullName)"
    }
    $figmaWorkspaceIds[$workspaceId] = $figmaWorkspaceFile.FullName

    $repositoryPath = [System.IO.Path]::GetFullPath($root)
    $repositoryPrefix = $repositoryPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    foreach ($workspacePathField in @("project", "output")) {
        $relativeWorkspacePath = [string]$figmaWorkspace.$workspacePathField
        if ([System.IO.Path]::IsPathRooted($relativeWorkspacePath)) {
            throw "Figma workspace $workspacePathField must be repository-relative: $relativeWorkspacePath"
        }
        $resolvedWorkspacePath = [System.IO.Path]::GetFullPath((Join-Path $root $relativeWorkspacePath))
        if (-not $resolvedWorkspacePath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Figma workspace $workspacePathField leaves the repository: $relativeWorkspacePath"
        }
        if ($workspacePathField -eq "project") {
            if (-not $relativeWorkspacePath.EndsWith(".project.json", [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Figma workspace project must be a Rojo *.project.json file: $relativeWorkspacePath"
            }
            if (-not (Test-Path -LiteralPath $resolvedWorkspacePath -PathType Leaf)) {
                throw "Figma workspace Rojo project is missing: $resolvedWorkspacePath"
            }
        }
        elseif ([System.IO.Path]::GetExtension($resolvedWorkspacePath) -notin @(".rbxlx", ".rbxm")) {
            throw "Figma workspace output must be an .rbxlx or .rbxm file: $relativeWorkspacePath"
        }
    }

    $figmaWorkspaceModelRoots = @{}
    foreach ($modelDefinition in @($figmaWorkspace.models)) {
        if (
            [string]::IsNullOrWhiteSpace([string]$modelDefinition.root) -or
            [string]::IsNullOrWhiteSpace([string]$modelDefinition.path) -or
            [string]::IsNullOrWhiteSpace([string]$modelDefinition.studioPath)
        ) {
            throw "Every workspace model requires root, path, and studioPath: $($figmaWorkspaceFile.FullName)"
        }
        $modelRoot = [string]$modelDefinition.root
        if ($figmaWorkspaceModelRoots.ContainsKey($modelRoot)) {
            throw "Duplicate model root '$modelRoot' in Figma workspace '$workspaceId'."
        }
        $figmaWorkspaceModelRoots[$modelRoot] = $true
        Invoke-Checked "Figma workspace mapping ($($figmaWorkspace.id)/$($modelDefinition.root))" {
            node scripts\figma-ui-bridge.mjs verify --model $modelDefinition.path
        }
    }
}
Invoke-Checked "Luau tests" { lune run tests/run }
Invoke-Checked "Stagewright performance budgets" { lune run scripts/benchmark-stagewright.luau }
if (-not (Test-Path -LiteralPath "worker\node_modules" -PathType Container)) {
    Invoke-Checked "Worker install" { npm ci --prefix worker }
}
$nodeExecutable = (Get-Command node -ErrorAction Stop).Source
$typescriptCompiler = Join-Path $PSScriptRoot "..\worker\node_modules\typescript\bin\tsc"
Invoke-Checked "Worker type check" {
    & $nodeExecutable $typescriptCompiler -p worker\tsconfig.json
}
Invoke-Checked "Worker tests" {
    & $nodeExecutable --experimental-strip-types --test worker\test\*.test.ts
}
Invoke-Checked "Skill validation" { python scripts\validate_skill.py ".agents\skills\roblox-template" }

Write-Host "All template checks passed."
}
finally {
    Pop-Location
}
