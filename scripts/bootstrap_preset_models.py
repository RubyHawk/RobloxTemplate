#!/usr/bin/env python3
"""Create the first independent authored UI preset sources.

This is intentionally conservative: existing preset files are never replaced,
so rerunning it cannot erase UI Plus/Studio work saved back into a preset.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "src" / "ui"
PRESETS = UI / "presets"
BASE_UI = UI / "TemplateUI.model.json"


def name_of(node: dict) -> str:
    return node.get("Name") or node.get("Properties", {}).get("Name", "")


def walk(node: dict):
    yield node
    for child in node.get("Children", []) or []:
        yield from walk(child)


def child(node: dict, name: str) -> dict | None:
    return next((item for item in node.get("Children", []) or [] if name_of(item) == name), None)


def corner(radius: int) -> dict:
    return {
        "ClassName": "UICorner",
        "Properties": {"CornerRadius": {"UDim": [0, radius]}},
        "Children": [],
    }


def stroke(thickness: int = 3) -> dict:
    return {
        "ClassName": "UIStroke",
        "Properties": {"Color": [0.025, 0.035, 0.09], "Thickness": thickness, "Transparency": 0},
        "Children": [],
    }


def currency_slot(index: int, accent: list[float]) -> dict:
    return {
        "Name": f"CurrencySlot{index:02d}",
        "ClassName": "Frame",
        "Properties": {
            "BackgroundColor3": [1, 1, 1],
            "BorderSizePixel": 0,
            "LayoutOrder": index,
            "Size": {"UDim2": [[0, 154], [0, 58]]},
            "Visible": index == 1,
            "ZIndex": 7,
        },
        "Children": [
            corner(18),
            stroke(3),
            {
                "Name": "Accent",
                "ClassName": "Frame",
                "Properties": {
                    "BackgroundColor3": accent,
                    "BorderSizePixel": 0,
                    "Position": {"UDim2": [[0, 5], [0, 5]]},
                    "Size": {"UDim2": [[0, 48], [0, 48]]},
                    "ZIndex": 8,
                },
                "Children": [corner(14), stroke(3)],
            },
            {
                "Name": "Symbol",
                "ClassName": "TextLabel",
                "Properties": {
                    "BackgroundTransparency": 1,
                    "FontFace": {
                        "family": "rbxasset://fonts/families/FredokaOne.json",
                        "weight": "Regular",
                        "style": "Normal",
                    },
                    "Position": {"UDim2": [[0, 5], [0, 5]]},
                    "Size": {"UDim2": [[0, 48], [0, 48]]},
                    "Text": str(index),
                    "TextColor3": [1, 1, 1],
                    "TextSize": 22,
                    "TextStrokeColor3": [0.025, 0.035, 0.09],
                    "TextStrokeTransparency": 0,
                    "ZIndex": 9,
                },
                "Children": [],
            },
            {
                "Name": "AmountLabel",
                "ClassName": "TextLabel",
                "Properties": {
                    "BackgroundTransparency": 1,
                    "FontFace": {
                        "family": "rbxasset://fonts/families/Nunito.json",
                        "weight": "ExtraBold",
                        "style": "Normal",
                    },
                    "Position": {"UDim2": [[0, 59], [0, 4]]},
                    "Size": {"UDim2": [[1, -66], [0, 31]]},
                    "Text": "0",
                    "TextColor3": [0.025, 0.035, 0.09],
                    "TextSize": 20,
                    "TextXAlignment": "Left",
                    "ZIndex": 8,
                },
                "Children": [],
            },
            {
                "Name": "Caption",
                "ClassName": "TextLabel",
                "Properties": {
                    "BackgroundTransparency": 1,
                    "FontFace": {
                        "family": "rbxasset://fonts/families/Nunito.json",
                        "weight": "ExtraBold",
                        "style": "Normal",
                    },
                    "Position": {"UDim2": [[0, 60], [0, 32]]},
                    "Size": {"UDim2": [[1, -67], [0, 19]]},
                    "Text": "CURRENCY",
                    "TextColor3": [0.32, 0.34, 0.46],
                    "TextSize": 10,
                    "TextXAlignment": "Left",
                    "ZIndex": 8,
                },
                "Children": [],
            },
        ],
    }


def ensure_currency_tray(model: dict) -> None:
    root = model["Children"][0]
    if child(root, "CurrencyTray") is not None:
        return
    accents = [
        [1, 0.79, 0.04],
        [0.05, 0.48, 1],
        [0.62, 0.24, 0.96],
        [0.02, 0.82, 0.7],
        [1, 0.18, 0.54],
    ]
    tray = {
        "Name": "CurrencyTray",
        "ClassName": "Frame",
        "Properties": {
            "AnchorPoint": [0.5, 0],
            "BackgroundTransparency": 1,
            "BorderSizePixel": 0,
            "Position": {"UDim2": [[0.5, 0], [0, 18]]},
            "Size": {"UDim2": [[0.9, 0], [0, 88]]},
            "ZIndex": 7,
        },
        "Children": [
            {
                "ClassName": "UISizeConstraint",
                "Properties": {"MaxSize": [850, 88], "MinSize": [280, 88]},
                "Children": [],
            },
            {
                "Name": "Slots",
                "ClassName": "ScrollingFrame",
                "Properties": {
                    "AutomaticCanvasSize": "X",
                    "BackgroundTransparency": 1,
                    "BorderSizePixel": 0,
                    "CanvasSize": {"UDim2": [[0, 0], [0, 0]]},
                    "ScrollingDirection": "X",
                    "ScrollBarThickness": 0,
                    "Size": {"UDim2": [[1, 0], [0, 62]]},
                    "ZIndex": 7,
                },
                "Children": [
                    {
                        "ClassName": "UIListLayout",
                        "Properties": {
                            "FillDirection": "Horizontal",
                            "HorizontalAlignment": "Center",
                            "Padding": {"UDim": [0, 10]},
                            "SortOrder": "LayoutOrder",
                            "VerticalAlignment": "Top",
                        },
                        "Children": [],
                    },
                    *[currency_slot(i + 1, color) for i, color in enumerate(accents)],
                ],
            },
            {
                "Name": "BoostLabel",
                "ClassName": "TextLabel",
                "Properties": {
                    "AnchorPoint": [0.5, 0],
                    "BackgroundTransparency": 1,
                    "FontFace": {
                        "family": "rbxasset://fonts/families/Nunito.json",
                        "weight": "ExtraBold",
                        "style": "Normal",
                    },
                    "Position": {"UDim2": [[0.5, 0], [0, 66]]},
                    "Size": {"UDim2": [[0.9, 0], [0, 20]]},
                    "Text": "x1.00 BOOST  •  0 FRIENDS",
                    "TextColor3": [1, 1, 1],
                    "TextSize": 12,
                    "TextStrokeColor3": [0.025, 0.035, 0.09],
                    "TextStrokeTransparency": 0,
                    "ZIndex": 8,
                },
                "Children": [],
            },
        ],
    }
    root.setdefault("Children", []).append(tray)


def recolor_rpg(model: dict) -> None:
    replacements = {
        (0.4862745, 0.227451, 0.9294118): [0.27, 0.22, 0.46],
        (0.62, 0.24, 0.96): [0.38, 0.29, 0.64],
        (0.05, 0.48, 1.0): [0.16, 0.38, 0.68],
        (1.0, 0.79, 0.04): [0.89, 0.61, 0.12],
        (1.0, 0.18, 0.54): [0.66, 0.20, 0.31],
        (0.02, 0.82, 0.7): [0.12, 0.55, 0.42],
        (0.12, 0.9, 0.22): [0.25, 0.58, 0.28],
    }
    for node in walk(model):
        props = node.get("Properties", {})
        for key in ("BackgroundColor3", "TextColor3", "ImageColor3", "Color"):
            value = props.get(key)
            if isinstance(value, list) and len(value) == 3:
                rounded = tuple(round(float(item), 7) for item in value)
                for source, target in replacements.items():
                    if all(abs(rounded[i] - source[i]) < 0.00001 for i in range(3)):
                        props[key] = target
                        break

    root = model["Children"][0]
    nav = child(root, "Navigation")
    if nav:
        nav["Properties"].update(
            {
                "AnchorPoint": [0.5, 1],
                "Position": {"UDim2": [[0.5, 0], [0.76, 0]]},
                "Size": {"UDim2": [[0, 430], [0, 82]]},
            }
        )
        constraint = next((item for item in nav["Children"] if item.get("ClassName") == "UISizeConstraint"), None)
        if constraint:
            constraint["Properties"] = {"MaxSize": [520, 92], "MinSize": [300, 74]}
        buttons = child(nav, "Buttons")
        if buttons:
            buttons["Properties"].update(
                {
                    "AutomaticCanvasSize": "X",
                    "CanvasSize": {"UDim2": [[0, 0], [0, 0]]},
                    "ScrollingDirection": "X",
                }
            )
            grid = next((item for item in buttons["Children"] if item.get("ClassName") == "UIGridLayout"), None)
            if grid:
                grid["Properties"].update(
                    {
                        "CellPadding": {"UDim2": [[0, 8], [0, 0]]},
                        "CellSize": {"UDim2": [[0, 76], [0, 76]]},
                        "FillDirectionMaxCells": 5,
                    }
                )
    replacements_text = {
        "BAG": "INVENTORY",
        "SHOP": "MERCHANT",
        "PROFILE": "HERO",
        "MORE": "MENU",
        "MY BAG": "ADVENTURER INVENTORY",
    }
    for node in walk(model):
        props = node.get("Properties", {})
        if props.get("Text") in replacements_text:
            props["Text"] = replacements_text[props["Text"]]


def write_if_missing(path: Path, model: dict) -> None:
    if path.exists():
        print(f"kept existing {path.relative_to(ROOT)}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(model, ensure_ascii=False), encoding="utf-8")
    print(f"created {path.relative_to(ROOT)}")


def main() -> None:
    base = json.loads(BASE_UI.read_text(encoding="utf-8"))
    ensure_currency_tray(base)
    BASE_UI.write_text(json.dumps(base, ensure_ascii=False), encoding="utf-8")

    incremental = copy.deepcopy(base)
    rpg = copy.deepcopy(base)
    incremental.setdefault("Properties", {})["Enabled"] = False
    rpg.setdefault("Properties", {})["Enabled"] = False
    recolor_rpg(rpg)

    for preset, model in (("incremental", incremental), ("rpg", rpg)):
        folder = PRESETS / preset
        write_if_missing(folder / "TemplateUI.model.json", model)
        source_loading = UI / "TemplateLoading.model.json"
        source_sign = UI / "StarterSignUI.model.json"
        if source_loading.exists():
            loading = json.loads(source_loading.read_text(encoding="utf-8"))
            if preset == "rpg":
                recolor_rpg(loading)
            write_if_missing(folder / "TemplateLoading.model.json", loading)
        if source_sign.exists():
            sign = json.loads(source_sign.read_text(encoding="utf-8"))
            if preset == "rpg":
                recolor_rpg(sign)
            write_if_missing(folder / "StarterSignUI.model.json", sign)


if __name__ == "__main__":
    main()
