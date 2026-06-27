$ErrorActionPreference = "Stop"

stylua --check src tests
selene src tests
wally install
rojo build default.project.json --output RobloxTemplate.rbxlx
lune run tests/run
npm --prefix worker run typecheck
npm --prefix worker test
python scripts\validate_skill.py ".agents\skills\roblox-template"

Write-Host "All template checks passed."
