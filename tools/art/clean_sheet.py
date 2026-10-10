#!/usr/bin/env python3
"""Evens out the background of a generated sheet before slicing: some sheets came back on a
darker magenta or purple (or a different shade per cell) with soft pink glows painted around
lanterns and glowing plants. Everything reachable from a cell's border through background,
magenta, pink or lavender glow becomes flat #FF00FF, so the slicer's magenta key and label
removal work as on the other sheets. The art's dark outline stops the fill, so pink and
purple art inside an outline stays.

    python3 tools/art/clean_sheet.py NAME [NAME ...]   # cleans the source of art/sheets/NAME.json in place
    python3 tools/art/clean_sheet.py NAME --halo lantern_lit   # also a blue-lavender halo in these cells
    python3 tools/art/clean_sheet.py NAME --cells lantern_lit  # only these cells
    python3 tools/art/clean_sheet.py NAME --heal-x 255,509 --only-heal  # paint out thin panel lines
                                     # drawn across a painting at these x (sheet pixels), nothing else
    python3 tools/art/clean_sheet.py NAME --sky far,mid --only-sky  # backdrop strips painted over their
                                     # own sky: the sky (one colour per row, a gradient) becomes magenta

Uses the manifest's `grid` (or the detected one) and `region`, and runs once per sheet: run it
again on the original picture, not on its own output, if the thresholds change.
"""
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import slice_sheets as ss  # noqa: E402

MAGENTA = np.array([255, 0, 255])


def passable(cell, bg, halo=False):
    c = cell.astype(int)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    near_bg = np.abs(c - bg).sum(2) < 90
    magenta = (np.minimum(r, b) - g > 110) & (np.abs(r - b) < 90)
    pink = (r > 170) & (r - g > 70) & (b - g > 25)            # warm pink glow over magenta
    lavender = (b > 170) & (b - g > 60) & (r - g > 40) & (np.abs(r - b) < 80)  # cool glow
    ok = near_bg | magenta | pink | lavender
    if halo:  # a soft blue-lavender disc painted behind a glowing crystal
        ok |= (b > 200) & (b - r > 40) & (b - g > 50) & (r > 120) & (g < 180)
    return ok


def clean_cell(cell, halo=False):
    h, w, _ = cell.shape
    ring = np.concatenate([cell[0], cell[-1], cell[:, 0], cell[:, -1]]).astype(int)
    mag = ring[(np.minimum(ring[:, 0], ring[:, 2]) - ring[:, 1]) > 100]
    bg = np.median(mag, 0) if len(mag) else MAGENTA
    ok = passable(cell, bg, halo)
    seen = np.zeros((h, w), bool)
    q = deque()
    for y, x in [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] + \
                [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]:
        if ok[y, x] and not seen[y, x]:
            seen[y, x] = True
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and ok[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    out = cell.copy()
    out[seen] = MAGENTA
    return out


def remove_sky(cell, tol=20):
    """A strip painted over a sky gradient: each row's sky colour is followed down from the top
    row, and the sky reachable from the top in that row's colour becomes magenta."""
    c = cell.astype(int)
    h, w, _ = c.shape
    sky = np.zeros((h, w), bool)
    magenta = (np.minimum(c[..., 0], c[..., 2]) - c[..., 1]) > 150
    top = 0
    def divider(y):  # a thin dark panel line along the top edge
        med = np.median(c[y], 0)
        return med.sum() < 200 and (np.abs(c[y] - med).sum(1) < 40).mean() > 0.8
    while top < min(h - 1, 40) and (magenta[top].mean() > 0.5 or divider(top)):  # divider or label bar
        sky[top] = True
        top += 1
    def mode(px):  # the most common colour: a flat sky band even where trees fill most of the row
        q = px // 6
        vals, counts = np.unique(q, axis=0, return_counts=True)
        best = vals[counts.argmax()]
        return np.median(px[(q == best).all(1)], 0)
    prev = mode(c[top])
    last = top - 1
    for y in range(top, h):
        near = np.abs(c[y] - prev).sum(1) < 75  # stepped gradients jump between bands
        if near.mean() < 0.08:
            break
        prev = mode(c[y][near])
        sky[y] = (np.abs(c[y] - prev).sum(1) < tol) | magenta[y]
        last = y
    seen = np.zeros((h, w), bool)
    q = deque((0, x) for x in range(w) if sky[0, x])
    for _, x in q:
        seen[0, x] = True
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny <= last and 0 <= nx < w and sky[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    out = cell.copy()
    out[seen] = MAGENTA
    return out


def heal_columns(img, xs, half=2):
    """Paints thin vertical lines out of a painting: each column within `half` of x becomes a
    blend of the columns just outside the line."""
    out = img.astype(float)
    for x in xs:
        a, b = x - half - 1, x + half + 1
        for i, cx in enumerate(range(x - half, x + half + 1)):
            t = (i + 1) / (2 * half + 2)
            out[:, cx] = out[:, a] * (1 - t) + out[:, b] * t
    return out.round().astype(np.uint8)


def main():
    args = sys.argv[1:]
    heal = []
    if "--heal-x" in args:
        i = args.index("--heal-x")
        heal = [int(v) for v in args[i + 1].split(",")]
        del args[i:i + 2]
    only_heal = "--only-heal" in args
    args = [a for a in args if a != "--only-heal"]
    sky = set()
    if "--sky" in args:
        i = args.index("--sky")
        sky = set(args[i + 1].split(","))
        del args[i:i + 2]
    only_sky = "--only-sky" in args
    args = [a for a in args if a != "--only-sky"]
    only_cells = None
    if "--cells" in args:  # clean only these cells (others keep glows that belong to the art)
        i = args.index("--cells")
        only_cells = set(args[i + 1].split(","))
        del args[i:i + 2]
    halo = set()
    if "--halo" in args:
        i = args.index("--halo")
        halo = set(args[i + 1].split(","))
        del args[i:i + 2]
    for name in args:
        with open(os.path.join(ss.SHEETS, name + ".json")) as f:
            man = json.load(f)
        path = os.path.join(ss.ROOT, man["source"])
        img = np.asarray(Image.open(path).convert("RGB")).copy()
        if heal:
            img = heal_columns(img, heal)
        if only_heal:
            Image.fromarray(img).save(path, optimize=True)
            print(f"{name}: healed lines in {man['source']}")
            continue
        x0, y0, x1, y1 = man.get("region", [0, 0, img.shape[1], img.shape[0]])
        part = img[y0:y1, x0:x1]
        bg = ss.background_color(part.astype(int))
        bands = ss.grid_from_manifest(man["grid"], part.shape) if "grid" in man else ss.detect_grid(part.astype(int), bg)
        ins = man["inset"] + 4 if "inset" in man else 4  # stay inside the divider lines / cell frames
        for (by0, by1, cols), row in zip(bands, man["cells"]):
            for (cx0, cx1), cell_name in zip(cols, row):
                if only_cells is not None and cell_name not in only_cells:
                    continue
                box = part[by0 + ins:by1 - ins, cx0 + ins:cx1 - ins]
                if cell_name in sky:
                    box = remove_sky(box)
                if not only_sky:
                    box = clean_cell(box, cell_name in halo)
                part[by0 + ins:by1 - ins, cx0 + ins:cx1 - ins] = box
        img[y0:y1, x0:x1] = part
        Image.fromarray(img).save(path, optimize=True)
        print(f"{name}: cleaned {man['source']}")


if __name__ == "__main__":
    main()
