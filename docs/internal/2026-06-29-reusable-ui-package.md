# 2026-06-29: reusable bright simulator UI package

## Official documentation checked

- Roblox Packages: https://create.roblox.com/docs/projects/assets/packages
- Roblox assets and cross-experience reuse: https://create.roblox.com/docs/assets
- PackageLink reference: https://create.roblox.com/docs/reference/engine/classes/PackageLink

## Decision

The first reusable visual pack is `UI_BrightSimulator`. Its local source is `src/ui/TemplateUI.model.json`, its Rojo package project is `ui-packages/UI_BrightSimulator.project.json`, and `4_BUILD_UI_PACK.cmd` exports a drag-and-drop RBXM without altering the authored source.

The package is UI-only. Template services and binders remain separate so multiple visual packages can share the same secure server-authoritative core.

Creating the cloud `PackageLink` remains a Studio action because Roblox requires choosing the permanent asset owner. Roblox does not support ownership transfers, so a team should normally select its group instead of an individual account. Package copies can auto-update, but modifying a copy disables auto-update until the changes are published or reverted.
