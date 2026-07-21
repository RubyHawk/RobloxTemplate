$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "rojo-plugin-state.ps1")

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = Join-Path $temporaryRoot ("rojo-plugin-state-" + [guid]::NewGuid().ToString("N"))
$testRoot = [System.IO.Path]::GetFullPath($testRoot)
if (-not $testRoot.StartsWith($temporaryRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Rojo plugin state test directory escaped the system temporary directory."
}

New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $state = Get-RojoStudioPluginState -RobloxRoot $testRoot
    Assert-True (-not $state.HasAny) "An empty Roblox directory must not report a plugin."

    $cloudRoot = Join-Path $testRoot "12345\InstalledPlugins\13916111004"
    New-Item -ItemType Directory -Path $cloudRoot -Force | Out-Null
    $state = Get-RojoStudioPluginState -RobloxRoot $testRoot
    Assert-True (-not $state.HasCreatorStore) "An empty Creator Store cache must not report a plugin."

    $managedPath = Join-Path $testRoot "Plugins\RojoManagedPlugin.rbxm"
    New-Item -ItemType Directory -Path (Split-Path -Parent $managedPath) -Force | Out-Null
    [System.IO.File]::WriteAllBytes($managedPath, [byte[]]@(1))
    $state = Get-RojoStudioPluginState -RobloxRoot $testRoot
    Assert-True ($state.HasManaged -and -not $state.HasCreatorStore -and -not $state.HasConflict) "A sole managed plugin must be recognized."

    $cloudPayload = Join-Path $cloudRoot "98765\Plugin.rbxm"
    New-Item -ItemType Directory -Path (Split-Path -Parent $cloudPayload) -Force | Out-Null
    [System.IO.File]::WriteAllBytes($cloudPayload, [byte[]]@(1))
    $state = Get-RojoStudioPluginState -RobloxRoot $testRoot
    Assert-True ($state.HasCreatorStore -and $state.HasConflict) "Two usable plugin copies must report a conflict."

    Remove-Item -LiteralPath $managedPath -Force
    $state = Get-RojoStudioPluginState -RobloxRoot $testRoot
    Assert-True ($state.HasCreatorStore -and -not $state.HasManaged -and -not $state.HasConflict) "A sole Creator Store plugin must be recognized."

    Write-Host "Rojo Studio plugin detector passed all install-state checks."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
