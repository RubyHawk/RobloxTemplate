#!/usr/bin/env python3
"""Render a Rojo UI .model.json into a static SVG preview.

This lets us eyeball a preset's authored StarterGui layout without opening
Roblox Studio. It approximates the Roblox 2D layout engine: UDim2 position and
size, AnchorPoint, UIListLayout / UIGridLayout, UIPadding, UICorner, UIStroke,
and a two-stop UIGradient. Images are drawn as labelled placeholders because
Roblox asset bitmaps cannot be fetched here (the same reason the Figma bridge
shows image placeholders).

Usage:
    python3 scripts/render_ui_preview.py <model.json> <out.svg> [WIDTHxHEIGHT]
"""

from __future__ import annotations

import html
import json
import sys
from pathlib import Path


def prop(node, name, fallback=None):
    return (node.get("Properties") or {}).get(name, fallback)


def rgb(value, fallback=(255, 255, 255)):
    if isinstance(value, list) and len(value) == 3:
        return tuple(max(0, min(255, round(float(c) * 255))) for c in value)
    return fallback


def hexcolor(value, fallback=(255, 255, 255)):
    r, g, b = rgb(value, fallback)
    return f"#{r:02x}{g:02x}{b:02x}"


def udim2(value):
    raw = value.get("UDim2") if isinstance(value, dict) else None
    if not raw:
        return (0, 0, 0, 0)
    return (float(raw[0][0]), float(raw[0][1]), float(raw[1][0]), float(raw[1][1]))


def udim(value, fallback=(0, 0)):
    raw = value.get("UDim") if isinstance(value, dict) else None
    if not raw:
        return fallback
    return (float(raw[0]), float(raw[1]))


def child_of_class(node, class_name):
    for c in node.get("Children") or []:
        if c.get("ClassName") == class_name:
            return c
    return None


def children_of_class(node, class_name):
    return [c for c in node.get("Children") or [] if c.get("ClassName") == class_name]


def is_visual(node):
    return node.get("ClassName") in {
        "Frame", "ScrollingFrame", "CanvasGroup", "TextLabel", "TextButton",
        "TextBox", "ImageLabel", "ImageButton", "ViewportFrame", "VideoFrame",
    }


def resolve_rect(node, parent):
    """Absolute (x, y, w, h) for a node inside parent rect (px, py, pw, ph)."""
    px, py, pw, ph = parent
    sxs, sxo, sys_, syo = udim2(prop(node, "Size", {"UDim2": [[0, 0], [0, 0]]}))
    w = sxs * pw + sxo
    h = sys_ * ph + syo
    pxs, pxo, pys, pyo = udim2(prop(node, "Position", {"UDim2": [[0, 0], [0, 0]]}))
    x = px + pxs * pw + pxo
    y = py + pys * ph + pyo
    anchor = prop(node, "AnchorPoint", [0, 0])
    ax, ay = (float(anchor[0]), float(anchor[1])) if isinstance(anchor, list) else (0, 0)
    x -= ax * w
    y -= ay * h
    return (x, y, w, h)


def apply_padding(rect, node):
    pad = child_of_class(node, "UIPadding")
    if not pad:
        return rect
    x, y, w, h = rect

    def px_of(name):
        s, o = udim(prop(pad, name, {"UDim": [0, 0]}))
        return s * (w if "Left" in name or "Right" in name else h) + o

    l = px_of("PaddingLeft")
    r = px_of("PaddingRight")
    t = px_of("PaddingTop")
    b = px_of("PaddingBottom")
    return (x + l, y + t, w - l - r, h - t - b)


def corner_radius(node):
    c = child_of_class(node, "UICorner")
    if not c:
        return 0
    s, o = udim(prop(c, "CornerRadius", {"UDim": [0, 0]}))
    return o  # scale radius is rare here; offset dominates


class Renderer:
    def __init__(self):
        self.parts = []
        self.defs = []
        self.grad_id = 0

    def text(self, node, rect):
        x, y, w, h = rect
        raw = prop(node, "Text", "")
        if raw is None or str(raw) == "":
            return
        text = html.escape(str(raw))
        size = float(prop(node, "TextSize", 18) or 18)
        color = hexcolor(prop(node, "TextColor3", [0, 0, 0]), (0, 0, 0))
        xalign = str(prop(node, "TextXAlignment", "Center"))
        wrapped = prop(node, "TextWrapped", False)
        face = prop(node, "FontFace", {})
        family = ""
        if isinstance(face, dict):
            family = str(face.get("family", ""))
        weight = "700"
        if "FredokaOne" in family:
            weight = "800"
        anchor = {"Left": "start", "Center": "middle", "Right": "end"}.get(xalign, "middle")
        if anchor == "start":
            tx = x + 4
        elif anchor == "end":
            tx = x + w - 4
        else:
            tx = x + w / 2
        stroke_t = prop(node, "TextStrokeTransparency", 1)
        stroke = ""
        if stroke_t is not None and float(stroke_t) < 0.95:
            sc = hexcolor(prop(node, "TextStrokeColor3", [0, 0, 0]), (0, 0, 0))
            stroke = f' stroke="{sc}" stroke-width="{max(1, size*0.09):.1f}" paint-order="stroke"'
        # crude single-line vertical centering; multi-line text just anchors near middle
        ty = y + h / 2 + size * 0.34
        display = text
        if wrapped and len(display) > 0:
            # approximate wrap: cap characters per line to width
            max_chars = max(6, int(w / (size * 0.52)))
            if len(display) > max_chars:
                words = display.split(" ")
                lines, cur = [], ""
                for word in words:
                    if len(cur) + len(word) + 1 <= max_chars:
                        cur = (cur + " " + word).strip()
                    else:
                        lines.append(cur)
                        cur = word
                if cur:
                    lines.append(cur)
                lines = lines[:3]
                total = len(lines)
                start_y = y + h / 2 - (total - 1) * size * 0.62 + size * 0.34
                for i, line in enumerate(lines):
                    self.parts.append(
                        f'<text x="{tx:.1f}" y="{start_y + i*size*1.24:.1f}" font-size="{size:.0f}" '
                        f'font-weight="{weight}" fill="{color}" text-anchor="{anchor}"'
                        f' font-family="Nunito, Verdana, sans-serif"{stroke}>{html.escape(line)}</text>'
                    )
                return
        self.parts.append(
            f'<text x="{tx:.1f}" y="{ty:.1f}" font-size="{size:.0f}" font-weight="{weight}" '
            f'fill="{color}" text-anchor="{anchor}" font-family="Nunito, Verdana, sans-serif"'
            f'{stroke}>{display}</text>'
        )

    def gradient_fill(self, node, rect):
        grad = child_of_class(node, "UIGradient")
        if not grad:
            return None
        seq = prop(grad, "Color", None)
        stops = []
        # Rojo stores a ColorSequence as {"ColorSequence": {"keypoints": [...]}}
        keypoints = None
        if isinstance(seq, dict):
            if "ColorSequence" in seq and isinstance(seq["ColorSequence"], dict):
                keypoints = seq["ColorSequence"].get("keypoints") or seq["ColorSequence"].get("Keypoints")
            elif "Keypoints" in seq:
                keypoints = seq["Keypoints"]
            elif "keypoints" in seq:
                keypoints = seq["keypoints"]
        if keypoints:
            for kp in keypoints:
                t = float(kp.get("Time", kp.get("time", 0)))
                col = kp.get("Color") or kp.get("color") or kp.get("Value")
                stops.append((t, hexcolor(col, (255, 255, 255))))
        if len(stops) < 2:
            return None
        rot = float(prop(grad, "Rotation", 0) or 0)
        self.grad_id += 1
        gid = f"g{self.grad_id}"
        import math
        rad = math.radians(rot)
        x1 = 50 - math.cos(rad) * 50
        y1 = 50 - math.sin(rad) * 50
        x2 = 50 + math.cos(rad) * 50
        y2 = 50 + math.sin(rad) * 50
        stop_svg = "".join(
            f'<stop offset="{t*100:.0f}%" stop-color="{c}"/>' for t, c in stops
        )
        self.defs.append(
            f'<linearGradient id="{gid}" x1="{x1:.0f}%" y1="{y1:.0f}%" x2="{x2:.0f}%" y2="{y2:.0f}%">{stop_svg}</linearGradient>'
        )
        return f"url(#{gid})"

    def draw(self, node, parent_rect, depth=0):
        if prop(node, "Visible", True) is False:
            return
        cls = node.get("ClassName")
        if not is_visual(node):
            return
        rect = resolve_rect(node, parent_rect)
        x, y, w, h = rect
        if w <= 0 or h <= 0:
            # still recurse (layout containers may size children), but nothing to draw
            pass
        r = corner_radius(node)
        bg_t = prop(node, "BackgroundTransparency", 0)
        bg_t = float(bg_t) if bg_t is not None else 0.0
        if bg_t < 0.999 and w > 0 and h > 0:
            fill = self.gradient_fill(node, rect) or hexcolor(prop(node, "BackgroundColor3", [255, 255, 255]))
            opacity = 1 - bg_t
            self.parts.append(
                f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r:.0f}" '
                f'fill="{fill}" fill-opacity="{opacity:.2f}"/>'
            )
        # stroke
        stroke = child_of_class(node, "UIStroke")
        if stroke and w > 0 and h > 0:
            st = float(prop(stroke, "Transparency", 0) or 0)
            if st < 0.98:
                sc = hexcolor(prop(stroke, "Color", [0, 0, 0]), (0, 0, 0))
                sw = float(prop(stroke, "Thickness", 1) or 1)
                self.parts.append(
                    f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r:.0f}" '
                    f'fill="none" stroke="{sc}" stroke-width="{sw:.1f}" stroke-opacity="{1-st:.2f}"/>'
                )
        # image placeholder
        if cls in {"ImageLabel", "ImageButton"} and w > 0 and h > 0:
            img_t = float(prop(node, "ImageTransparency", 0) or 0)
            if img_t < 0.98 and prop(node, "Image", "") not in ("", None):
                icol = hexcolor(prop(node, "ImageColor3", [255, 255, 255]))
                self.parts.append(
                    f'<rect x="{x+2:.1f}" y="{y+2:.1f}" width="{max(0,w-4):.1f}" height="{max(0,h-4):.1f}" '
                    f'rx="{max(0,r-2):.0f}" fill="{icol}" fill-opacity="0.18"/>'
                )
        # text
        if cls in {"TextLabel", "TextButton", "TextBox"}:
            self.text(node, rect)

        # children, honoring a layout if present
        content_rect = apply_padding(rect, node)
        self.layout_children(node, content_rect, depth)

    def layout_children(self, node, content_rect, depth):
        kids = [c for c in (node.get("Children") or []) if is_visual(c)]
        kids = [c for c in kids if prop(c, "Visible", True) is not False]
        # ZIndex ordering (stable)
        kids.sort(key=lambda c: float(prop(c, "ZIndex", 1) or 1))
        grid = child_of_class(node, "UIGridLayout")
        lst = child_of_class(node, "UIListLayout")
        cx, cy, cw, ch = content_rect
        if grid:
            cs = udim2(prop(grid, "CellSize", {"UDim2": [[0, 100], [0, 100]]}))
            cp = udim2(prop(grid, "CellPadding", {"UDim2": [[0, 0], [0, 0]]}))
            cell_w = cs[0] * cw + cs[1]
            cell_h = cs[2] * ch + cs[3]
            pad_x = cp[1]
            pad_y = cp[3]
            per_row = max(1, int((cw + pad_x) // max(1, (cell_w + pad_x))))
            for i, c in enumerate(kids):
                col = i % per_row
                row = i // per_row
                gx = cx + col * (cell_w + pad_x)
                gy = cy + row * (cell_h + pad_y)
                self.draw_in_cell(c, (gx, gy, cell_w, cell_h), depth + 1)
            return
        if lst:
            direction = str(prop(lst, "FillDirection", "Vertical"))
            pad = udim(prop(lst, "Padding", {"UDim": [0, 0]}))[1]
            horiz_align = str(prop(lst, "HorizontalAlignment", "Left"))
            vert_align = str(prop(lst, "VerticalAlignment", "Top"))
            offset = 0
            for c in kids:
                r = resolve_rect(c, content_rect)
                cwid, chei = r[2], r[3]
                if direction == "Horizontal":
                    gx = cx + offset
                    if vert_align == "Center":
                        gy = cy + (ch - chei) / 2
                    elif vert_align == "Bottom":
                        gy = cy + ch - chei
                    else:
                        gy = cy
                    self.draw_placed(c, (gx, gy, cwid, chei), depth + 1)
                    offset += cwid + pad
                else:
                    gy = cy + offset
                    if horiz_align == "Center":
                        gx = cx + (cw - cwid) / 2
                    elif horiz_align == "Right":
                        gx = cx + cw - cwid
                    else:
                        gx = cx
                    self.draw_placed(c, (gx, gy, cwid, chei), depth + 1)
                    offset += chei + pad
            return
        # absolute
        for c in kids:
            self.draw(c, content_rect, depth + 1)

    def draw_in_cell(self, node, cell_rect, depth):
        # node fills the grid cell
        self._draw_at(node, cell_rect, depth)

    def draw_placed(self, node, rect, depth):
        self._draw_at(node, rect, depth)

    def _draw_at(self, node, rect, depth):
        # Draw a node whose absolute rect is already computed (layout-driven).
        x, y, w, h = rect
        cls = node.get("ClassName")
        r = corner_radius(node)
        bg_t = prop(node, "BackgroundTransparency", 0)
        bg_t = float(bg_t) if bg_t is not None else 0.0
        if bg_t < 0.999 and w > 0 and h > 0:
            fill = self.gradient_fill(node, rect) or hexcolor(prop(node, "BackgroundColor3", [255, 255, 255]))
            self.parts.append(
                f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r:.0f}" '
                f'fill="{fill}" fill-opacity="{1-bg_t:.2f}"/>'
            )
        stroke = child_of_class(node, "UIStroke")
        if stroke and w > 0 and h > 0:
            st = float(prop(stroke, "Transparency", 0) or 0)
            if st < 0.98:
                sc = hexcolor(prop(stroke, "Color", [0, 0, 0]), (0, 0, 0))
                sw = float(prop(stroke, "Thickness", 1) or 1)
                self.parts.append(
                    f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r:.0f}" '
                    f'fill="none" stroke="{sc}" stroke-width="{sw:.1f}" stroke-opacity="{1-st:.2f}"/>'
                )
        if cls in {"ImageLabel", "ImageButton"} and prop(node, "Image", "") not in ("", None) and w > 0:
            icol = hexcolor(prop(node, "ImageColor3", [255, 255, 255]))
            self.parts.append(
                f'<rect x="{x+2:.1f}" y="{y+2:.1f}" width="{max(0,w-4):.1f}" height="{max(0,h-4):.1f}" '
                f'rx="{max(0,r-2):.0f}" fill="{icol}" fill-opacity="0.18"/>'
            )
        if cls in {"TextLabel", "TextButton", "TextBox"}:
            self.text(node, rect)
        content_rect = apply_padding(rect, node)
        self.layout_children(node, content_rect, depth)


def find(node, name):
    for c in node.get("Children") or []:
        if c.get("Name") == name:
            return c
    return None


def render(model_path, out_path, size):
    W, H = size
    with open(model_path, encoding="utf-8") as f:
        model = json.load(f)
    r = Renderer()
    # Draw every top-level child of the container (ScreenGui, BillboardGui, ...)
    # so multi-root models (e.g. a sign's Shadow + Card) render fully, not just
    # the first branch.
    for child_node in model.get("Children", []) or []:
        r.draw(child_node, (0, 0, W, H), 0)
    defs = "".join(r.defs)
    body = "\n".join(r.parts)
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
        f'viewBox="0 0 {W} {H}">\n<defs>{defs}</defs>\n'
        f'<rect width="{W}" height="{H}" fill="#0a1230"/>\n{body}\n</svg>\n'
    )
    Path(out_path).write_text(svg, encoding="utf-8")
    print(f"wrote {out_path} ({len(svg)} bytes)")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    model_path = sys.argv[1]
    out_path = sys.argv[2]
    size = (1280, 720)
    if len(sys.argv) >= 4 and "x" in sys.argv[3]:
        w, h = sys.argv[3].lower().split("x")
        size = (int(w), int(h))
    render(model_path, out_path, size)


if __name__ == "__main__":
    main()
