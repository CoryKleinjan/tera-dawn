#!/usr/bin/env python3
"""Close-up panels of whole body cells for Gemini edits, and pasting the edits back.

Gemini leaves small details (like hands) alone when asked to edit the whole 32-pose body sheet,
but redraws them when the figure is big in the picture. A panel shows up to COLS x ROWS cells
of art/source/paperdoll_body.png, each ZOOM times bigger, so an edit can redraw a few cells'
hands or arms at a time. Pasting puts the edited cells back at their own size:

    python3 tools/art/body_panels.py panels DIR NAME CELL,CELL,...
        DIR/NAME_1.png, NAME_2.png, ... (COLS x ROWS cells each, in the order given)
    python3 tools/art/body_panels.py hands CELL,CELL,... EDIT_1.png EDIT_2.png ...
        take only what the edit changed on his hands and arms (see changed_limbs)
    python3 tools/art/body_panels.py upper CELL,CELL,... EDIT_1.png ...
        take everything above his shorts from the edit; his legs stay as they are
    python3 tools/art/body_panels.py worn-base SHEET OUT CELL,CELL,...
        a worn sheet (art/source/<x>_frames.png) with those cells swapped for the bare body,
        for an edit that dresses only them after the body changed
    python3 tools/art/body_panels.py worn-cells SHEET EDIT CELL,CELL,...
        copy those cells from the dressed edit back into the worn sheet

Then re-cut the body and rebuild the layers (slice_sheets.py paperdoll_body, then
paperdoll_layers.py).
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grip_guide as gg  # noqa: E402
import paperdoll_layers as pl  # noqa: E402
import slice_sheets as ss  # noqa: E402

COLS, ROWS = 2, 2
ZOOM = 3
GAP = 16           # magenta between cells (panel pixels)
CHANGED = 90       # colour distance (summed RGB) at which a pixel counts as changed by the edit
MIN_CHANGE = 40    # smaller changed patches are the zoom's own noise along outlines (pixels)
GROW = 3           # a changed patch takes this many pixels round it, for its outline
SHORTS_GREY = 25   # the shorts are grey: channels within this of each other, and darkish


def groups(cells):
    n = COLS * ROWS
    return [cells[i:i + n] for i in range(0, len(cells), n)]


def _place(i, w, h):
    return GAP + (i % COLS) * (w * ZOOM + GAP), GAP + (i // COLS) * (h * ZOOM + GAP)


def _panel_size(count, w, h):
    cols, rows = min(count, COLS), -(-count // COLS)
    return cols * (w * ZOOM + GAP) + GAP, rows * (h * ZOOM + GAP) + GAP


def _cell_size(boxes):
    """Every cell is cut at the size of the largest one, so panels line up."""
    return (max(b[2] - b[0] for b in boxes.values()), max(b[3] - b[1] for b in boxes.values()))


def panels(out_dir, name, cells):
    boxes = gg.layout()
    w, h = _cell_size(boxes)
    body = Image.open(gg.BODY).convert("RGB")
    os.makedirs(out_dir, exist_ok=True)
    for n, group in enumerate(groups(cells), 1):
        img = Image.new("RGB", _panel_size(len(group), w, h), gg.MAGENTA)
        for i, c in enumerate(group):
            x0, y0 = boxes[c][:2]
            crop = body.crop((x0, y0, x0 + w, y0 + h)).resize((w * ZOOM, h * ZOOM), Image.LANCZOS)
            img.paste(crop, _place(i, w, h))
        path = os.path.join(out_dir, f"{name}_{n}.png")
        img.save(path)
        print(f"panel: {path} ({', '.join(group)})")


def _edited_cells(cells, paths):
    """{cell: (its box on the body sheet, the edited cell back at body size as RGBA)}."""
    boxes = gg.layout()
    w, h = _cell_size(boxes)
    out = {}
    for group, path in zip(groups(cells), paths):
        edit = gg._sheet(path, _panel_size(len(group), w, h))
        for i, c in enumerate(group):
            px, py = _place(i, w, h)
            zoomed = Image.fromarray(edit[py:py + h * ZOOM, px:px + w * ZOOM])
            arr = np.asarray(zoomed.resize((w, h), Image.LANCZOS)).copy()
            out[c] = (boxes[c], gg.solid(arr, (0, 0, w, h)))
    return out


def _components(mask):
    """Labels of the 8-connected patches of `mask`, and their sizes."""
    labels, n = ss.label(mask)
    return labels, np.bincount(labels.ravel(), minlength=n + 1)


def changed_limbs(old, new):
    """Where the edit redrew something: pixels whose colour (or background) changed, in patches
    big enough not to be the zoom's noise along the outlines, grown by their outline. His head
    (the top of the figure) never counts, so a redrawn face can't sneak in."""
    a, b = old[..., 3] > 0, new[..., 3] > 0
    diff = np.abs(old[..., :3].astype(int) - new[..., :3].astype(int)).sum(2) > CHANGED
    changed = (a != b) | (a & b & diff)
    labels, sizes = _components(changed)
    keep = sizes >= MIN_CHANGE
    keep[0] = False
    mask = ss.dilate(keep[labels], GROW)
    if (old[..., 3] > 0).any():
        found = pl.analyse(old)
        (cx, cy), r = found["head"], found["r"]
        yy, xx = np.mgrid[:old.shape[0], :old.shape[1]]
        mask &= (xx - cx) ** 2 + (yy - cy) ** 2 > (r * 1.05) ** 2
    return mask


def _shorts_top(old):
    """The first row of his shorts (grey pixels), or the cell's bottom when there are none."""
    rgb = old[..., :3].astype(int)
    grey = (old[..., 3] > 0) & (rgb.max(2) - rgb.min(2) < SHORTS_GREY) & (rgb.max(2) < 140)
    rows = np.where(grey.sum(1) > 6)[0]
    return rows[0] if len(rows) else old.shape[0]


def paste(cells, paths, mode):
    body = np.asarray(Image.open(gg.BODY).convert("RGB")).copy()
    for c, ((x0, y0, x1, y1), new) in _edited_cells(cells, paths).items():
        new = new[:y1 - y0, :x1 - x0]
        region = body[y0:y1, x0:x1]
        old = gg.solid(region.copy(), (0, 0, x1 - x0, y1 - y0))
        if mode == "upper":
            take = np.zeros(region.shape[:2], bool)
            take[:_shorts_top(old)] = True
            # a hand swung down past his hips still comes along
            take |= changed_limbs(old, new) & gg._handlike(new)
        else:
            take = changed_limbs(old, new)
        region[take] = np.where(new[take][:, 3:] > 0, new[take][:, :3], gg.MAGENTA)
    Image.fromarray(body).save(gg.BODY)
    print(f"{mode}: {len(cells)} cells -> {os.path.relpath(gg.BODY, pl.ROOT)}")


def _swap_cells(dst_path, src, cells, out_path, key=False):
    """Copies `cells` from `src` into the sheet at dst_path; with `key`, the cell's background
    (whatever flat colour Gemini painted, reached from the cell border) becomes pure magenta."""
    boxes = gg.layout()
    dst = np.asarray(Image.open(dst_path).convert("RGB")).copy()
    for c in cells:
        x0, y0, x1, y1 = boxes[c]
        cell = src[y0:y1, x0:x1]
        if key:
            solid = gg.solid(src, boxes[c], exact=False)
            cell = np.where(solid[..., 3:] > 0, solid[..., :3], gg.MAGENTA)
        dst[y0:y1, x0:x1] = cell
    Image.fromarray(dst).save(out_path)
    print(f"{', '.join(cells)} -> {out_path}")


def worn_base(sheet, out, cells):
    _swap_cells(sheet, np.asarray(Image.open(gg.BODY).convert("RGB")), cells, out)


def worn_cells(sheet, edit, cells):
    size = Image.open(sheet).size
    _swap_cells(sheet, gg._sheet(edit, size), cells, sheet, key=True)


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) == 4 and args[0] == "panels":
        panels(args[1], args[2], args[3].split(","))
    elif len(args) >= 3 and args[0] in ("hands", "upper"):
        paste(args[1].split(","), args[2:], args[0])
    elif len(args) == 4 and args[0] == "worn-base":
        worn_base(args[1], args[2], args[3].split(","))
    elif len(args) == 4 and args[0] == "worn-cells":
        worn_cells(args[1], args[2], args[3].split(","))
    else:
        sys.exit(__doc__)
