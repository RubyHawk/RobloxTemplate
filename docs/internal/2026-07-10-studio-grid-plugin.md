# Studio Grid Plugin Check - 2026-07-10

Official Roblox documentation checked before adding an edit-mode grid plugin:

- Studio plugins overview: https://create.roblox.com/docs/studio/plugins
- Plugin API reference: https://create.roblox.com/docs/reference/engine/classes/Plugin
- PluginMouse API reference: https://create.roblox.com/docs/reference/engine/classes/PluginMouse
- PluginToolbarButton API reference: https://create.roblox.com/docs/reference/engine/classes/PluginToolbarButton
- ChangeHistoryService API reference: https://create.roblox.com/docs/reference/engine/classes/ChangeHistoryService
- Model pivot / WorldPivot API reference: https://create.roblox.com/docs/reference/engine/classes/Model/WorldPivot

Notes:

- Edit-mode grid painting needs a Studio plugin, not regular game scripts, because the tool must run while the place is not in Play mode.
- Roblox's plugin guide shows toolbar creation through `Plugin:CreateToolbar()` / `PluginToolbar:CreateButton()` and edit operations wrapped with `ChangeHistoryService` recordings for undo and redo.
- `Plugin:CreateDockWidgetPluginGuiAsync()` is the current docked panel constructor; `CreateDockWidgetPluginGui()` is deprecated.
- `Plugin:GetMouse()` provides click access in the Studio viewport after the plugin activates.
- A model with `PrimaryPart` uses that primary part as its pivot, while `WorldPivot` is used when there is no primary part.
