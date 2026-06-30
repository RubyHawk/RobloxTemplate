# Connected UI restyle: Fredoka/Nunito + chunky buttons — 2026-06-30

## Why

Feedback: the connected template UI read as too soft/corporate next to typical
bright, icon-driven Roblox simulator UIs. Comparing against real reference
screenshots, the thick dark outlines, white-text-with-dark-stroke treatment,
fully-saturated per-screen colors, and real icon art (from
`TemplateConfig.icons`) were already authored in `TemplateUI.model.json` —
they just didn't survive translation into a flat HTML mockup. The two
genuine gaps were the font (`GothamSSm`, a clean corporate sans) and buttons
with no press-depth.

## Sources checked

- Roblox `Font` enum reference: <https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/Font.yaml>
- Roblox `Font` datatype reference (family paths, `fromEnum` table): <https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/Font.yaml>
- Rojo's own property-encoding test fixture, used to get the `ColorSequence` JSON shape right before touching the real file: <https://raw.githubusercontent.com/rojo-rbx/rojo/master/plugin/rbx_dom_lua/allValues.json>

## What changed

- `Theme.font`/`Theme.fontBold` now point at `Nunito` (ExtraBold) and
  `FredokaOne` (Regular — it only ships one practical weight) instead of
  `GothamSSm`. These two tokens aren't read anywhere at runtime today (every
  label's `FontFace` is a baked Studio property, not assigned by the screen
  binder), so the real fix is in `TemplateUI.model.json` itself.
- `scripts/restyle_ui_fonts_and_buttons.py` (idempotent, re-run after adding
  new buttons/text) walked all 2323 authored instances and:
  - Remapped every `FontFace` from `GothamSSm`+`Heavy` (emphasis text:
    titles, button labels, nav labels — 278 instances) to `FredokaOne`, and
    `GothamSSm`+`Bold` (body/description/amount text — 405 instances) to
    `Nunito` `ExtraBold`. This was a 1:1 swap on an existing semantic split,
    not a new one.
  - Added a `UIGradient` "Sheen" child to all 106 `TextButton`s that have a
    `UICorner` (a subtle lighter-top/darker-bottom tint of each button's own
    color, for a glossy/chunky look) — safe everywhere, since `UIGradient`
    isn't a `GuiObject` and so isn't subject to layout managers.
  - Added an offset, darker-shade `<Name>Shadow` `Frame` sibling (copying
    the button's `UICorner`/`UIStroke`) behind 64 of those buttons, for the
    "candy button" press-depth look. This was **only** done where the
    button's parent has no `UIGridLayout`/`UIListLayout`/`UITableLayout`
    child — inserting an extra `GuiObject` sibling into one of those would
    have been laid out as a new grid/list cell and broken the real layout
    (the 5 nav-rail tabs, the 5 more-menu tiles, and most of the
    list-stacked screen CTAs — Claim/Search/Redeem/Settings toggles — are
    skipped for the shadow specifically; they still get the font and the
    gradient).
- Same `GothamSSm` → `FredokaOne`/`Nunito` swap applied to the two scripts
  that build their own UI at runtime outside the `TemplateUI` tree:
  `ReplicatedFirst/Loading.client.luau` (boot splash) and
  `starter/StarterExample.server.luau` (demo billboard).

## Verification

`rokit install` could not complete in this sandboxed session (its own HTTP
client failed against the egress proxy; plain `curl` to the same GitHub
hosts worked fine), so `rojo`, `lune`, `stylua`, and `wally` binaries were
downloaded directly from their GitHub release assets instead of through
rokit. With those:

- `rojo build bootstrap.project.json` succeeds — confirms the new
  `FontFace`, `UIGradient`/`ColorSequence`, and shadow-`Frame` instances are
  structurally valid, not just well-formed JSON.
- `lune run tests/run`: 81/81 assertions still pass.
- `stylua --check src tests`: clean.
- `selene` could not run — its Roblox API dump fetch failed in this sandbox
  (different host than GitHub releases, not worked around). Nothing in this
  pass touches Luau control flow beyond the two-line `Theme.luau` font swap
  and the two single-line font swaps above, all of which `stylua` and
  `rojo build` already cover.
- `places/RobloxPlayableStarter.rbxlx` (the larger Studio-saved snapshot
  used for local playtesting) was **not** regenerated — it's a manually
  saved Studio export, not a build artifact of this repo's scripts. Re-save
  it from Studio (or `rojo build` + reinsert the gallery showrooms) to pick
  up this pass.
