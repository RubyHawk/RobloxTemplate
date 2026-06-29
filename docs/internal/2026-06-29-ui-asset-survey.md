# 2026-06-29: 2025–2026 Roblox UI asset survey

## Why this review happened

The first connected HUD was technically tidy but looked like a programmer placeholder: a generic dollar badge, five text-only colored blocks, and text rows inside every screen. Before revising it again, we reviewed current Roblox asset packs, designer portfolios, and UI visible in successful experiences.

## Sources reviewed

- Zxgly's December 2025 scripted cartoony UI pack and daily-reward updates: https://zxgly.itch.io/free-cartoony-roblox-ui-pack
- RBLX Essentials' 2026 Studio-editable, tag-driven general UI kit: https://rblx-essentials.itch.io/general-ui-kit
- Ryvion Studios' August 2025 five-screen UI pack: https://builtbybit.com/resources/modern-roblox-ui-pack-5-guis.73421/
- Filwarka's January 2026 outlined Roblox icon pack: https://filwarka.itch.io/ui-asset-roblox-pack
- Current Roblox UI asset/system marketplace examples: https://kwstudio.org/collection/interactive-ui
- Roblox UI designer portfolio updated in 2025: https://devforum.roblox.com/t/ui-portfolio-mrcandydev%E2%80%99s-ui-design-portfolio-updated-2025/3435967
- Pet Simulator 99 loadout UI reference: https://www.ginx.tv/en/roblox/pet-sim-99-enchant-builds
- Grow a Garden inventory and scaling discussion: https://devforum.roblox.com/t/how-would-i-scale-my-inventory-for-all-platforms-like-grow-a-garden/3861350
- RIVALS match HUD reference: https://games.gg/ja/rivals/
- 99 Nights in the Forest survival HUD reference: https://bo3.gg/games/articles/how-to-eliminate-lag-and-bugs-in-99-night-in-the-forest

The marketplace does not provide a trustworthy universal popularity ranking for UI packs. We therefore used repeated visual patterns across recent packs and live games instead of treating a seller's word "popular" as evidence.

## Repeated 2025–2026 patterns

- Primary navigation is icon-first with a short text label, normally limited to four or five actions.
- Live gameplay HUDs stay compact. Large colorful panels appear only after the player chooses to open a screen.
- Strong packs use one dominant brand color. Reward gold, success green, and danger red are semantic accents rather than five unrelated navigation colors.
- Inventory and shop screens lead with item art, rarity or category cues, prices, quantities, and one clear action.
- Daily rewards use a visual sequence of reward tiles, not paragraphs describing the streak.
- Polished interfaces use deliberate outlines, shallow depth, and clear groups. Merely rounding every rectangle does not create a coherent theme.
- Useful packs are editable in Studio and keep behavior separate from presentation. Unknown third-party scripts remain a security risk even when the screenshots look good.
- Simulator UI is not the only valid Roblox style. Competitive and survival games remove most decorative HUD elements during play, so future starter branches should be theme-specific.

## Applied direction

- Replaced the oversized right rail with a safe-area-aware bottom dock.
- Added icon slots and short labels to all five primary actions.
- Rebuilt the coin HUD around a coin identity, clear count, boost detail, and explicit shop shortcut.
- Replaced rainbow navigation colors with a blue brand system and semantic reward/success colors.
- Added authored `ItemCardTemplate` and `RewardTileTemplate` instances under `StarterGui.TemplateUI.Root.ComponentTemplates`.
- Kept dynamic data population in Luau while leaving ordinary colors, spacing, borders, typography, and card structure editable as Studio instances.
- Used bundled Roblox icons only as working fallbacks. The licensed source icons under `assets/icons/gvesster-basic/` should be uploaded by the experience owner before a final branded release.

## Do not assume

- A generic simulator pack is automatically suitable for every map branch.
- More saturation means more appeal to children.
- A downloaded RBXM is safe because its UI looks polished.
- Local PNG paths can render in a published Roblox experience; chosen source art must be uploaded and assigned Roblox asset IDs.
