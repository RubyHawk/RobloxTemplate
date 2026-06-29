# Roblox Template Working Agreements

- Read `.agents/skills/roblox-template/SKILL.md` before changing template systems or UI.
- Write Luau in strict mode and keep the server authoritative for currency, inventory, rewards, purchases, profiles, and verification.
- Validate every client payload by type, value, permission, and rate limit.
- Put map-specific values in `TemplateConfig`; never hardcode product, group, audio, notification, or experience IDs in services.
- Preserve profile compatibility with explicit schema migrations. Never silently discard unknown saved data.
- Before work on Roblox chat, policy, monetization, notifications, privacy, or platform APIs, read the newest official topic documentation and record the date and links under `docs/internal/`.
- Keep every visual UI structure in editable StarterGui instances. Runtime code may bind behavior, replace text/images, and show/hide pre-authored data slots, but must never create, clone, or destroy GuiObjects.
- Keep connected UI token-styled, safe-area aware, touch friendly, and usable in phone portrait and landscape.
- Run StyLua, Selene, Rojo build, Luau specs, worker tests, and skill validation before committing.
- Do not add direct Discord links, paid random-item mechanics, secrets, or live external integrations to the repository.
