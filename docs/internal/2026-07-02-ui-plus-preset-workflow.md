# UI Plus preset workflow check — 2026-07-02

## Source checked

- Roblox Creator Store listing supplied by the project owner: <https://create.roblox.com/store/asset/136052543524332/UI-Plus-Advanced-and-free-UI-Tools?pagePosition=58>

## Repository decision

UI Plus is treated only as a Studio authoring convenience. The repository does not import or execute plugin code and has no runtime dependency on the plugin.

Incremental and RPG presets use different authored model files for `TemplateUI`, loading, and starter-sign visuals. Generated experiences contain only the selected visual tree. This means moving or resizing instances with UI Plus in one generated place cannot mutate the other preset.

The shared binding contract is names only. Runtime code may update values and visibility but does not create, clone, or destroy GUI instances.
