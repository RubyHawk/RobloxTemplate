[CmdletBinding()]
param(
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $root "exports"
$packages = @(
    @{ Project = "ui-packages\UI_Incremental.project.json"; Output = "UI_Incremental.rbxm" },
    @{ Project = "ui-packages\UI_RPG.project.json"; Output = "UI_RPG.rbxm" }
)

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

Push-Location $root
try {
    foreach ($package in $packages) {
        $project = Join-Path $root $package.Project
        $outputFile = Join-Path $outputDirectory $package.Output
        & rojo build $project --output $outputFile
        if ($LASTEXITCODE -ne 0) {
            throw "Rojo could not build $($package.Output). Run 1_SETUP.cmd, then try again."
        }
    }
}
finally {
    Pop-Location
}

Write-Host "" 
Write-Host "SEPARATE UI PACKAGES READY" -ForegroundColor Green
foreach ($package in $packages) {
    Write-Host "  $(Join-Path $outputDirectory $package.Output)"
}
Write-Host ""
Write-Host "Drag this file into Roblox Studio, or use Model > Advanced > Insert from File." -ForegroundColor Cyan
if (-not $NoOpen) {
    Start-Process -FilePath "explorer.exe" -ArgumentList $outputDirectory
}
