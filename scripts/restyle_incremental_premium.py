#!/usr/bin/env python3
"""Restyle the Incremental preset toward a premium "roll game" look.

The authored Incremental UI previously used fully-saturated neon card fills, a
light-cyan scroll background, and all-green action buttons. That reads as flat
and garish. Popular roll/gacha games instead use dark neutral panels with
*colored rarity accents*: dark tiles, a rarity-tinted frame and badge, big
artwork, and a clean type hierarchy.

This pass rewrites only visual properties (colors, gradients, corners, strokes,
text sizes, and — for the shop grid — slot geometry). It never renames a node,
changes a node's ClassName, adds/removes a binding root, or touches an Image
asset id, so the Luau binders in src/client keep working unchanged. It edits
only src/ui/presets/incremental/*; other presets and the base template are left
alone (Figma-bridge boundary: a patch updates one preset).

Runtime still owns behavior and live data. Reward "DayN" tiles keep whatever
background the client assigns from Theme at runtime; everything else is authored
here.

Usage:  python3 scripts/restyle_incremental_premium.py
Safe to re-run (idempotent): tiles already converted are detected and skipped.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRESET = ROOT / "src" / "ui" / "presets" / "incremental"

# ---------------------------------------------------------------------------
# Palette (Color3 as [r, g, b] floats, matching the model format)
# ---------------------------------------------------------------------------
OUTLINE = [0.043, 0.055, 0.106]      # #0B0E1B chunky cartoon outline
PANEL = [0.098, 0.122, 0.235]        # #19203C screen panel body
PANEL_EDGE = [0.145, 0.180, 0.325]   # #252E53 panel top highlight (gradient)
CONTENT = [0.063, 0.082, 0.169]      # #10152B scroll background
TILE = [0.145, 0.184, 0.345]         # #252F58 tile surface
TILE_EDGE = [0.196, 0.243, 0.443]    # #323E71 tile top highlight (gradient)
INNER = [0.086, 0.114, 0.235]        # #161D3C artwork inset
FIELD = [0.078, 0.102, 0.212]        # #141A36 text field
WHITE = [1.0, 1.0, 1.0]
MUTED = [0.706, 0.741, 0.878]        # #B4BDE0 secondary text
DIM = [0.549, 0.588, 0.749]          # #8C96BF tertiary text
GREEN = [0.157, 0.792, 0.353]        # #28CA5A primary action
GREEN_HI = [0.278, 0.878, 0.451]     # gradient top
GREEN_SHADOW = [0.070, 0.470, 0.200]

# Rarity accent cycle used for tile frames/badges (bright but not neon-flat).
RARITY = [
    [1.00, 0.780, 0.235],  # gold
    [0.560, 0.451, 1.00],  # amethyst
    [0.290, 0.800, 1.00],  # cyan
    [1.00, 0.400, 0.640],  # pink
    [0.360, 0.855, 0.482], # green
    [1.00, 0.573, 0.318],  # orange
]

# Per-screen identity hue (kept from the old headers, richened).
SCREEN_ACCENT = {
    "InventoryScreen": [0.259, 0.561, 1.00],
    "StoreScreen": [1.00, 0.310, 0.404],
    "RewardsScreen": [1.00, 0.784, 0.235],
    "ProfileScreen": [0.639, 0.412, 0.980],
    "SettingsScreen": [0.157, 0.792, 0.706],
    "FeedbackScreen": [1.00, 0.510, 0.208],
    "CodesScreen": [1.00, 0.310, 0.600],
    "BoardsScreen": [1.00, 0.667, 0.220],
    "CommunityScreen": [0.290, 0.820, 0.400],
    "DynamicScreen": [0.259, 0.561, 1.00],
}

FREDOKA = {"family": "rbxasset://fonts/families/FredokaOne.json", "weight": "Regular", "style": "Normal"}
NUNITO = {"family": "rbxasset://fonts/families/Nunito.json", "weight": "ExtraBold", "style": "Normal"}

# Names whose backgrounds the client overwrites at runtime; leave their fill.
RUNTIME_FILLED = {f"Day{i}" for i in range(1, 8)}

# Dark ink for text that must sit on the light reward tiles the client paints.
INK_TEXT = [0.110, 0.067, 0.200]  # matches Theme.text (28,17,51)
REWARD_SURFACE = [1.0, 1.0, 1.0]  # matches Theme.colors.surface the client applies


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
def props(node):
    return node.setdefault("Properties", {})


def name_of(node):
    return node.get("Name") or (node.get("Properties") or {}).get("Name")


def kids(node):
    return node.get("Children") or []


def child(node, name):
    for c in kids(node):
        if name_of(c) == name:
            return c
    return None


def child_class(node, cls):
    for c in kids(node):
        if c.get("ClassName") == cls:
            return c
    return None


def descend(node):
    yield node
    for c in kids(node):
        yield from descend(c)


def lighten(color, amount):
    return [min(1.0, c + (1.0 - c) * amount) for c in color]


def darken(color, amount):
    return [max(0.0, c * (1.0 - amount)) for c in color]


def corner(radius):
    return {"ClassName": "UICorner", "Properties": {"CornerRadius": {"UDim": [0, radius]}}, "Children": []}


def stroke_child(color, thickness=3, transparency=0.0):
    return {
        "ClassName": "UIStroke",
        "Properties": {"Color": color, "Thickness": thickness, "Transparency": transparency},
        "Children": [],
    }


def gradient_child(top, bottom, rotation=90):
    return {
        "ClassName": "UIGradient",
        "Properties": {
            "Color": {"ColorSequence": {"keypoints": [
                {"time": 0.0, "color": top},
                {"time": 1.0, "color": bottom},
            ]}},
            "Rotation": rotation,
        },
        "Children": [],
    }


def set_corner(node, radius):
    c = child_class(node, "UICorner")
    if c is None:
        node.setdefault("Children", []).insert(0, corner(radius))
    else:
        c["Properties"] = {"CornerRadius": {"UDim": [0, radius]}}


def set_stroke(node, color, thickness=3, transparency=0.0):
    s = child_class(node, "UIStroke")
    if s is None:
        node.setdefault("Children", []).append(stroke_child(color, thickness, transparency))
    else:
        p = s.setdefault("Properties", {})
        p["Color"] = color
        p["Thickness"] = thickness
        p["Transparency"] = transparency


def set_gradient(node, top, bottom, rotation=90):
    """Replace any existing background UIGradient with one premium fill.

    Removes prior gradients (old "Sheen" tints and previous PremiumFill runs) so
    a stale bright gradient can't override the new fill, and so re-runs stay
    idempotent."""
    node["Children"] = [c for c in kids(node) if c.get("ClassName") != "UIGradient"]
    g = gradient_child(top, bottom, rotation)
    g["Name"] = "PremiumFill"
    node["Children"].insert(0, g)


def set_text(node, color=None, size=None, muted=False):
    p = props(node)
    if color is not None:
        p["TextColor3"] = color
    if size is not None:
        p["TextSize"] = size


# ---------------------------------------------------------------------------
# Element restyles
# ---------------------------------------------------------------------------
def restyle_header(screen, accent):
    header = child(screen, "Header")
    if header:
        hp = props(header)
        hp["BackgroundColor3"] = accent
        set_corner(header, 18)
        set_stroke(header, OUTLINE, 3)
        set_gradient(header, lighten(accent, 0.22), darken(accent, 0.12))
        acc = child(header, "HeaderAccent")
        if acc:
            props(acc)["BackgroundColor3"] = lighten(accent, 0.45)
    for extra in ("PanelBadge",):
        node = child(screen, extra)
        if node:
            props(node)["BackgroundColor3"] = lighten(accent, 0.2)
    title = child(screen, "Title")
    if title:
        set_text(title, WHITE)
        p = props(title)
        p["TextStrokeColor3"] = OUTLINE
        p["TextStrokeTransparency"] = 0.0


def restyle_close(screen):
    for name in ("CloseButton",):
        btn = child(screen, name)
        if btn:
            set_stroke(btn, OUTLINE, 3)
            set_corner(btn, 14)


def restyle_content(screen):
    content = child(screen, "Content")
    if content:
        cp = props(content)
        cp["BackgroundColor3"] = CONTENT
        cp["BackgroundTransparency"] = 0.0
        set_corner(content, 16)
    return content


def restyle_panel(screen, accent):
    sp = props(screen)
    sp["BackgroundColor3"] = PANEL
    set_corner(screen, 24)
    set_stroke(screen, OUTLINE, 3)
    set_gradient(screen, PANEL_EDGE, PANEL, 90)


def style_action_button(node):
    """Green primary CTA with gradient, dark stroke; matching shadow if present."""
    p = props(node)
    p["BackgroundColor3"] = GREEN
    set_corner(node, 12)
    set_stroke(node, OUTLINE, 3)
    set_gradient(node, GREEN_HI, GREEN, 90)
    set_text(node, WHITE)
    p["TextStrokeColor3"] = OUTLINE
    p["TextStrokeTransparency"] = 0.0


def style_pill(node, accent, text_color=None):
    """Turn a bare label into a rounded rarity/price badge."""
    p = props(node)
    p["BackgroundColor3"] = accent
    p["BackgroundTransparency"] = 0.0
    set_corner(node, 10)
    set_stroke(node, OUTLINE, 2)
    set_text(node, text_color if text_color is not None else OUTLINE)
    p["TextStrokeTransparency"] = 1.0


def restyle_tile(slot, accent):
    """Neon fill -> dark tile + rarity frame, artwork inset, badge, CTA."""
    p = props(slot)
    p["BackgroundColor3"] = TILE
    set_corner(slot, 18)
    set_stroke(slot, accent, 3)
    set_gradient(slot, TILE_EDGE, TILE, 90)

    art = child(slot, "Artwork")
    if art:
        ap = props(art)
        ap["BackgroundColor3"] = INNER
        set_corner(art, 14)
        set_stroke(art, lighten(accent, 0.15), 3)
        glyph = child(art, "Glyph")
        if glyph:
            set_text(glyph, WHITE)
            gp = props(glyph)
            gp["TextStrokeColor3"] = OUTLINE
            gp["TextStrokeTransparency"] = 0.0

    title = child(slot, "Title")
    if title:
        set_text(title, WHITE, 17)
    body = child(slot, "Body")
    if body:
        set_text(body, MUTED, 12)
    qty = child(slot, "Quantity")
    if qty:
        style_pill(qty, accent)

    shadow = child(slot, "ActionButtonShadow")
    if shadow:
        props(shadow)["BackgroundColor3"] = GREEN_SHADOW
        set_corner(shadow, 12)
    action = child(slot, "ActionButton")
    if action:
        style_action_button(action)


def restyle_reward_tile(tile):
    """Daily-reward DayN tiles: the client repaints the fill light at runtime and
    only recolors StateLabel, leaving DayLabel/AmountLabel white (unreadable on a
    light fill). Author a clean light card with dark text so Studio matches
    runtime and the text stays legible either way."""
    p = props(tile)
    p["BackgroundColor3"] = REWARD_SURFACE
    set_corner(tile, 16)
    set_stroke(tile, OUTLINE, 3)
    for label in ("DayLabel", "AmountLabel", "StateLabel"):
        node = child(tile, label)
        if node:
            set_text(node, INK_TEXT)
            lp = props(node)
            lp["TextStrokeTransparency"] = 1.0
    badge = child(tile, "CoinBadge")
    if badge:
        set_stroke(badge, OUTLINE, 3)


def restyle_generic_card(card, accent):
    """StreakCard/OfflineCard/StatsCard/rows/etc: dark card, white title, muted body."""
    if name_of(card) in RUNTIME_FILLED:
        return
    p = props(card)
    p["BackgroundColor3"] = TILE
    set_corner(card, 16)
    set_stroke(card, OUTLINE, 3)
    title = child(card, "Title")
    if title:
        set_text(title, WHITE, max(15, int(props(title).get("TextSize", 16))))
    body = child(card, "Body")
    if body:
        set_text(body, MUTED)
    for badge_name in ("IconBadge", "CoinBadge"):
        badge = child(card, badge_name)
        if badge:
            props(badge)["BackgroundColor3"] = INNER
            set_stroke(badge, lighten(accent, 0.1), 3)


def copy_geometry(template_slot, target_slot):
    """Give a StoreSlot the same child geometry as an ItemSlot (vertical card)."""
    geo_keys = ("AnchorPoint", "Position", "Size", "TextXAlignment")
    tmap = {name_of(c): c for c in kids(template_slot) if name_of(c)}
    for c in kids(target_slot):
        n = name_of(c)
        src = tmap.get(n)
        if not src:
            continue
        sp = src.get("Properties", {})
        cp = props(c)
        for key in geo_keys:
            if key in sp:
                cp[key] = json.loads(json.dumps(sp[key]))


# ---------------------------------------------------------------------------
# HUD / navigation / tray
# ---------------------------------------------------------------------------
def restyle_hud(root):
    hud = child(root, "CurrencyHUD")
    if not hud:
        return
    for name in ("PillBackground",):
        node = child(hud, name)
        if node:
            np = props(node)
            np["BackgroundColor3"] = PANEL
            set_gradient(node, PANEL_EDGE, PANEL, 90)
    hp = props(hud)
    if "BackgroundColor3" in hp and hp.get("BackgroundTransparency", 0) != 1:
        hp["BackgroundColor3"] = PANEL
    set_stroke(hud, OUTLINE, 3)
    for label in ("CoinLabel", "CoinCaption", "BoostLabel"):
        node = child(hud, label)
        if node:
            set_text(node, WHITE if label != "CoinCaption" else MUTED)
            props(node)["TextStrokeColor3"] = OUTLINE
            props(node)["TextStrokeTransparency"] = 0.0
    add = child(hud, "AddCoinsButton")
    if add:
        style_action_button(add)
    badge = child(hud, "CoinBadge")
    if badge:
        set_stroke(badge, OUTLINE, 3)  # clean dark frame around the gold coin


def restyle_nav(root):
    for holder_name in ("Navigation", "MoreMenu"):
        holder = child(root, holder_name)
        if not holder:
            continue
        hp = props(holder)
        if hp.get("BackgroundTransparency", 0) != 1:
            hp["BackgroundColor3"] = PANEL
            set_stroke(holder, OUTLINE, 3)
        buttons = child(holder, "Buttons")
        if not buttons:
            continue
        idx = 0
        for btn in kids(buttons):
            if btn.get("ClassName") not in ("TextButton", "ImageButton", "Frame"):
                continue
            if not name_of(btn):
                continue
            accent = RARITY[idx % len(RARITY)]
            idx += 1
            bubble = child(btn, "IconBubble")
            if bubble:
                # nav-rail tile: dark bubble with a rarity-tinted frame
                props(bubble)["BackgroundColor3"] = TILE
                set_stroke(bubble, accent, 3)
            elif btn.get("ClassName") in ("TextButton", "ImageButton"):
                # more-menu row: dark chip (was a white pill with a white sheen)
                bp = props(btn)
                bp["BackgroundColor3"] = TILE
                set_corner(btn, 14)
                set_stroke(btn, accent, 3)
                set_gradient(btn, TILE_EDGE, TILE)
                fb = child(btn, "Fallback")
                if fb:
                    set_text(fb, WHITE)
            label = child(btn, "Label")
            if label:
                set_text(label, WHITE)
                props(label)["TextStrokeColor3"] = OUTLINE
                props(label)["TextStrokeTransparency"] = 0.0


def restyle_tray(root):
    tray = child(root, "CurrencyTray")
    if not tray:
        return
    slots = child(tray, "Slots")
    if not slots:
        return
    idx = 0
    for slot in kids(slots):
        if not name_of(slot) or not name_of(slot).startswith("CurrencySlot"):
            continue
        accent = RARITY[idx % len(RARITY)]
        idx += 1
        sp = props(slot)
        sp["BackgroundColor3"] = PANEL
        set_stroke(slot, OUTLINE, 3)
        set_gradient(slot, PANEL_EDGE, PANEL, 90)
        acc = child(slot, "Accent")
        if acc:
            props(acc)["BackgroundColor3"] = accent
            set_stroke(acc, OUTLINE, 2)
        for lbl, col in (("AmountLabel", WHITE), ("Caption", MUTED)):
            node = child(slot, lbl)
            if node:
                set_text(node, col)
    boost = child(tray, "BoostLabel")
    if boost:
        set_text(boost, WHITE)


# ---------------------------------------------------------------------------
# Toolbar / buttons inside screens
# ---------------------------------------------------------------------------
def restyle_toolbar(content, accent):
    toolbar = child(content, "Toolbar")
    if not toolbar:
        return
    props(toolbar)["BackgroundColor3"] = FIELD
    set_corner(toolbar, 14)
    search = child(toolbar, "SearchInput")
    if search:
        sp = props(search)
        sp["BackgroundColor3"] = FIELD
        sp["TextColor3"] = WHITE
        if "PlaceholderColor3" in sp or True:
            sp["PlaceholderColor3"] = DIM
        set_stroke(search, OUTLINE, 2)
        set_corner(search, 12)
    for name in ("CategoryButton",):
        btn = child(toolbar, name)
        if btn:
            props(btn)["BackgroundColor3"] = accent
            set_stroke(btn, OUTLINE, 2)
            set_corner(btn, 12)
            set_gradient(btn, lighten(accent, 0.18), darken(accent, 0.12))
            set_text(btn, WHITE)
            props(btn)["TextStrokeColor3"] = OUTLINE
            props(btn)["TextStrokeTransparency"] = 0.0
        sh = child(toolbar, "CategoryButtonShadow")
        if sh:
            props(sh)["BackgroundColor3"] = darken(accent, 0.35)


CARD_NAMES = {
    "StreakCard", "OfflineCard", "StatsCard", "SearchIntro", "SearchResult",
    "LikesCard", "CommunityCard", "ClubsCard", "SavedCard", "EmptyState",
}
CARD_PREFIXES = ("Milestone", "LeaderRow", "ListRow")


def is_card(node):
    n = name_of(node) or ""
    if n in CARD_NAMES:
        return True
    return any(n.startswith(p) and n[len(p):].isdigit() for p in CARD_PREFIXES)


def restyle_content_children(content, accent):
    """Walk a screen's Content and give cards/buttons the premium treatment."""
    # Direct-child banner frames ("StoreHeader", "FeedbackIntro") and section
    # heading labels get the dark treatment with the screen's accent.
    for direct in kids(content):
        n = name_of(direct) or ""
        if direct.get("ClassName") == "Frame" and (n.endswith("Header") or n.endswith("Intro")):
            restyle_generic_card(direct, accent)
            set_stroke(direct, accent, 3)
        if direct.get("ClassName") == "TextLabel" and (n.endswith("Heading") or n.endswith("Header")):
            set_text(direct, WHITE)
            props(direct)["TextStrokeColor3"] = OUTLINE
            props(direct)["TextStrokeTransparency"] = 0.0

    for node in list(descend(content)):
        n = name_of(node) or ""
        cls = node.get("ClassName")
        if is_card(node):
            restyle_generic_card(node, accent)
        # a category selector sitting directly in content (e.g. Feedback) -> accent chip
        if cls == "TextButton" and n == "CategoryButton":
            p = props(node)
            p["BackgroundColor3"] = accent
            set_corner(node, 12)
            set_stroke(node, OUTLINE, 2)
            set_gradient(node, lighten(accent, 0.18), darken(accent, 0.12))
            set_text(node, WHITE)
            p["TextStrokeColor3"] = OUTLINE
            p["TextStrokeTransparency"] = 0.0
        # standalone content buttons (claim/redeem/submit/toggles/global)
        if cls == "TextButton" and n not in ("ActionButton", "CategoryButton", "CloseButton"):
            p = props(node)
            # keep primary claim/redeem/submit green; toggles get a dark chip
            if n in ("ClaimDailyButton", "ClaimOfflineButton", "RedeemButton", "SubmitButton", "SearchButton", "GlobalButton", "ExtendedOfflineButton"):
                style_action_button(node)
            else:
                p["BackgroundColor3"] = TILE
                set_corner(node, 12)
                set_stroke(node, OUTLINE, 2)
                set_gradient(node, TILE_EDGE, TILE)
                set_text(node, WHITE)
                p["TextStrokeColor3"] = OUTLINE
                p["TextStrokeTransparency"] = 0.0
        if cls == "TextBox" and n in ("SearchInput", "MessageInput", "CodeInput"):
            p = props(node)
            p["BackgroundColor3"] = FIELD
            p["TextColor3"] = WHITE
            p["PlaceholderColor3"] = DIM
            set_stroke(node, OUTLINE, 2)
            set_corner(node, 12)


# ---------------------------------------------------------------------------
# Main model transform
# ---------------------------------------------------------------------------
def restyle_template_ui(model):
    root = model["Children"][0]
    screens = child(root, "Screens")

    # capture a good vertical-card template from the inventory before edits
    item_template = None
    if screens:
        inv = child(screens, "InventoryScreen")
        if inv:
            grid = child(child(inv, "Content"), "ItemsGrid")
            if grid:
                item_template = child(grid, "ItemSlot01")

    if screens:
        for screen in kids(screens):
            sname = name_of(screen)
            accent = SCREEN_ACCENT.get(sname, RARITY[0])
            restyle_panel(screen, accent)
            restyle_header(screen, accent)
            restyle_close(screen)
            content = restyle_content(screen)
            if content is None:
                continue
            restyle_toolbar(content, accent)
            restyle_content_children(content, accent)

            # daily reward strip -> readable light cards (client repaints fill)
            strip = child(content, "RewardStrip")
            if strip:
                for tile in kids(strip):
                    if (name_of(tile) or "").startswith("Day"):
                        restyle_reward_tile(tile)

            # inventory item grid -> rarity tiles
            grid = child(content, "ItemsGrid")
            if grid:
                i = 0
                for slot in kids(grid):
                    if (name_of(slot) or "").startswith("ItemSlot"):
                        restyle_tile(slot, RARITY[i % len(RARITY)])
                        i += 1

            # store list -> 2-column card grid reusing item geometry
            pgrid = child(content, "ProductsGrid")
            if pgrid:
                layout = child_class(pgrid, "UIGridLayout")
                if layout:
                    lp = props(layout)
                    lp["CellSize"] = {"UDim2": [[0.5, -5], [0, 202]]}
                    lp["CellPadding"] = {"UDim2": [[0, 10], [0, 10]]}
                    lp["FillDirectionMaxCells"] = 2
                    lp["HorizontalAlignment"] = "Center"
                i = 0
                for slot in kids(pgrid):
                    if (name_of(slot) or "").startswith("StoreSlot"):
                        props(slot)["Size"] = {"UDim2": [[0.5, -5], [0, 202]]}
                        if item_template is not None:
                            copy_geometry(item_template, slot)
                        restyle_tile(slot, RARITY[i % len(RARITY)])
                        i += 1

    restyle_hud(root)
    restyle_nav(root)
    restyle_tray(root)
    return model


def recolor_simple(model):
    """Loading + sign screens: swap the light card/background for the dark palette.

    Walks the whole tree (these roots are a ScreenGui or a BillboardGui with
    several top-level children), not just the first branch."""
    for node in descend(model):
        p = node.get("Properties", {})
        bg = p.get("BackgroundColor3")
        if isinstance(bg, list) and len(bg) == 3:
            r, g, b = bg
            # near-white surfaces -> dark tile; light cyan -> content
            if r > 0.9 and g > 0.9 and b > 0.9:
                p["BackgroundColor3"] = PANEL
            elif abs(r - 0.84) < 0.12 and b > 0.9 and g > 0.9:
                p["BackgroundColor3"] = CONTENT
        txt = p.get("TextColor3")
        if isinstance(txt, list) and len(txt) == 3 and max(txt) < 0.25:
            # very dark text on now-dark surfaces -> light
            p["TextColor3"] = WHITE
    return model


def main():
    ui = PRESET / "TemplateUI.model.json"
    model = json.loads(ui.read_text(encoding="utf-8"))
    restyle_template_ui(model)
    ui.write_text(json.dumps(model, ensure_ascii=False), encoding="utf-8")
    print(f"restyled {ui.relative_to(ROOT)}")

    for extra in ("TemplateLoading.model.json", "StarterSignUI.model.json"):
        path = PRESET / extra
        if path.exists():
            m = json.loads(path.read_text(encoding="utf-8"))
            recolor_simple(m)
            path.write_text(json.dumps(m, ensure_ascii=False), encoding="utf-8")
            print(f"restyled {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
