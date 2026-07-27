[CmdletBinding()]
param(
    [switch]$StatusOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $root "assets\icons\icon-manifest.json"
$assetFolder = Join-Path $root "assets\icons\gvesster-basic"
$requiredRoles = @("rollDice", "talentUpgrade")

function Read-Manifest {
    Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Show-Status($Manifest) {
    Write-Host ""
    Write-Host "RNG DEFENDER UI ASSETS" -ForegroundColor Cyan
    foreach ($role in $requiredRoles) {
        $entry = $Manifest.roles.$role
        $status = if ([string]::IsNullOrWhiteSpace([string]$entry.content)) {
            "NEEDS ROBLOX UPLOAD"
        } else {
            "READY: $($entry.content)"
        }
        Write-Host ("  {0,-16} {1,-24} {2}" -f $role, $status, $entry.source)
    }
    Write-Host ""
    Write-Host "Inventory uses the already connected 'bag' role. Only the two assets above are new." -ForegroundColor DarkGray
}

$manifest = Read-Manifest
Show-Status $manifest
if ($StatusOnly) {
    exit 0
}

$pendingRoles = @($requiredRoles | Where-Object {
    [string]::IsNullOrWhiteSpace([string]$manifest.roles.$_.content)
})
if ($pendingRoles.Count -eq 0) {
    Write-Host "All required tower-defense action icons are connected." -ForegroundColor Green
    exit 0
}

foreach ($role in $pendingRoles) {
    $source = [string]$manifest.roles.$role.source
    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $root ($source -replace '/', '\')))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Local source PNG for '$role' is missing: $sourcePath. Restore the repository asset before uploading."
    }
}

Write-Host "In Roblox Studio:" -ForegroundColor Yellow
Write-Host "  1. Open View > Asset Manager."
Write-Host "  2. Open Images and choose Bulk Import."
Write-Host "  3. Import the PNG files shown in the Explorer window."
Write-Host "  4. After moderation finishes, right-click each image and copy its asset ID."
Write-Host "  5. Return here and paste the matching numeric ID."
Write-Host ""
Start-Process explorer.exe -ArgumentList @("/select,`"$assetFolder\roll_dice.png`"")
Read-Host "Press Enter after both PNG files have been uploaded"

$updates = [ordered]@{}
foreach ($role in $pendingRoles) {
    while ($true) {
        $content = (Read-Host "Paste the Roblox asset ID for $role, or leave blank to keep it pending").Trim()
        if ($content -eq "") {
            break
        }
        if ($content -notmatch '^\d+$' -and $content -notmatch '^rbxassetid://\d+$') {
            Write-Host "Use the numeric image asset ID or rbxassetid:// followed by digits." -ForegroundColor Yellow
            continue
        }
        $updates[$role] = if ($content -match '^\d+$') {
            "rbxassetid://$content"
        } else {
            $content
        }
        break
    }
}

if ($updates.Count -gt 0) {
    $json = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    foreach ($role in $updates.Keys) {
        $escapedRole = [regex]::Escape([string]$role)
        $pattern = "(?s)(`"$escapedRole`"\s*:\s*\{[^{}]*?`"content`"\s*:\s*)`"[^`"]*`"(?<middle>\s*,\s*`"state`"\s*:\s*)`"[^`"]*`""
        $matcher = [regex]::new($pattern)
        if (-not $matcher.IsMatch($json)) {
            throw "Could not update the '$role' manifest entry safely."
        }
        $content = [string]$updates[$role]
        $json = $matcher.Replace(
            $json,
            {
                param($match)
                $match.Groups[1].Value `
                    + "`"$content`"" `
                    + $match.Groups["middle"].Value `
                    + '"uploaded"'
            },
            1
        )
    }
    [System.IO.File]::WriteAllText(
        $manifestPath,
        (($json -replace "\r?\n$", "") + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
    & (Join-Path $PSScriptRoot "sync-icon-manifest.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "The uploaded IDs were saved, but generated Luau validation failed."
    }
    Write-Host "Saved the Roblox image IDs and regenerated IconAssets.luau." -ForegroundColor Green
} else {
    Write-Host "No IDs were changed; the two icon roles remain pending." -ForegroundColor Yellow
}

Show-Status (Read-Manifest)
