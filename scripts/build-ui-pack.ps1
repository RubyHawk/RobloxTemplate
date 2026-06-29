[CmdletBinding()]
param(
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "ui-packages\UI_BrightSimulator.project.json"
$outputDirectory = Join-Path $root "exports"
$outputFile = Join-Path $outputDirectory "UI_BrightSimulator.rbxm"

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

Push-Location $root
try {
    & rojo build $project --output $outputFile
    if ($LASTEXITCODE -ne 0) {
        throw "Rojo could not build the UI package. Run 1_SETUP.cmd, then try again."
    }
}
finally {
    Pop-Location
}

Write-Host "" 
Write-Host "UI PACKAGE READY" -ForegroundColor Green
Write-Host "  $outputFile"
Write-Host ""
Write-Host "Drag this file into Roblox Studio, or use Model > Advanced > Insert from File." -ForegroundColor Cyan
if (-not $NoOpen) {
    Start-Process -FilePath "explorer.exe" -ArgumentList $outputDirectory
}
