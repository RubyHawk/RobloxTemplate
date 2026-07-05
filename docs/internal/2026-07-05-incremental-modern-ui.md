# Incremental modern UI direction

Recorded: 2026-07-05

This pass translates the approved Roblox simulator references into an original,
editable Incremental preset rather than copying one game's artwork.

## Visual rules

- Keep the playfield open. Primary actions live in a compact icon-first dock at
  the bottom; supporting currencies sit at the right on desktop and become a
  horizontal top tray on compact screens.
- Use bright, category-specific icon colors against near-black panels. Labels
  are short, outlined, and secondary to the icon silhouette.
- Inventory is a wide dark modal with an offset orange title banner, a large
  close target, independent illustrated category tabs, and a dense icon grid.
- Boost information stays collapsed during play. Its authored details panel
  uses a clear left-label/right-value breakdown for friends, Premium, potion,
  and the resulting multiplier.
- Phone layouts keep touch targets at least 44 Roblox offset units, move the
  inventory categories to a horizontal row, and reduce the item grid from four
  columns to two or three based on actual available width.
- Upgrade/skill-tree screens should use compact hexagonal state nodes when that
  feature is added: bright owned, accented available, dark locked. Do not use
  oversized labels that obscure the graph.

## Implementation boundaries

- Every visual node added by this pass is a permanent object in
  `src/ui/presets/incremental/TemplateUI.model.json`.
- Runtime Luau only binds values, click behavior, visibility, selected states,
  and responsive layout properties. It creates, clones, and destroys no GUI.
- The RPG preset is untouched and remains a physically independent tree.
- The deterministic transformer is
  `scripts/restyle_incremental_modern.py`; rerunning it edits only Incremental.

## Figma workflow

Figma Starter's MCP quota blocked remote canvas edits during this pass. The
editable draft target is <https://www.figma.com/design/f5CVGUAVDYZ4rZEjgFdkar>.
Until the quota resets, use the local Roblox UI Bridge from `START_HERE.cmd` and
import:

`X:\RobloxTemplate\src\ui\presets\incremental\TemplateUI.model.json`

The local bridge preserves the physical authored tree and does not require a
Figma API token.
