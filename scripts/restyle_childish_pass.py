#!/usr/bin/env python3
"""Second restyle pass on src/ui/TemplateUI.model.json: colored rings around
icon badges, gap-aware icon enlargement (grows each badge only as much as
its own layout has real slack for, computed per instance - never a blind
fixed percentage), rounded-square nav/tray tiles, and a couple of
hand-placed ribbon/star accents on the two hero cards. Skips
ShowcaseCanvas entirely - that subtree is the licensed third-party
showroom pack, out of scope for template restyling.

Re-run after adding new IconBadge/Artwork/CoinBadge instances; already-large
rings are left alone (checked by ring thickness) so repeat runs don't keep
inflating the same icon.

Usage: python3 scripts/restyle_childish_pass.py
"""

import copy
import pathlib
import json

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
MODEL_PATH = REPO_ROOT / "src" / "ui" / "TemplateUI.model.json"

RING_PALETTE = [
    [0.62, 0.24, 0.96],  # purple
    [0.05, 0.48, 1.0],  # blue
    [1.0, 0.79, 0.04],  # gold
    [1.0, 0.18, 0.54],  # pink
    [0.02, 0.82, 0.7],  # teal
]
RING_THICKNESS = 4
SAFETY_MARGIN_PX = 3
MAX_GROWTH_UNCONSTRAINED = 0.22
MAX_GROWTH_CONSTRAINED_OF_SIZE = 0.35

ring_index = 0
stats = {"rings_added": 0, "grown": 0, "nav_tiles_rounded": 0, "hero_accents": 0}


def find_child(node, class_name):
    for c in node.get("Children", []) or []:
        if c.get("ClassName") == class_name:
            return c
    return None


def name_of(node):
    return node.get("Name") or (node.get("Properties", {}) or {}).get("Name")


def find_child_named(node, name):
    for c in node.get("Children", []) or []:
        if name_of(c) == name:
            return c
    return None


def get_size(props):
    size = props.get("Size", {}).get("UDim2", [[0, 0], [0, 40]])
    return size[0][0], size[0][1], size[1][0], size[1][1]


def get_pos(props):
    pos = props.get("Position", {}).get("UDim2", [[0, 0], [0, 0]])
    return pos[0][0], pos[0][1], pos[1][0], pos[1][1]


def next_ring_color():
    global ring_index
    color = RING_PALETTE[ring_index % len(RING_PALETTE)]
    ring_index += 1
    return color


def add_or_update_ring(node):
    stroke = find_child(node, "UIStroke")
    color = next_ring_color()
    if stroke is None:
        stroke = {"ClassName": "UIStroke", "Properties": {}, "Children": []}
        node.setdefault("Children", []).append(stroke)
    props = stroke.setdefault("Properties", {})
    already_ringed = props.get("Thickness", 0) >= RING_THICKNESS
    props["Thickness"] = RING_THICKNESS
    props["Color"] = color
    props["Transparency"] = 0
    return already_ringed


def compute_min_gap(node, parent):
    """Smallest horizontal gap to any sibling positioned to the right at the
    same X-scale-basis (same layout column convention)."""
    props = node.get("Properties", {}) or {}
    sx, sox, sy, soy = get_size(props)
    px, pox, py, poy = get_pos(props)
    min_gap = None
    for sib in parent.get("Children", []) or []:
        if sib is node:
            continue
        sp = sib.get("Properties", {}) or {}
        if "Size" not in sp or "Position" not in sp:
            continue
        _, sib_ox, _, _ = get_size(sp)
        sib_px, sib_pox, _, _ = get_pos(sp)
        if sib_pox > pox and abs(sib_px - px) < 0.001:
            gap = sib_pox - (pox + sox)
            if min_gap is None or gap < min_gap:
                min_gap = gap
    return min_gap


def grow_badge(node, parent):
    props = node.get("Properties", {}) or {}
    sx, ox, sy, oy = get_size(props)
    if sx != 0 or sy != 0:
        return False  # scale-based sizing isn't part of this fixed-offset badge pattern
    gap = compute_min_gap(node, parent)
    if gap is None:
        growth = ox * MAX_GROWTH_UNCONSTRAINED
    else:
        available = gap - SAFETY_MARGIN_PX
        if available <= 2:
            return False
        growth = min(available, ox * MAX_GROWTH_CONSTRAINED_OF_SIZE)
    if growth < 2:
        return False

    # UDim.Offset is stored as an integer in the engine; Rojo's model JSON
    # rejects a fractional offset outright (rather than truncating it), so
    # every computed offset must be rounded before it's written back.
    new_size = round(ox + growth)
    props["Size"] = {"UDim2": [[0, new_size], [0, new_size]]}

    px, pox, py, poy = get_pos(props)
    if abs(py - 0.5) < 0.001:
        # vertically centered via Position={0.5, -halfHeight}; keep centered
        props["Position"] = {"UDim2": [[px, pox], [py, round(-new_size / 2)]]}
    return True


def restyle_badges(node, parent=None, skip=False):
    name = name_of(node)
    if name == "ShowcaseCanvas":
        skip = True
    if not skip and name in ("IconBadge", "Artwork", "CoinBadge") and parent is not None:
        already = add_or_update_ring(node)
        if not already:
            stats["rings_added"] += 1
            if grow_badge(node, parent):
                stats["grown"] += 1
    for c in node.get("Children", []) or []:
        restyle_badges(c, node, skip)


def round_nav_tiles(root):
    """IconBubble circles -> rounded squares, matching the reference's
    bottom icon-tray look instead of full circles. Nav + more-menu tiles
    only (by name), not every circular badge in the file."""
    nav_names = {"BagButton", "ShopButton", "GiftButton", "ProfileButton", "MoreButton"}

    def find_all(node, names, path="ROOT"):
        n = name_of(node)
        if n == "ShowcaseCanvas":
            return
        here = f"{path}/{n}" if n else path
        if n in names:
            yield node
        for c in node.get("Children", []) or []:
            yield from find_all(c, names, here)

    for button in find_all(root, nav_names):
        bubble = find_child_named(button, "IconBubble")
        if bubble is None:
            continue
        corner = find_child(bubble, "UICorner")
        if corner is not None:
            corner["Properties"] = {"CornerRadius": {"UDim": [0, 16]}}
            stats["nav_tiles_rounded"] += 1


def add_ribbon_and_star(card, ribbon_text, star_text="★"):
    """Small rotated banner tag + tilted star badge hanging off a card's
    top-left corner. No native cut-corner shape in Roblox, so this is a
    rotated rounded rect rather than the angled-cut ribbon from the
    reference art - the closest safe approximation without a new image
    asset."""
    if find_child_named(card, "RibbonTag") is not None:
        return False

    ribbon = {
        "Name": "RibbonTag",
        "ClassName": "Frame",
        "Properties": {
            "Size": {"UDim2": [[0, 108], [0, 30]]},
            "Position": {"UDim2": [[0, -14], [0, -12]]},
            "Rotation": -8,
            "BackgroundColor3": [1.0, 0.7686275, 0.1803922],
            "BorderSizePixel": 0,
            "ZIndex": 60,
        },
        "Children": [
            {"ClassName": "UICorner", "Properties": {"CornerRadius": {"UDim": [0, 8]}}, "Children": []},
            {
                "ClassName": "UIStroke",
                "Properties": {"Thickness": 3, "Color": [0.025, 0.035, 0.09], "Transparency": 0},
                "Children": [],
            },
            {
                "Name": "Label",
                "ClassName": "TextLabel",
                "Properties": {
                    "Size": {"UDim2": [[1, 0], [1, 0]]},
                    "BackgroundTransparency": 1,
                    "Text": ribbon_text,
                    "TextColor3": [0.4666667, 0.2509804, 0.0235294],
                    "TextSize": 13,
                    "FontFace": {
                        "family": "rbxasset://fonts/families/FredokaOne.json",
                        "weight": "Regular",
                        "style": "Normal",
                    },
                    "ZIndex": 61,
                },
                "Children": [],
            },
        ],
    }

    star = {
        "Name": "StarBadge",
        "ClassName": "Frame",
        "Properties": {
            "Size": {"UDim2": [[0, 34], [0, 34]]},
            "Position": {"UDim2": [[1, -20], [0, -14]]},
            "Rotation": -14,
            "BackgroundColor3": [1.0, 0.7686275, 0.1803922],
            "BorderSizePixel": 0,
            "ZIndex": 60,
        },
        "Children": [
            {"ClassName": "UICorner", "Properties": {"CornerRadius": {"UDim": [1, 0]}}, "Children": []},
            {
                "ClassName": "UIStroke",
                "Properties": {"Thickness": 3, "Color": [0.025, 0.035, 0.09], "Transparency": 0},
                "Children": [],
            },
            {
                "Name": "Label",
                "ClassName": "TextLabel",
                "Properties": {
                    "Size": {"UDim2": [[1, 0], [1, 0]]},
                    "BackgroundTransparency": 1,
                    "Text": star_text,
                    "TextColor3": [0.4666667, 0.2509804, 0.0235294],
                    "TextSize": 16,
                    "FontFace": {
                        "family": "rbxasset://fonts/families/FredokaOne.json",
                        "weight": "Regular",
                        "style": "Normal",
                    },
                    "ZIndex": 61,
                },
                "Children": [],
            },
        ],
    }

    card.setdefault("Children", []).append(ribbon)
    card.setdefault("Children", []).append(star)
    stats["hero_accents"] += 2
    return True


def find_path(node, target_name, path="ROOT"):
    n = name_of(node)
    here = f"{path}/{n}" if n else path
    if n == target_name:
        yield here, node
    for c in node.get("Children", []) or []:
        yield from find_path(c, target_name, here)


def count(node):
    return 1 + sum(count(c) for c in (node.get("Children") or []))


def main():
    with open(MODEL_PATH, encoding="utf-8") as f:
        data = json.load(f)

    root = data["Children"][0]
    before = count(data)

    restyle_badges(root)
    round_nav_tiles(root)

    for path, node in find_path(root, "StoreHeader"):
        if "ShowcaseCanvas" not in path:
            add_ribbon_and_star(node, "FEATURED")
    for path, node in find_path(root, "StreakCard"):
        if "ShowcaseCanvas" not in path:
            add_ribbon_and_star(node, "STREAK")

    after = count(data)

    with open(MODEL_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)

    print("stats:", stats)
    print("instance count:", before, "->", after)


if __name__ == "__main__":
    main()
