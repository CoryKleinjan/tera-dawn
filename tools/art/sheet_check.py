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
- palette (with --anchor): the sprite colours sit close to the anchor sheet's colours (a warning only)
- flat bottom (with --stands, for things that stand on a map): each sprite ends in a flat bottom
  edge as wide as the object just above it. A 3/4 view's slanted base fails this (a warning, as
  the eye still decides: it can't see a top face drawn above a flat bottom)
- must have (with --must-have): a colour (e.g. W1's green grip rod) is in the cells that need it
  and absent from the cells that must not have it
- town kit (with --town, the entry's "town_check" from tools/art/town_kit.py): the building's door
  covers its doorway mark and its base sits on the mark's ground line; nothing is cut off at the
  canvas or cell edge; no stray bits away from the art (leftover flags, candles, figures); no ground
  line wider than the base; no pink glow round the art; a backdrop's bottom quarter is quiet (no
  near foreground). These reject (fail) or flag (warn); they never change the picture.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slice_sheets import background_color, detect_grid, dilate, key_magenta, label  # noqa: E402


MAGENTA = np.array([255, 0, 255])
LABEL_BAND = 0.16  # top of each cell where the white label sits
FRAME_AREA_RANGE = (0.55, 1.8)  # allowed frame area relative to the sheet's median frame
FLAT_BOTTOM_BAND = 0.06  # how far up (share of the sprite's height) "just above the bottom" reaches
FLAT_BOTTOM_EDGE = 0.01  # rows (share of the sprite's height) that count as its bottom edge
FLAT_BOTTOM_MIN = 0.6  # the bottom edge's width relative to the widest row in that band
BACKGROUND_NEAR = 60  # colour distance (summed over R, G, B) that still counts as the background
EDGE_GAP = 4  # town kit: art this close to the canvas or cell edge counts as cut off
STRAY_MIN = 0.0004  # town kit: a separate piece this share of the cell is a stray bit, not a speck
STRAY_GAP = 12  # town kit: a piece further than this from the main art is separate from it
DOOR_COVER = 0.9  # town kit: share of the doorway mark the building must cover
BASE_TOLERANCE = 0.02  # town kit: how far (share of the height) the base may sit off the ground line
GROUND_LINE = 1.12  # town kit: the bottom rows this much wider than the base above are a ground line
HALO_SHARE = 0.25  # town kit: share of the ring round the art that may be pink glow
BUSY_FOREGROUND = 1.3  # town kit: a backdrop's bottom quarter this much busier than the whole is near foreground


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


def is_pink(pixels):
    """Bright pink-purple: what the magenta key cuts out."""
    return (pixels[..., 0] > 200) & (pixels[..., 2] > 200) & (pixels[..., 1] < 80)


def magenta_in_art(rgb, bg, boxes):
    """(pink pixels in the art, art pixels) over every cell. The key cuts out every pink pixel,
    so pink can't be told apart by its alpha. Pink-purple painted on the art is a different
    shade from the background, though: count pink pixels that aren't the background's colour
    (the sheet's, or the cell's own), leaving out the 2 px next to it where art edges blend
    into it. Gaps in the art, like the space inside a bow, are the background's colour, so
    they don't count; exact #FF00FF painted on the art can't be told from a gap either."""
    pink_in_art = art = 0
    for box in boxes:
        mask, cell = sprite_mask(rgb, bg, box)
        if not mask.any():
            continue
        # Gemini sometimes tints a cell's background, so the cell's own main colour counts too
        background = (np.abs(cell - bg).sum(2) < BACKGROUND_NEAR) | \
                     (np.abs(cell - background_color(cell)).sum(2) < BACKGROUND_NEAR)
        pink = is_pink(cell) & ~dilate(background, 2)
        # pink reaching the cell's edge is a neighbour's background where the sheet's grid
        # drifts from even cells, not paint on the art
        lab, _ = label(pink)
        edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
        pink &= ~np.isin(lab, edge[edge > 0])
        pink_in_art += int(pink.sum())
        art += int(mask.sum())
    return pink_in_art, art


def opaque_pixels(rgb, bg, boxes):
    out = []
    for box in boxes:
        mask, cell = sprite_mask(rgb, bg, box, solid=0.99)
        if mask.any():
            out.append(cell[mask])
    return np.concatenate(out) if out else np.zeros((0, 3))


def check(path, cells=None, kind="still", anchor=None, must_have=None, stands=False, town=None):
    rgb = load_rgb(path)
    bg = background_color(rgb)
    results = []

    def add(name, status, detail):
        results.append({"check": name, "status": status, "detail": detail})

    if town and town.get("kind") in ("backdrop", "wall"):
        # a town kit scene is painted edge to edge, with no magenta
        add("background", "pass", "a scene, painted edge to edge")
        if town["kind"] == "backdrop":
            add(*busy_foreground(rgb))
        return summarise(path, results)

    is_magenta = np.abs(bg - MAGENTA).sum() < 90
    # A darker or pinker magenta still keys (the slicer keys against the sheet's own colour).
    magenta_ish = bg[1] < 0.45 * min(bg[0], bg[2]) and abs(int(bg[0]) - int(bg[2])) < 60
    if is_magenta:
        add("background", "pass", "flat magenta")
    elif magenta_ish:
        add("background", "warn", "a darker magenta %s" % list(map(int, bg)))
    else:
        add("background", "fail" if cells else "warn", "not magenta: main colour %s" % list(map(int, bg)))
    if not (is_magenta or magenta_ish):
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

    pink, art_area = magenta_in_art(rgb, bg, boxes)
    if art_area:
        share = pink / art_area
        add("magenta in sprites", "pass" if share < 0.01 else ("warn" if share < 0.03 else "fail"),
            "%.1f%% of the art is magenta" % (share * 100))

    art = opaque_pixels(rgb, bg, boxes)

    if anchor and len(art):
        a_rgb = load_rgb(anchor)
        a_bg = background_color(a_rgb)
        a_art = opaque_pixels(a_rgb, a_bg, cells_of(detect_grid(a_rgb, a_bg)))
        if len(a_art):
            dist = palette_distance(art, palette(a_art))
            # Only a warning: a family anchor (e.g. the first monster of a region) is a different
            # creature, so its colours are a guide, not a rule.
            add("palette", "pass" if dist < 35 else "warn",
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

    if stands:
        slanted = [i + 1 for i, box in enumerate(boxes) if not flat_bottom(sprite_mask(rgb, bg, box)[0])]
        add("flat bottom", "pass" if not slanted else "warn",
            "every sprite" if not slanted else "cells %s end in a slanted or pointed bottom" % ", ".join(map(str, slanted)))

    if town:
        for r in town_checks(rgb, bg, town, boxes):
            add(*r)

    return summarise(path, results)


# ---------- town kit ----------

def art_mask(rgb, bg, box):
    """Opaque art in a box, edge to edge (no label band: kit canvases have no labels)."""
    y0, y1, x0, x1 = box
    cell = rgb[y0:y1, x0:x1].astype(np.float64)
    _, alpha = key_magenta(cell, bg)
    return alpha > 0.5, cell


def pieces(mask):
    """(main piece's mask, [areas of separate pieces]) of an art mask."""
    lab, n = label(mask)
    if not n:
        return mask, []
    areas = np.bincount(lab.ravel())[1:]
    main = lab == int(areas.argmax()) + 1
    near = dilate(main, STRAY_GAP)
    apart = [int(a) for i, a in enumerate(areas) if i != areas.argmax() and not (near & (lab == i + 1)).any()]
    return main, apart


def touches_edge(mask):
    g = EDGE_GAP
    return bool(mask[:g].any() or mask[-g:].any() or mask[:, :g].any() or mask[:, -g:].any())


def ground_line(mask):
    """Whether the bottom few rows run wider than the base just above them (Gemini's ground line)."""
    rows = np.flatnonzero(mask.sum(1) >= 3)
    if len(rows) < 40:
        return False

    def span(y):
        xs = np.flatnonzero(mask[y])
        return xs[-1] - xs[0] + 1 if len(xs) else 0

    bottom = rows[-1]
    edge = max(span(y) for y in range(bottom - 5, bottom + 1))
    above = max(span(y) for y in range(bottom - 40, bottom - 10))
    return above > 0 and edge > GROUND_LINE * above


def halo(cell, mask, bg):
    """Share of the ring just outside the art that is pink-purple glow rather than the background."""
    ring = dilate(mask, 8) & ~mask
    if not ring.any():
        return 0.0
    px = cell[ring]
    off_bg = np.abs(px - bg).sum(1) > 40
    tinted = off_bg & (px[:, 0] > 120) & (px[:, 2] > 120) & (px[:, 1] < px[:, 0] * 0.7)
    return float(tinted.mean())


def busy_foreground(rgb):
    """A backdrop's bottom quarter should be quiet: far-away land, water or sky. Flowers, grass,
    rocks or planks close to the viewer fill it with strong edges (calibrated on the six town
    panoramas: Dawnharbor 0.4, Dawnrise's flower meadow 1.7)."""
    import cv2
    g = np.asarray(Image.fromarray(rgb.astype(np.uint8)).convert("L").resize((1536, max(1, round(1536 * rgb.shape[0] / rgb.shape[1]))))).astype(np.float32)
    m = np.hypot(cv2.Sobel(g, cv2.CV_32F, 1, 0), cv2.Sobel(g, cv2.CV_32F, 0, 1))
    ratio = float(m[int(m.shape[0] * 0.75):].mean() / max(m.mean(), 1e-6))
    return ("clear foreground", "pass" if ratio < BUSY_FOREGROUND else "warn",
            "bottom quarter %.2fx as busy as the whole%s" % (ratio, "" if ratio < BUSY_FOREGROUND else ": near foreground?"))


def town_checks(rgb, bg, town, boxes):
    """The town kit's checks for one result (see the module notes). Returns (name, status, detail)."""
    out = []
    h, w = rgb.shape[:2]
    kind = town.get("kind")
    if kind == "sheet":  # pieces laid out on a fixed sheet: only the glow applies
        glows = [i + 1 for i, box in enumerate(boxes) if halo(*reversed(art_mask(rgb, bg, box)), bg) > HALO_SHARE]
        return [("glow halo", "warn" if glows else "pass", "cells %s" % glows if glows else "none")]
    if kind in ("building", "single"):
        boxes = [(0, h, 0, w)]
    else:  # leave out the divider lines Gemini sometimes paints between cells
        boxes = [(y0 + 6, y1 - 6, x0 + 6, x1 - 6) for y0, y1, x0, x1 in boxes]
    cut, strays, lines, glows = [], [], [], []
    for i, box in enumerate(boxes):
        mask, cell = art_mask(rgb, bg, box)
        if not mask.any():
            continue
        main, apart = pieces(mask)
        cell_area = mask.size
        if touches_edge(mask):
            cut.append(i + 1)
        if [a for a in apart if a > STRAY_MIN * cell_area]:
            strays.append(i + 1)
        if kind != "sheet" and ground_line(main):
            lines.append(i + 1)
        if halo(cell, mask, bg) > HALO_SHARE:
            glows.append(i + 1)
        if kind == "building":
            x0, y0, x1, y1 = town["door"]
            cover = mask[y0:y1, x0:x1].mean()
            out.append(("door on its mark", "pass" if cover >= DOOR_COVER else "fail",
                        "the building covers %d%% of the doorway mark" % round(cover * 100)))
            rows = np.flatnonzero(main.sum(1) >= 3)
            off = abs(int(rows[-1]) + 1 - y1) / h if len(rows) else 1.0
            out.append(("base on the ground line", "pass" if off <= BASE_TOLERANCE else "fail",
                        "%d px from the doorway's bottom" % round(off * h)))
    one = kind in ("building", "single")
    where = (lambda c: "the art") if one else (lambda c: "cells %s" % ", ".join(map(str, c)))
    out.append(("not cut off", "fail" if cut and one else ("warn" if cut else "pass"),
                "%s touch%s the edge" % (where(cut), "es" if one else "") if cut else "a clear margin all round"))
    out.append(("stray bits", "warn" if strays else "pass",
                "%s ha%s pieces apart from the art (leftovers? the cut drops them)" % (where(strays), "s" if one else "ve")
                if strays else "none"))
    out.append(("ground line", "warn" if lines else "pass",
                "%s stand%s on a line wider than the base (the cut removes it)" % (where(lines), "s" if one else "")
                if lines else "none"))
    out.append(("glow halo", "warn" if glows else "pass",
                "%s ha%s a pink glow round the edge" % (where(glows), "s" if one else "ve") if glows else "none"))
    return out


def flat_bottom(mask):
    """Whether the sprite in `mask` ends in a flat bottom edge: its lowest rows span nearly as
    wide as the widest row just above them. Empty cells count as flat."""
    rows = np.flatnonzero(mask.sum(1) >= 3)
    if len(rows) < 10:
        return True
    top, bottom = rows[0], rows[-1]
    band = max(3, round((bottom - top) * FLAT_BOTTOM_BAND))

    def span(y):
        xs = np.flatnonzero(mask[y])
        return xs[-1] - xs[0] + 1 if len(xs) else 0

    # the last ~1% of rows: a flat bottom drawn a hair off level, or with rounded outline
    # corners, still counts; a 3/4 base slants over far more rows than that
    edge = max(span(y) for y in range(bottom - max(2, round((bottom - top) * FLAT_BOTTOM_EDGE)), bottom + 1))
    widest = max(span(y) for y in range(bottom - band, bottom + 1))
    return edge >= FLAT_BOTTOM_MIN * widest


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
    ap.add_argument("--stands", action="store_true", help="things that stand on a map: check for flat bottoms")
    ap.add_argument("--town", help='town kit checks, JSON, e.g. {"kind": "building", "door": [604, 923, 829, 1267]}')
    ap.add_argument("--json", action="store_true", help="print the result as JSON")
    args = ap.parse_args()
    res = check(args.sheet, args.cells, args.kind, args.anchor,
                json.loads(args.must_have) if args.must_have else None, args.stands,
                json.loads(args.town) if args.town else None)
    if args.json:
        print(json.dumps(res, indent=1))
        return
    print("%s: %s" % (os.path.basename(args.sheet), res["status"].upper()))
    for r in res["checks"]:
        print("  %-18s %-4s %s" % (r["check"], r["status"], r["detail"]))


if __name__ == "__main__":
    main()
