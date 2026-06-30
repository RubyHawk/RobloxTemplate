# Simulator UI visual study — 2026-06-30

## Why this pass happened

The previous connected UI was structurally editable but visually too restrained. It read as a generic purple application shell rather than a current Roblox simulator pack for a young audience.

## References reviewed

- Essential GUI Pack: https://clearlydev.com/product/essential-gui-pack/
- Zxgly Free Cartoony Roblox UI Pack: https://zxgly.itch.io/free-cartoony-roblox-ui-pack
- Anime Simulator UI Kit V2: https://gfxcomet.gumroad.com/l/anime9000
- Free Clicker Simulator UI: https://kwstudio.org/b/free-clicker-simulator
- Cartoon Simulator UI Kit: https://gfxcomet.com/product/cartoon-simulator-ui-kit
- RhosGFX Cartoony UI Pack: https://rhosgfx.itch.io/cartoony-ui-pack
- BuiltByBit Cartoony Icon Pack: https://builtbybit.com/resources/cartoony-icon-pack.99324/
- Roblox Creator Store simulator shop example: https://create.roblox.com/store/asset/110841229296644/Shop-Gui-Simulator-Tycoon-Game-Build-Kit

## Repeated visual patterns

- Saturated cyan/blue panel bodies with red, green, yellow, orange, pink, and purple feature accents.
- Thick near-black outlines around panels, controls, icons, and white display text.
- Compact floating windows instead of dashboard-sized application pages.
- Large circular icon-first navigation arranged vertically along the left edge without rectangular button containers.
- Wide illustrated store offers, compact inventory tiles, short labels, price pills, and green action buttons.
- Currency presented as a compact outlined pill with an icon and green plus button.
- Multiple example windows displayed together on a dedicated showroom canvas.

## Repository decision

`StarterGui.TemplateUI` opens in Studio as a visible WYSIWYG showroom made entirely from editable instances. At runtime, the client hides only that showroom canvas and binds the permanent connected HUD/screens already present in the same model. Runtime code must not construct, clone, or destroy GUI objects.

DataDelve Canary is treated as a DataStore inspection tool. It does not own or generate the visual interface.
