$ErrorActionPreference = "Stop"

function Invoke-Checked([string]$Name, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

Invoke-Checked "StyLua" { stylua --check src tests }
Invoke-Checked "Selene" { selene src tests }
Invoke-Checked "Wally" { wally install }
Invoke-Checked "Rojo build" { rojo build bootstrap.project.json --output RobloxTemplate.rbxlx }
Invoke-Checked "Luau tests" { lune run tests/run }
Invoke-Checked "Worker type check" { npm --prefix worker run typecheck }
Invoke-Checked "Worker tests" { npm --prefix worker test }
Invoke-Checked "Skill validation" { python scripts\validate_skill.py ".agents\skills\roblox-template" }

Write-Host "All template checks passed."
