[CmdletBinding()]
param(
    [switch]$Full
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$failures = 0
$warnings = 0

function Write-Pass([string]$Message) {
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-Fail([string]$Message) {
    $script:failures += 1
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Write-Warning([string]$Message) {
    $script:warnings += 1
    Write-Host "[NOTE] $Message" -ForegroundColor Yellow
}

function Test-Tool([string]$Name, [string]$ExpectedText) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        Write-Fail "$Name is missing. Run 1_SETUP.cmd."
        return $false
    }
    $version = (& $Name --version 2>&1 | Select-Object -First 1).ToString()
    if ($version -notmatch [regex]::Escape($ExpectedText)) {
        Write-Warning "$Name reports '$version'; expected $ExpectedText. Run 1_SETUP.cmd to restore the pinned version."
    }
    else {
        Write-Pass "$version"
    }
    return $true
}

Push-Location $root
try {
    Write-Host "Roblox Template Doctor" -ForegroundColor Cyan
    Write-Host "Checking the things needed to edit and run the template..."
    Write-Host ""

    $requiredToolsReady = $true
    $requiredTools = @(
        @("rokit", "1.2.0"),
        @("rojo", "7.7.0"),
        @("wally", "0.3.2"),
        @("selene", "0.31.0"),
        @("stylua", "2.5.2"),
        @("lune", "0.10.4")
    )
    foreach ($tool in $requiredTools) {
        if (-not (Test-Tool $tool[0] $tool[1])) {
            $requiredToolsReady = $false
        }
    }

    $plugin = Join-Path $env:LOCALAPPDATA "Roblox\Plugins\RojoManagedPlugin.rbxm"
    if (Test-Path $plugin -PathType Leaf) {
        Write-Pass "Rojo Studio plugin is installed"
    }
    else {
        Write-Fail "Rojo Studio plugin is missing. Run 1_SETUP.cmd."
    }

    $studio = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "Roblox\Versions") -Filter "RobloxStudioBeta.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($studio) {
        Write-Pass "Roblox Studio is installed"
    }
    else {
        Write-Fail "Roblox Studio is missing. Install it from https://create.roblox.com/docs/studio/setup"
    }

    Write-Host ""
    Write-Host "Project checks" -ForegroundColor Cyan
    if ($requiredToolsReady) {
        & stylua --check src tests
        if ($LASTEXITCODE -eq 0) { Write-Pass "Luau formatting" } else { Write-Fail "Luau formatting failed" }
        & selene src tests
        if ($LASTEXITCODE -eq 0) { Write-Pass "Luau linting" } else { Write-Fail "Luau linting failed" }

        New-Item -ItemType Directory -Path (Join-Path $root "build") -Force | Out-Null
        & rojo build bootstrap.project.json --output (Join-Path $root "build\DoctorTest.rbxlx")
        if ($LASTEXITCODE -eq 0) { Write-Pass "Rojo place build" } else { Write-Fail "Rojo could not build the place" }

        & lune run tests/run
        if ($LASTEXITCODE -eq 0) { Write-Pass "Pure Luau tests" } else { Write-Fail "Pure Luau tests failed" }
    }
    else {
        Write-Warning "Project checks were skipped until 1_SETUP.cmd installs the missing tools."
    }

    if ($Full) {
        if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
            if (-not (Test-Path "worker\node_modules" -PathType Container)) {
                & npm ci --prefix worker
            }
            & npm --prefix worker run typecheck
            if ($LASTEXITCODE -eq 0) { Write-Pass "Optional worker type check" } else { Write-Fail "Worker type check failed" }
            & npm --prefix worker test
            if ($LASTEXITCODE -eq 0) { Write-Pass "Optional worker tests" } else { Write-Fail "Worker tests failed" }
        }
        else {
            Write-Warning "Node.js is missing, so the optional notification worker was skipped."
        }
        if (Get-Command python -ErrorAction SilentlyContinue) {
            & python scripts\validate_skill.py ".agents\skills\roblox-template"
            if ($LASTEXITCODE -eq 0) { Write-Pass "Shared AI skill" } else { Write-Fail "Shared AI skill validation failed" }
        }
        else {
            Write-Warning "Python is missing, so optional AI skill validation was skipped."
        }
    }

    Write-Host ""
    if ($failures -eq 0) {
        Write-Host "EVERY REQUIRED CHECK PASSED" -ForegroundColor Green
        if ($warnings -gt 0) {
            Write-Host "$warnings optional note(s) are shown above."
        }
        Write-Host "You can use START_HERE.cmd now."
        exit 0
    }

    Write-Host "$failures required check(s) failed. Follow the red messages, then run this again." -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}
