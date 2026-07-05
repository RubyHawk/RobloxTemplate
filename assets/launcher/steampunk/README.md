# Roblox Workshop — Steampunk asset kit

These are the editable source assets for the desktop launcher. They are deliberately
flat, geometric SVGs rather than generated paintings. Every asset follows the same
palette, two-weight outline system, 45-degree highlight direction, and restrained
material treatment.

The SVG sources and exported PNGs are committed to Git. Nothing used by the launcher
is read from `build/`, Downloads, or another machine-specific folder. The approved
high-detail asset board is preserved under `detailed/`, alongside the exact crops used
by the app. The mechanically-correct lever remains a deterministic SVG and is exported
at normal and 2x resolution.

## Visual rules

- Iron: `#171715`, `#24231F`, outline `#090908`
- Brass: `#B78332`, highlight `#D7AA58`, shadow `#6D471B`
- Patina: `#397F77`, highlight `#65AAA0`
- Parchment: `#D9C49C`, ink `#30291F`
- Base outline: 4 units on a 96-unit icon canvas
- Detail outline: 2 units
- Corners are clipped or lightly rounded; no pill shapes
- Navigation symbols describe one action only; no unrelated object collages

`manifest.json` records the runtime role and export size of each source.
