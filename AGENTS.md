# Roblox Template Working Agreements

- Read `.agents/skills/roblox-template/SKILL.md` before changing template systems or UI.
- Write Luau in strict mode and keep the server authoritative for currency, inventory, rewards, purchases, profiles, and verification.
- Validate every client payload by type, value, permission, and rate limit.
- Put map-specific values in `TemplateConfig`; never hardcode product, group, audio, notification, or experience IDs in services.
- Preserve profile compatibility with explicit schema migrations. Never silently discard unknown saved data.
- Keep UI factory-driven, token-styled, safe-area aware, touch friendly, and usable in phone portrait and landscape.
- Run StyLua, Selene, Rojo build, Luau specs, worker tests, and skill validation before committing.
- Do not add direct Discord links, paid random-item mechanics, secrets, or live external integrations to the repository.
