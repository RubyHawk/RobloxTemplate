#!/usr/bin/env python3
"""Apply the approved modern simulator layout to the independent Incremental UI pack.

The script edits only src/ui/presets/incremental/TemplateUI.model.json. It never
copies from, links to, or rewrites the RPG preset. All visuals remain authored
StarterGui instances; runtime code only binds data and interactions.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MODEL = ROOT / "src" / "ui" / "presets" / "incremental" / "TemplateUI.model.json"

INK = [0.018, 0.025, 0.055]
PANEL = [0.055, 0.061, 0.082]
PANEL_RAISED = [0.09, 0.098, 0.125]
WHITE = [1, 1, 1]
MUTED = [0.72, 0.75, 0.82]
GOLD = [1, 0.77, 0.12]
ORANGE = [0.93, 0.42, 0.12]
CYAN = [0.08, 0.72, 1]
GREEN = [0.18, 0.9, 0.34]
PINK = [1, 0.16, 0.42]
PURPLE = [0.58, 0.2, 0.96]

FREDOKA = {
    "family": "rbxasset://fonts/families/FredokaOne.json",
    "weight": "Regular",
    "style": "Normal",
}
NUNITO = {
    "family": "rbxasset://fonts/families/Nunito.json",
    "weight": "ExtraBold",
    "style": "Normal",
}


def name(node: dict) -> str:
    return node.get("Name") or node.get("Properties", {}).get("Name") or node.get("ClassName", "")


def find(node: dict, target: str) -> dict | None:
    if name(node) == target:
        return node
    for child in node.get("Children", []) or []:
        match = find(child, target)
        if match is not None:
            return match
    return None


def child(node: dict, target: str) -> dict | None:
    for item in node.get("Children", []) or []:
        if name(item) == target:
            return item
    return None


def child_class(node: dict, class_name: str) -> dict | None:
    for item in node.get("Children", []) or []:
        if item.get("ClassName") == class_name:
            return item
    return None


def props(node: dict) -> dict:
    return node.setdefault("Properties", {})


def udim2(xs: float, xo: int, ys: float, yo: int) -> dict:
    return {"UDim2": [[xs, xo], [ys, yo]]}


def corner(radius: int) -> dict:
    return {"ClassName": "UICorner", "Properties": {"CornerRadius": {"UDim": [0, radius]}}, "Children": []}


def stroke(color=INK, thickness: int = 3, transparency: float = 0) -> dict:
    return {
        "ClassName": "UIStroke",
        "Properties": {"Color": color, "Thickness": thickness, "Transparency": transparency},
        "Children": [],
    }


def text_label(node_name: str, text: str, size: int, color=WHITE, font=FREDOKA) -> dict:
    return {
        "Name": node_name,
        "ClassName": "TextLabel",
        "Properties": {
            "BackgroundTransparency": 1,
            "BorderSizePixel": 0,
            "FontFace": font,
            "Size": udim2(1, 0, 1, 0),
            "Text": text,
            "TextColor3": color,
            "TextSize": size,
            "TextStrokeColor3": INK,
            "TextStrokeTransparency": 0,
            "TextWrapped": True,
            "ZIndex": 83,
        },
        "Children": [],
    }


def set_stroke(node: dict, color=INK, thickness: int = 3, transparency: float = 0) -> None:
    value = child_class(node, "UIStroke")
    if value is None:
        value = stroke(color, thickness, transparency)
        node.setdefault("Children", []).append(value)
    else:
        props(value).update(Color=color, Thickness=thickness, Transparency=transparency)


def set_corner(node: dict, radius: int) -> None:
    value = child_class(node, "UICorner")
    if value is None:
        node.setdefault("Children", []).append(corner(radius))
    else:
        props(value)["CornerRadius"] = {"UDim": [0, radius]}


def restyle_navigation(root: dict) -> None:
    nav = find(root, "Navigation")
    buttons = child(nav, "Buttons")
    layout = child_class(buttons, "UIGridLayout")
    constraint = child_class(nav, "UISizeConstraint")
    props(nav).update(
        AnchorPoint=[0.5, 1],
        Position=udim2(0.5, 0, 1, -14),
        Size=udim2(0, 470, 0, 82),
        BackgroundColor3=PANEL,
        BackgroundTransparency=0.12,
        BorderSizePixel=0,
        ClipsDescendants=False,
    )
    set_corner(nav, 22)
    set_stroke(nav, INK, 4)
    props(constraint).update(MaxSize=[470, 88], MinSize=[280, 78])
    props(buttons).update(
        AutomaticCanvasSize="X",
        CanvasSize=udim2(0, 0, 0, 0),
        ScrollingDirection="X",
        ScrollBarThickness=0,
        Size=udim2(1, -16, 1, -8),
        Position=udim2(0, 8, 0, 4),
    )
    props(layout).update(
        CellPadding=udim2(0, 8, 0, 0),
        CellSize=udim2(0, 82, 0, 74),
        FillDirection="Horizontal",
        FillDirectionMaxCells=5,
        HorizontalAlignment="Center",
        VerticalAlignment="Center",
    )

    colors = [ORANGE, CYAN, PURPLE, GOLD, GREEN]
    labels = ["BAG", "SHOP", "REWARDS", "PROFILE", "MORE"]
    for index, button_name in enumerate(["BagButton", "ShopButton", "GiftButton", "ProfileButton", "MoreButton"]):
        button = child(buttons, button_name)
        bubble = child(button, "IconBubble")
        label = child(button, "Label")
        props(button).update(Size=udim2(0, 82, 0, 74), BackgroundTransparency=1, Text="")
        props(bubble).update(
            AnchorPoint=[0.5, 0],
            Position=udim2(0.5, 0, 0, 0),
            Size=udim2(0, 58, 0, 58),
            BackgroundColor3=colors[index],
            BackgroundTransparency=0,
            ZIndex=12,
        )
        set_corner(bubble, 15)
        set_stroke(bubble, INK, 4)
        props(label).update(
            Position=udim2(0, -8, 0, 52),
            Size=udim2(1, 16, 0, 22),
            Text=labels[index],
            TextColor3=WHITE,
            TextSize=13,
            FontFace=FREDOKA,
            TextStrokeColor3=INK,
            TextStrokeTransparency=0,
            ZIndex=13,
        )


def restyle_currency_tray(root: dict) -> None:
    tray = find(root, "CurrencyTray")
    slots = child(tray, "Slots")
    layout = child_class(slots, "UIListLayout")
    constraint = child_class(tray, "UISizeConstraint")
    boost = child(tray, "BoostLabel")
    props(tray).update(
        AnchorPoint=[1, 0.5],
        Position=udim2(1, -16, 0.5, 0),
        Size=udim2(0, 178, 0, 348),
        BackgroundTransparency=1,
    )
    props(constraint).update(MaxSize=[190, 348], MinSize=[160, 88])
    props(slots).update(
        AutomaticCanvasSize="Y",
        CanvasSize=udim2(0, 0, 0, 0),
        ScrollingDirection="Y",
        ScrollBarThickness=0,
        Size=udim2(1, 0, 1, 0),
    )
    props(layout).update(
        FillDirection="Vertical",
        HorizontalAlignment="Right",
        VerticalAlignment="Center",
        Padding={"UDim": [0, 8]},
    )
    props(boost).update(Visible=False)
    for index in range(1, 6):
        slot = child(slots, f"CurrencySlot{index:02d}")
        accent = child(slot, "Accent")
        amount = child(slot, "AmountLabel")
        caption = child(slot, "Caption")
        symbol = child(slot, "Symbol")
        icon = child(slot, "Icon")
        props(slot).update(Size=udim2(0, 168, 0, 56), BackgroundColor3=PANEL, BackgroundTransparency=0.08)
        set_corner(slot, 15)
        set_stroke(slot, INK, 3)
        props(accent).update(Position=udim2(0, 5, 0, 5), Size=udim2(0, 46, 0, 46))
        set_corner(accent, 13)
        props(symbol).update(Position=udim2(0, 5, 0, 5), Size=udim2(0, 46, 0, 46), TextColor3=WHITE)
        props(icon).update(Position=udim2(0, 8, 0, 8), Size=udim2(0, 40, 0, 40))
        props(amount).update(
            Position=udim2(0, 58, 0, 2), Size=udim2(1, -64, 0, 31), TextColor3=WHITE,
            TextSize=20, FontFace=FREDOKA, TextStrokeColor3=INK, TextStrokeTransparency=0,
        )
        props(caption).update(
            Position=udim2(0, 59, 0, 31), Size=udim2(1, -65, 0, 18), TextColor3=MUTED,
            TextSize=10, FontFace=NUNITO, TextStrokeTransparency=1,
        )


def category_button(button_name: str, label: str, fallback: str, color) -> dict:
    return {
        "Name": button_name,
        "ClassName": "TextButton",
        "Properties": {
            "AutoButtonColor": False,
            "BackgroundColor3": PANEL_RAISED,
            "BorderSizePixel": 0,
            "LayoutOrder": 1,
            "Size": udim2(0, 82, 0, 76),
            "Text": "",
            "ZIndex": 48,
        },
        "Children": [
            corner(14),
            stroke(color, 3),
            {
                "Name": "Icon",
                "ClassName": "ImageLabel",
                "Properties": {
                    "BackgroundTransparency": 1,
                    "Image": "",
                    "Position": udim2(0.5, -19, 0, 7),
                    "Size": udim2(0, 38, 0, 38),
                    "ScaleType": "Fit",
                    "Visible": False,
                    "ZIndex": 49,
                },
                "Children": [],
            },
            {
                "Name": "Fallback",
                "ClassName": "TextLabel",
                "Properties": {
                    "BackgroundTransparency": 1,
                    "FontFace": FREDOKA,
                    "Position": udim2(0.5, -19, 0, 7),
                    "Size": udim2(0, 38, 0, 38),
                    "Text": fallback,
                    "TextColor3": color,
                    "TextSize": 24,
                    "ZIndex": 49,
                },
                "Children": [],
            },
            {
                "Name": "Label",
                "ClassName": "TextLabel",
                "Properties": {
                    "BackgroundTransparency": 1,
                    "FontFace": FREDOKA,
                    "Position": udim2(0, 4, 0, 47),
                    "Size": udim2(1, -8, 0, 23),
                    "Text": label,
                    "TextColor3": WHITE,
                    "TextSize": 12,
                    "TextStrokeColor3": INK,
                    "TextStrokeTransparency": 0,
                    "ZIndex": 49,
                },
                "Children": [],
            },
        ],
    }


def restyle_inventory(root: dict) -> None:
    screen = find(root, "InventoryScreen")
    header = child(screen, "Header")
    title = child(screen, "Title")
    close = child(screen, "CloseButton")
    close_shadow = child(screen, "CloseButtonShadow")
    header_icon = child(screen, "HeaderIcon")
    panel_badge = child(screen, "PanelBadge")
    constraint = child_class(screen, "UISizeConstraint")
    content = child(screen, "Content")
    toolbar = child(content, "Toolbar")
    search = child(toolbar, "SearchInput")
    category = child(toolbar, "CategoryButton")
    category_shadow = child(toolbar, "CategoryButtonShadow")
    empty = child(content, "EmptyState")
    grid = child(content, "ItemsGrid")
    grid_layout = child_class(grid, "UIGridLayout")

    props(screen).update(
        Position=udim2(0.5, 0, 0.5, 0),
        Size=udim2(0.88, 0, 0.82, 0),
        BackgroundColor3=PANEL,
        BackgroundTransparency=0.02,
        ClipsDescendants=False,
    )
    set_corner(screen, 12)
    set_stroke(screen, INK, 5)
    props(constraint).update(MaxSize=[820, 620], MinSize=[300, 300])
    props(header).update(
        Position=udim2(0, 16, 0, -18),
        Size=udim2(0.62, 0, 0, 68),
        BackgroundColor3=ORANGE,
        Rotation=-2,
        ZIndex=45,
    )
    set_corner(header, 12)
    set_stroke(header, INK, 4)
    gradient = child_class(header, "UIGradient")
    if gradient is None:
        header["Children"].insert(0, {
            "Name": "HeaderSheen",
            "ClassName": "UIGradient",
            "Properties": {
                "Color": {"ColorSequence": {"keypoints": [
                    {"time": 0, "color": [1, 0.62, 0.3]},
                    {"time": 1, "color": [0.72, 0.22, 0.06]},
                ]}},
                "Rotation": 90,
            },
            "Children": [],
        })
    props(title).update(
        Position=udim2(0, 82, 0, -10),
        Size=udim2(0.55, 0, 0, 46),
        Text="INVENTORY",
        TextColor3=WHITE,
        TextSize=30,
        TextXAlignment="Left",
        FontFace=FREDOKA,
        TextStrokeColor3=INK,
        TextStrokeTransparency=0,
        ZIndex=47,
    )
    props(header_icon).update(Position=udim2(0, 28, 0, -7), Size=udim2(0, 48, 0, 48), ZIndex=47)
    props(close).update(
        Position=udim2(1, 13, 0, -18), Size=udim2(0, 58, 0, 58), Rotation=6,
        BackgroundColor3=PINK, Text="X", TextSize=26, ZIndex=49,
    )
    props(close_shadow).update(Position=udim2(1, 13, 0, -12), Size=udim2(0, 58, 0, 58), Rotation=6, ZIndex=48)
    set_corner(close, 13)
    set_stroke(close, INK, 4)
    props(panel_badge)["Visible"] = False

    if child(screen, "CategoryTabs") is None:
        tabs = {
            "Name": "CategoryTabs",
            "ClassName": "Frame",
            "Properties": {
                "BackgroundTransparency": 1,
                "Position": udim2(0, -18, 0, 74),
                "Size": udim2(0, 92, 1, -92),
                "ZIndex": 47,
            },
            "Children": [
                {
                    "ClassName": "UIListLayout",
                    "Properties": {"FillDirection": "Vertical", "Padding": {"UDim": [0, 8]}, "SortOrder": "LayoutOrder"},
                    "Children": [],
                },
                category_button("AllButton", "ALL", "A", GOLD),
                category_button("ConsumableButton", "BOOSTS", "B", PURPLE),
                category_button("EquipmentButton", "GEAR", "G", CYAN),
                category_button("MiscButton", "MISC", "M", GREEN),
            ],
        }
        for order, tab in enumerate(tabs["Children"][1:], 1):
            props(tab)["LayoutOrder"] = order
        screen.setdefault("Children", []).append(tabs)

    props(content).update(
        Position=udim2(0, 92, 0, 66),
        Size=udim2(1, -104, 1, -78),
        BackgroundColor3=PANEL,
        BackgroundTransparency=1,
        CanvasSize=udim2(0, 0, 0, 0),
        AutomaticCanvasSize="Y",
        ScrollBarThickness=5,
        ScrollBarImageColor3=ORANGE,
    )
    props(toolbar).update(Size=udim2(1, 0, 0, 50), BackgroundTransparency=1)
    props(search).update(
        Position=udim2(0, 0, 0, 0), Size=udim2(1, 0, 0, 46),
        BackgroundColor3=PANEL_RAISED, TextColor3=WHITE, PlaceholderColor3=MUTED,
        PlaceholderText="SEARCH YOUR ITEMS...", TextSize=15,
    )
    set_corner(search, 12)
    set_stroke(search, [0.24, 0.27, 0.34], 2)
    props(category).update(Visible=False)
    props(category_shadow).update(Visible=False)
    props(empty).update(Position=udim2(0, 0, 0, 62), BackgroundColor3=PANEL_RAISED)
    set_stroke(empty, [0.24, 0.27, 0.34], 2)
    for label_name in ["Title", "Body"]:
        label = child(empty, label_name)
        props(label)["TextColor3"] = WHITE if label_name == "Title" else MUTED
    props(grid).update(Position=udim2(0, 0, 0, 62), Size=udim2(1, 0, 0, 544))
    props(grid_layout).update(
        CellPadding=udim2(0, 10, 0, 10),
        CellSize=udim2(0.25, -8, 0, 174),
        FillDirectionMaxCells=4,
        HorizontalAlignment="Center",
    )

    rarity = [GOLD, PURPLE, GREEN, ORANGE, PINK, CYAN]
    for index in range(1, 13):
        slot = child(grid, f"ItemSlot{index:02d}")
        art = child(slot, "Artwork")
        slot_title = child(slot, "Title")
        body = child(slot, "Body")
        quantity = child(slot, "Quantity")
        action = child(slot, "ActionButton")
        action_shadow = child(slot, "ActionButtonShadow")
        color = rarity[(index - 1) % len(rarity)]
        props(slot).update(Size=udim2(1, 0, 0, 174), BackgroundColor3=PANEL_RAISED, BackgroundTransparency=0)
        set_corner(slot, 12)
        set_stroke(slot, color, 3)
        props(art).update(
            AnchorPoint=[0.5, 0], Position=udim2(0.5, 0, 0, 8), Size=udim2(0, 88, 0, 88),
            BackgroundColor3=[0.025, 0.03, 0.045], BackgroundTransparency=0,
        )
        set_corner(art, 11)
        set_stroke(art, color, 2)
        props(slot_title).update(
            Position=udim2(0, 6, 0, 96), Size=udim2(1, -12, 0, 25), TextColor3=WHITE,
            TextSize=14, FontFace=FREDOKA, TextStrokeColor3=INK, TextStrokeTransparency=0,
        )
        props(body).update(Visible=False)
        props(quantity).update(
            Position=udim2(0, 7, 1, -40), Size=udim2(0.35, -5, 0, 28), TextColor3=WHITE,
            TextSize=14, FontFace=FREDOKA, TextStrokeColor3=INK, TextStrokeTransparency=0,
        )
        props(action_shadow).update(Position=udim2(0.35, 0, 1, -35), Size=udim2(0.65, -7, 0, 30))
        props(action).update(
            Position=udim2(0.35, 0, 1, -38), Size=udim2(0.65, -7, 0, 30),
            BackgroundColor3=GREEN, TextSize=13,
        )
        set_corner(action, 9)


def boost_row(row_name: str, label: str, value_name: str, value: str, y: int) -> list[dict]:
    label_node = text_label(row_name, label, 15, WHITE, NUNITO)
    props(label_node).update(Position=udim2(0, 16, 0, y), Size=udim2(0.65, -16, 0, 28), TextXAlignment="Left")
    value_node = text_label(value_name, value, 16, GOLD, FREDOKA)
    props(value_node).update(Position=udim2(0.65, 0, 0, y), Size=udim2(0.35, -16, 0, 28), TextXAlignment="Right")
    return [label_node, value_node]


def add_boost_panel(root: dict) -> None:
    if child(root, "BoostPanel") is not None:
        return
    details_children = [corner(12), stroke(INK, 4)]
    details_children += boost_row("FriendsLabel", "Friends Boost", "FriendsValue", "+0%", 48)
    details_children += boost_row("PremiumLabel", "Premium Boost", "PremiumValue", "+0%", 80)
    details_children += boost_row("PotionLabel", "Potion", "PotionValue", "x1", 112)
    details_children += boost_row("TotalLabel", "TOTAL", "TotalValue", "x1.00", 154)
    details_children.append({
        "Name": "Divider",
        "ClassName": "Frame",
        "Properties": {"BackgroundColor3": [0.24, 0.27, 0.34], "BorderSizePixel": 0, "Position": udim2(0, 14, 0, 144), "Size": udim2(1, -28, 0, 2), "ZIndex": 29},
        "Children": [],
    })
    details_children.append(text_label("Heading", "BOOST BREAKDOWN", 18, GOLD, FREDOKA))
    props(details_children[-1]).update(Position=udim2(0, 14, 0, 12), Size=udim2(1, -28, 0, 28), TextXAlignment="Left")
    root.setdefault("Children", []).append({
        "Name": "BoostPanel",
        "ClassName": "Frame",
        "Properties": {
            "AnchorPoint": [0, 0.5], "BackgroundTransparency": 1,
            "Position": udim2(0, 16, 0.58, 0), "Size": udim2(0, 226, 0, 52), "ZIndex": 26,
        },
        "Children": [
            {
                "Name": "SummaryButton",
                "ClassName": "TextButton",
                "Properties": {
                    "AutoButtonColor": False, "BackgroundColor3": PANEL, "BackgroundTransparency": 0.08,
                    "BorderSizePixel": 0, "Size": udim2(1, 0, 0, 52), "Text": "", "ZIndex": 27,
                },
                "Children": [
                    corner(12), stroke(INK, 4),
                    {"Name": "Icon", "ClassName": "ImageLabel", "Properties": {"BackgroundTransparency": 1, "Image": "", "Position": udim2(0, 8, 0, 7), "Size": udim2(0, 38, 0, 38), "ScaleType": "Fit", "ZIndex": 28}, "Children": []},
                    text_label("Label", "ACTIVE BOOSTS", 13, MUTED, NUNITO),
                    text_label("Value", "x1.00", 21, GOLD, FREDOKA),
                ],
            },
            {
                "Name": "Details",
                "ClassName": "Frame",
                "Properties": {
                    "BackgroundColor3": PANEL, "BackgroundTransparency": 0.04, "BorderSizePixel": 0,
                    "Position": udim2(0, 0, 0, 60), "Size": udim2(1, 0, 0, 194), "Visible": False, "ZIndex": 28,
                },
                "Children": details_children,
            },
        ],
    })
    panel = child(root, "BoostPanel")
    summary = child(panel, "SummaryButton")
    props(child(summary, "Label")).update(Position=udim2(0, 52, 0, 5), Size=udim2(1, -60, 0, 18), TextXAlignment="Left", TextStrokeTransparency=1)
    props(child(summary, "Value")).update(Position=udim2(0, 52, 0, 21), Size=udim2(1, -60, 0, 25), TextXAlignment="Left")


def main() -> None:
    data = json.loads(MODEL.read_text(encoding="utf-8"))
    root = find(data, "Root")
    if root is None:
        raise RuntimeError("Incremental model is missing Root")
    restyle_navigation(root)
    restyle_currency_tray(root)
    restyle_inventory(root)
    add_boost_panel(root)
    MODEL.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    print(f"Restyled {MODEL}")


if __name__ == "__main__":
    main()
