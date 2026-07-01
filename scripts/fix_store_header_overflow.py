#!/usr/bin/env python3
"""Fix StoreScreen/Content/StoreHeader: its Body label is authored with a
44px-tall box (enough for the description to wrap to 2 lines at narrow
modal widths, e.g. phone-sized screens), but the header Frame around it was
only 60px tall - 32px short of Title(34@y=12) + Body(44@y=48) = 92. On wide
viewports the description fits on one line and nothing looks wrong; once it
wraps to 2 lines (only happens at narrow/phone modal widths) the second
line visibly spills out of the yellow header past its own parent's bottom
edge. Found via mechanical device-size rendering, not present at
tablet/laptop widths where the sentence never wraps.

Grows the header to fit both lines, then shifts ProductsGrid and the
ScrollingFrame's CanvasSize down/taller by the same delta so the gap below
the header and the scrollable range stay consistent - not just a header
resize in isolation.

Usage: python3 scripts/fix_store_header_overflow.py
"""

import json
import pathlib

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
MODEL_PATH = REPO_ROOT / "src" / "ui" / "TemplateUI.model.json"

OLD_HEADER_H = 60
NEW_HEADER_H = 100
DELTA = NEW_HEADER_H - OLD_HEADER_H


def name_of(node):
    return node.get("Name") or (node.get("Properties", {}) or {}).get("Name")


def find_child_named(node, name):
    for c in node.get("Children", []) or []:
        if name_of(c) == name:
            return c
    return None


def find_path(node, target_name, path="ROOT"):
    n = name_of(node)
    here = f"{path}/{n}" if n else path
    if n == target_name:
        yield here, node
    for c in node.get("Children", []) or []:
        yield from find_path(c, target_name, here)


def main():
    with open(MODEL_PATH, encoding="utf-8") as f:
        data = json.load(f)

    root = data["Children"][0]
    fixed = 0
    for path, store_screen in find_path(root, "StoreScreen"):
        if "ShowcaseCanvas" in path:
            continue
        content = find_child_named(store_screen, "Content")
        if content is None:
            continue
        header = find_child_named(content, "StoreHeader")
        grid = find_child_named(content, "ProductsGrid")
        if header is None or grid is None:
            continue

        header_size = header["Properties"]["Size"]["UDim2"]
        assert header_size[1] == [0, OLD_HEADER_H], f"unexpected header height {header_size}"
        header["Properties"]["Size"] = {"UDim2": [header_size[0], [0, NEW_HEADER_H]]}

        grid_pos = grid["Properties"]["Position"]["UDim2"]
        grid["Properties"]["Position"] = {"UDim2": [grid_pos[0], [0, grid_pos[1][1] + DELTA]]}

        content_props = content["Properties"]
        canvas = content_props.get("CanvasSize", {}).get("UDim2")
        if canvas is not None:
            content_props["CanvasSize"] = {"UDim2": [canvas[0], [0, canvas[1][1] + DELTA]]}

        fixed += 1

    with open(MODEL_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)

    print("fixed StoreHeader instances:", fixed)


if __name__ == "__main__":
    main()
