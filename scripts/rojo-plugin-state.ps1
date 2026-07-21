function Get-RojoStudioPluginState {
    param(
        [string]$RobloxRoot
    )

    $managedPath = $null
    $creatorStorePaths = @()

    if ([string]::IsNullOrWhiteSpace($RobloxRoot) -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $RobloxRoot = Join-Path $env:LOCALAPPDATA "Roblox"
    }
    if (-not [string]::IsNullOrWhiteSpace($RobloxRoot)) {
        $managedPath = Join-Path $RobloxRoot "Plugins\RojoManagedPlugin.rbxm"
        if (Test-Path -LiteralPath $RobloxRoot -PathType Container) {
            foreach ($accountDirectory in @(Get-ChildItem -LiteralPath $RobloxRoot -Directory -ErrorAction SilentlyContinue)) {
                $candidate = Join-Path $accountDirectory.FullName "InstalledPlugins\13916111004"
                if (Test-Path -LiteralPath $candidate -PathType Container) {
                    $pluginPayload = Get-ChildItem -LiteralPath $candidate -Filter "Plugin.rbxm" -File -Recurse -ErrorAction SilentlyContinue |
                        Where-Object Length -gt 0 |
                        Select-Object -First 1
                    if ($null -ne $pluginPayload) {
                        $creatorStorePaths += $pluginPayload.FullName
                    }
                }
            }
        }
    }

    $hasManaged = $null -ne $managedPath -and (Test-Path -LiteralPath $managedPath -PathType Leaf)
    $hasCreatorStore = $creatorStorePaths.Count -gt 0
    return [pscustomobject]@{
        ManagedPath = $managedPath
        CreatorStorePaths = @($creatorStorePaths)
        HasManaged = $hasManaged
        HasCreatorStore = $hasCreatorStore
        HasAny = $hasManaged -or $hasCreatorStore
        HasConflict = $hasManaged -and $hasCreatorStore
    }
}

function Get-RojoStudioPluginConflictMessage {
    return "Two Rojo Studio plugins are installed (the local managed copy and Creator Store asset 13916111004). Keep exactly one before opening Studio; duplicate plugins connect and sync twice."
}
