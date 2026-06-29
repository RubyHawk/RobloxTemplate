# 2026-06-28: kid-friendly connected UI

## Critique

The first connected HUD looked like a generic dark admin dashboard and placed nine equal-priority actions in one strip. Recoloring it would not fix the weak hierarchy.

## Decision

The connected UI now has one compact coin card and a five-action bottom dock: Bag, Shop, Rewards, Profile, and More. Each primary action combines an icon with a short label. Codes, rankings, community, feedback, and settings live in a separate two-column menu. Inventory, store, and daily rewards use authored visual card templates rather than generic text-only rows.

The UI uses one dominant blue identity with yellow reserved for rewards and green for positive actions. It keeps large touch targets, high-contrast dark text on light surfaces or white text on saturated buttons, wrapped text, safe insets, and reduced-motion-aware tweens. It avoids countdown pressure, fake scarcity, and other manipulative patterns aimed at children.

## Official guidance checked

Checked on 2026-06-28:

- Roblox UI overview: https://create.roblox.com/docs/ui
- Roblox accessibility guidelines: https://create.roblox.com/docs/production/publishing/accessibility
- Roblox Studio device testing: https://create.roblox.com/docs/studio/testing-modes

Recheck these sources before changing accessibility behavior, preferred text sizing, transparency, or reduced motion.
