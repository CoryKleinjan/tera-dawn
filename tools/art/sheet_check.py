#!/usr/bin/env python3
"""Check a generated art sheet before a person looks at it.

    python3 tools/art/sheet_check.py SHEET.png --cells 4 8 --kind anim
    python3 tools/art/sheet_check.py SHEET.png --cells 2 4 --anchor art/source/dewling.png

Each check is "pass", "warn" or "fail"; a sheet passes when nothing fails. When the batch's
grid is known, the per-cell checks split the sheet into that many equal cells, which is how the
batches ask for them. It runs locally and
costs nothing, so the full Gemini pass runs it on every result (tools/art/gemini_pass.py).

Checks:
- background: the sheet's main colour is flat magenta #FF00FF
- grid: divider lines split the sheet into the rows and columns the batch asked for (a warning,
  because sprites that cross a divider can hide it)
- empty cells: every cell has art in it
- frame sizes (animation sheets): each frame's sprite area stays near the others, which
  catches frames where the character was redrawn bigger, smaller or as someone else
- magenta in sprites: no pink-purple inside the art (it would be cut out with the background)
- palette (with --anchor): the sprite colours sit close to the anchor sheet's colours
- must have (with --must-have): a colour (e.g. W1's green grip rod) is in the cells that need it
  and absent from the cells that must not have it
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slice_sheets import background_color, detect_grid, key_magenta  # noqa: E402


MAGENTA = np.array([255, 0, 255])
LABEL_BAND = 0.16  # top of each cell where the white label sits
FRAME_AREA_RANGE = (0.55, 1.8)  # allowed frame area relative to the sheet's median frame


def load_rgb(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.int32)


def cells_of(bands):
    return [(y0, y1, x0, x1) for y0, y1, cols in bands for x0, x1 in cols]


def even_cells(shape, rows, cols):
    """Equal cells, row by row: the layout every batch asks for."""
    h, w = shape[:2]
    return [(h * r // rows, h * (r + 1) // rows, w * c // cols, w * (c + 1) // cols)
            for r in range(rows) for c in range(cols)]


def divider_count(rgb, bg, axis):
    """How many cells divider lines make along one axis. Dividers are thin lines that differ
    from the background across most of the sheet (Gemini draws them dark magenta or grey)."""
    differs = np.abs(rgb - bg).sum(2) > 150
    share = differs.mean(1 - axis)
    size = len(share)
    runs = []
    for i in np.where(share > 0.6)[0]:
        if runs and i - runs[-1][1] <= 2:
            runs[-1][1] = i
        else:
            runs.append([i, i])
    lines = [(a + b) / 2 for a, b in runs if b - a <= 12 and 0.01 * size < a < 0.99 * size]
    return len(lines) + 1


def grid_counts(rgb, bg):
    """(rows, [cols]) from both detectors: the slicer's and divider_count."""
    bands = detect_grid(rgb, bg)
    return {(len(bands), tuple(sorted({len(c) for _, _, c in bands}))),
            (divider_count(rgb, bg, 0), (divider_count(rgb, bg, 1),))}


def sprite_mask(rgb, bg, box, solid=0.5):
    """Opaque art in one cell, without the label band and divider edges."""
    y0, y1, x0, x1 = box
    top = y0 + int((y1 - y0) * LABEL_BAND)
    cell = rgb[top + 3:y1 - 3, x0 + 3:x1 - 3].astype(np.float64)
    if cell.size == 0:
        return cell[..., 0] > 0, cell
    _, alpha = key_magenta(cell, bg)
    return alpha > solid, cell


def palette(pixels, k=24):
    """The k most common colours (quantised to 8 levels per channel) of an N x 3 array."""
    q = (pixels // 32).astype(np.int32)
    vals, counts = np.unique(q, axis=0, return_counts=True)
    return vals[np.argsort(-counts)[:k]] * 32 + 16


def palette_distance(pixels, pal):
    sample = pixels[:: max(1, len(pixels) // 20000)]
    d = np.sqrt(((sample[:, None, :] - pal[None, :, :]) ** 2).sum(2)).min(1)
    return float(np.mean(d))


def opaque_pixels(rgb, bg, boxes):
    out = []
    for box in boxes:
        mask, cell = sprite_mask(rgb, bg, box, solid=0.99)
        if mask.any():
            out.append(cell[mask])
    return np.concatenate(out) if out else np.zeros((0, 3))


def check(path, cells=None, kind="still", anchor=None, must_have=None):
    rgb = load_rgb(path)
    bg = background_color(rgb)
    results = []

    def add(name, status, detail):
        results.append({"check": name, "status": status, "detail": detail})

    is_magenta = np.abs(bg - MAGENTA).sum() < 90
    add("background", "pass" if is_magenta else ("fail" if cells else "warn"),
        "main colour %s" % list(map(int, bg)))
    if not is_magenta:
        # Scenes (backdrops, key art, the world map) are painted edge to edge: nothing more to check.
        return summarise(path, results)

    found = grid_counts(rgb, bg)
    shown = " or ".join("%d x %s" % (r, "/".join(map(str, c))) for r, c in sorted(found))
    if cells:
        rows, cols = cells
        ok = (rows, (cols,)) in found
        add("grid", "pass" if ok else "warn", "asked %d x %d, found %s" % (rows, cols, shown))
        boxes = even_cells(rgb.shape, rows, cols)
    else:
        add("grid", "pass", "found %s" % shown)
        boxes = cells_of(detect_grid(rgb, bg))

    areas, empty = [], []
    for i, box in enumerate(boxes):
        mask, _ = sprite_mask(rgb, bg, box)
        frac = mask.mean() if mask.size else 0.0
        areas.append(frac)
        if frac < 0.01:
            empty.append(i + 1)
    add("empty cells", "pass" if not empty else "warn",
        "none" if not empty else "cells %s" % ", ".join(map(str, empty)))

    if kind == "anim" and len(areas) > 2:
        filled = [a for a in areas if a >= 0.01]
        med = float(np.median(filled)) if filled else 0.0
        odd = [i + 1 for i, a in enumerate(areas)
               if a >= 0.01 and not (FRAME_AREA_RANGE[0] <= a / med <= FRAME_AREA_RANGE[1])]
        add("frame sizes", "pass" if not odd else "fail",
            "all frames similar" if not odd else "frames %s are a different size" % ", ".join(map(str, odd)))

    art = opaque_pixels(rgb, bg, boxes)
    if len(art):
        pink = (art[:, 0] > 200) & (art[:, 2] > 200) & (art[:, 1] < 80)
        share = float(pink.mean())
        add("magenta in sprites", "pass" if share < 0.01 else ("warn" if share < 0.03 else "fail"),
            "%.1f%% of art pixels are magenta" % (share * 100))

    if anchor and len(art):
        a_rgb = load_rgb(anchor)
        a_bg = background_color(a_rgb)
        a_art = opaque_pixels(a_rgb, a_bg, cells_of(detect_grid(a_rgb, a_bg)))
        if len(a_art):
            dist = palette_distance(art, palette(a_art))
            add("palette", "pass" if dist < 28 else ("warn" if dist < 45 else "fail"),
                "average distance to %s's colours: %.0f" % (os.path.basename(anchor), dist))

    if must_have:
        colour = np.array(must_have["rgb"])
        missing, extra = [], []
        for i, box in enumerate(boxes):
            y0, y1, x0, x1 = box
            cell = rgb[y0 + 3:y1 - 3, x0 + 3:x1 - 3]
            has = (np.abs(cell - colour).sum(2) < 90).mean() > 0.002
            if i + 1 in must_have.get("in", []) and not has:
                missing.append(i + 1)
            if i + 1 in must_have.get("not_in", []) and has:
                extra.append(i + 1)
        detail = []
        if missing:
            detail.append("missing in cells %s" % ", ".join(map(str, missing)))
        if extra:
            detail.append("should not be in cells %s" % ", ".join(map(str, extra)))
        add("must have", "fail" if detail else "pass", "; ".join(detail) or "where it should be")

    return summarise(path, results)


def summarise(path, results):
    statuses = [r["status"] for r in results]
    overall = "fail" if "fail" in statuses else ("warn" if "warn" in statuses else "pass")
    return {"sheet": path, "status": overall, "checks": results}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("sheet")
    ap.add_argument("--cells", nargs=2, type=int, metavar=("ROWS", "COLS"))
    ap.add_argument("--kind", default="still", choices=["still", "anim"])
    ap.add_argument("--anchor", help="sheet whose colours this one should match")
    ap.add_argument("--must-have", help='JSON, e.g. {"rgb": [0,255,0], "in": [1,2], "not_in": [21]}')
    ap.add_argument("--json", action="store_true", help="print the result as JSON")
    args = ap.parse_args()
    res = check(args.sheet, args.cells, args.kind, args.anchor,
                json.loads(args.must_have) if args.must_have else None)
    if args.json:
        print(json.dumps(res, indent=1))
        return
    print("%s: %s" % (os.path.basename(args.sheet), res["status"].upper()))
    for r in res["checks"]:
        print("  %-18s %-4s %s" % (r["check"], r["status"], r["detail"]))


if __name__ == "__main__":
    main()
