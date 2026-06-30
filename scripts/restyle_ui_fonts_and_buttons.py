#!/usr/bin/env python3
"""One-off restyle pass for src/ui/TemplateUI.model.json.

Swaps the authored GothamSSm FontFace for a chunkier, rounder pair (Fredoka
for emphasis/header text, Nunito for body text) and gives every rounded
TextButton a glossy UIGradient plus, where safe, an offset "candy button"
shadow frame. Re-run after adding new buttons/text to the model; it is
idempotent (skips instances it already touched).

Usage: python3 scripts/restyle_ui_fonts_and_buttons.py
"""

import copy
import json
import pathlib

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
MODEL_PATH = REPO_ROOT / "src" / "ui" / "TemplateUI.model.json"

LAYOUT_CLASSES = {"UIGridLayout", "UIListLayout", "UITableLayout"}

FONT_MAP = {
    ("rbxasset://fonts/families/GothamSSm.json", "Heavy"): {
        "family": "rbxasset://fonts/families/FredokaOne.json",
        "weight": "Regular",
        "style": "Normal",
    },
    ("rbxasset://fonts/families/GothamSSm.json", "Bold"): {
        "family": "rbxasset://fonts/families/Nunito.json",
        "weight": "ExtraBold",
        "style": "Normal",
    },
}


def clamp01(x):
    return max(0.0, min(1.0, x))


def lighten(rgb, amount):
    return [clamp01(c + (1 - c) * amount) for c in rgb]


def darken(rgb, amount):
    return [clamp01(c * (1 - amount)) for c in rgb]


def find_child(node, class_name):
    for c in node.get("Children", []) or []:
        if c.get("ClassName") == class_name:
            return c
    return None


def find_child_named(node, name):
    for c in node.get("Children", []) or []:
        if (c.get("Name") or (c.get("Properties", {}) or {}).get("Name")) == name:
            return c
    return None


def fix_fonts(node, stats):
    props = node.get("Properties")
    if props:
        font = props.get("FontFace") or props.get("Font")
        if isinstance(font, dict):
            key = (font.get("family"), font.get("weight"))
            if key in FONT_MAP:
                new_font = dict(FONT_MAP[key])
                prop_name = "FontFace" if "FontFace" in props else "Font"
                props[prop_name] = new_font
                stats["Heavy->FredokaOne" if key[1] == "Heavy" else "Bold->Nunito"] += 1
    for c in node.get("Children", []) or []:
        fix_fonts(c, stats)


def add_button_depth(node, stats, parent_has_layout=False):
    children = node.get("Children", []) or []
    has_layout = any(c.get("ClassName") in LAYOUT_CLASSES for c in children)
    props = node.get("Properties", {}) or {}
    corner = find_child(node, "UICorner")

    if node.get("ClassName") == "TextButton" and corner is not None:
        if find_child(node, "UIGradient") is None:
            base = props.get("BackgroundColor3", [1, 1, 1])
            gradient = {
                "Name": "Sheen",
                "ClassName": "UIGradient",
                "Properties": {
                    "Color": {
                        "ColorSequence": {
                            "keypoints": [
                                {"time": 0.0, "color": lighten(base, 0.22)},
                                {"time": 1.0, "color": darken(base, 0.10)},
                            ]
                        }
                    },
                    "Rotation": 90,
                },
                "Children": [],
            }
            children.insert(0, gradient)
            stats["gradients"] += 1

        button_name = node.get("Name", "Button")
        shadow_name = f"{button_name}Shadow"
        if not parent_has_layout and node.get("_owner_has_shadow") is None:
            node["_owner_has_shadow"] = shadow_name
            base = props.get("BackgroundColor3", [0.8, 0.8, 0.8])
            size = props.get("Size", {"UDim2": [[1, 0], [0, 40]]})
            height = size.get("UDim2", [[0, 0], [0, 40]])[1][1] or 40
            offset_px = 5 if height >= 40 else 3
            pos_udim2 = props.get("Position", {"UDim2": [[0, 0], [0, 0]]}).get("UDim2", [[0, 0], [0, 0]])
            shadow_props = {
                "Size": size,
                "Position": {"UDim2": [list(pos_udim2[0]), [pos_udim2[1][0], pos_udim2[1][1] + offset_px]]},
                "BackgroundColor3": darken(base, 0.34),
                "BackgroundTransparency": props.get("BackgroundTransparency", 0),
                "BorderSizePixel": 0,
                "ZIndex": props.get("ZIndex", 1),
            }
            if "AnchorPoint" in props:
                shadow_props["AnchorPoint"] = props["AnchorPoint"]
            shadow_children = [copy.deepcopy(corner)]
            stroke = find_child(node, "UIStroke")
            if stroke is not None:
                shadow_children.append(copy.deepcopy(stroke))
            node["_pending_shadow"] = {
                "Name": shadow_name,
                "ClassName": "Frame",
                "Properties": shadow_props,
                "Children": shadow_children,
            }
            stats["shadows"] += 1

    for c in children:
        add_button_depth(c, stats, has_layout)


def splice_shadows(node):
    children = node.get("Children", []) or []
    new_children = []
    for c in children:
        pending = c.pop("_pending_shadow", None)
        c.pop("_owner_has_shadow", None)
        if pending is not None:
            new_children.append(pending)
        new_children.append(c)
    node["Children"] = new_children
    for c in new_children:
        splice_shadows(c)


def skip_already_shadowed(node, parent_has_layout=False):
    """Mark buttons that already have a matching <Name>Shadow sibling so a
    re-run doesn't add a second one."""
    children = node.get("Children", []) or []
    has_layout = any(c.get("ClassName") in LAYOUT_CLASSES for c in children)
    for c in children:
        if c.get("ClassName") == "TextButton":
            shadow_name = f"{c.get('Name', 'Button')}Shadow"
            if find_child_named(node, shadow_name) is not None:
                c["_owner_has_shadow"] = shadow_name
        skip_already_shadowed(c, has_layout)


def count(node):
    return 1 + sum(count(c) for c in (node.get("Children") or []))


def main():
    with open(MODEL_PATH) as f:
        data = json.load(f)

    before = count(data)
    skip_already_shadowed(data)

    font_stats = {"Heavy->FredokaOne": 0, "Bold->Nunito": 0}
    depth_stats = {"gradients": 0, "shadows": 0}

    fix_fonts(data, font_stats)
    add_button_depth(data, depth_stats)
    splice_shadows(data)

    after = count(data)

    with open(MODEL_PATH, "w") as f:
        json.dump(data, f)

    print("font conversions:", font_stats)
    print("gradients added:", depth_stats["gradients"])
    print("shadow frames added:", depth_stats["shadows"])
    print("instance count:", before, "->", after)


if __name__ == "__main__":
    main()
