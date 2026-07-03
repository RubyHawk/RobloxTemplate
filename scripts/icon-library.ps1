[CmdletBinding()]
param([switch]$SmokeTest)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $root "assets\icons\icon-manifest.json"
$selectedFolder = Join-Path $root "assets\icons\gvesster-basic"
$fullLibrary = Join-Path $root "build\icon-pack-extract\Free Icon Pack v3.1 (Basic)"

function Read-Manifest {
    return Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-Manifest($Manifest) {
    $json = $Manifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($manifestPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    & (Join-Path $PSScriptRoot "sync-icon-manifest.ps1")
    if ($LASTEXITCODE -ne 0) { throw "The icon manifest did not validate." }
}

function Choose-Role($Manifest) {
    $roles = @($Manifest.roles.PSObject.Properties.Name | Sort-Object)
    Write-Host ""
    for ($index = 0; $index -lt $roles.Count; $index++) {
        $role = $roles[$index]
        $entry = $Manifest.roles.$role
        Write-Host ("{0,2}. {1,-16} {2,-14} {3}" -f ($index + 1), $role, $entry.state, $entry.source)
    }
    $choice = Read-Host "Role number"
    $number = 0
    if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $roles.Count) {
        throw "Invalid role selection."
    }
    return $roles[$number - 1]
}

if ($SmokeTest) {
    $manifest = Read-Manifest
    & (Join-Path $PSScriptRoot "sync-icon-manifest.ps1") -Check
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "Shared icon manager loaded $(@($manifest.roles.PSObject.Properties).Count) connected roles."
    exit 0
}

while ($true) {
    Write-Host ""
    Write-Host "ROBLOX SHARED ICON LIBRARY" -ForegroundColor Cyan
    Write-Host "  1. Replace an existing UI role with another PNG"
    Write-Host "  2. Set the Roblox image ID/name after upload"
    Write-Host "  3. Disable an icon and use its UI fallback"
    Write-Host "  4. Open shared selected icons"
    Write-Host "  5. Open the full local icon pack"
    Write-Host "  6. Validate manifest and generated Luau"
    Write-Host "  7. Exit"
    $choice = Read-Host "Choice"

    if ($choice -eq "7") { break }
    if ($choice -eq "4") { Start-Process explorer.exe $selectedFolder; continue }
    if ($choice -eq "5") {
        if (-not (Test-Path -LiteralPath $fullLibrary -PathType Container)) {
            Write-Host "The full licensed pack is not available locally under build/icon-pack-extract." -ForegroundColor Yellow
        } else {
            Start-Process explorer.exe $fullLibrary
        }
        continue
    }
    if ($choice -eq "6") {
        & (Join-Path $PSScriptRoot "sync-icon-manifest.ps1") -Check
        continue
    }

    $manifest = Read-Manifest
    if ($choice -eq "1") {
        $role = Choose-Role $manifest
        $entry = $manifest.roles.$role
        $dialog = [System.Windows.Forms.OpenFileDialog]::new()
        $dialog.Title = "Choose a PNG for $role"
        $dialog.Filter = "PNG images (*.png)|*.png"
        if (Test-Path -LiteralPath $fullLibrary -PathType Container) { $dialog.InitialDirectory = $fullLibrary }
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { continue }
        $destination = Join-Path $root (([string]$entry.source) -replace '/', '\')
        Copy-Item -LiteralPath $dialog.FileName -Destination $destination -Force
        $entry.sourceSha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry.content = ""
        $entry.state = "pending-upload"
        Save-Manifest $manifest
        Write-Host "Updated $role. Commit the PNG and manifest; upload it before it can render in Roblox." -ForegroundColor Green
        continue
    }
    if ($choice -eq "2") {
        $role = Choose-Role $manifest
        $content = (Read-Host "Paste a numeric asset ID, rbxassetid://..., or rbxgameasset://Images/Name").Trim()
        $contentValid = $content -match '^\d+$' `
            -or $content -match '^rbxassetid://\d+$' `
            -or $content -match '^rbxgameasset://Images/[A-Za-z0-9_-]+$'
        if (-not $contentValid) {
            Write-Host "That is not a supported Roblox image reference. Use option 3 to disable a role." -ForegroundColor Yellow
            continue
        }
        $manifest.roles.$role.content = $content
        $manifest.roles.$role.state = if ($content.StartsWith("rbxgameasset://")) { "game-asset" } else { "uploaded" }
        Save-Manifest $manifest
        Write-Host "Saved Roblox content for $role." -ForegroundColor Green
        continue
    }
    if ($choice -eq "3") {
        $role = Choose-Role $manifest
        $manifest.roles.$role.content = ""
        $manifest.roles.$role.state = "disabled"
        Save-Manifest $manifest
        Write-Host "Disabled $role; the authored text/Roblox fallback remains available." -ForegroundColor Green
        continue
    }

    Write-Host "Choose 1-7." -ForegroundColor Yellow
}
