#!/usr/bin/env python3
"""Make the base image for the grip-hands edit, and put the edit's hands on the body sheet.

The body sheet draws his weapon hand as an empty fist with the thumb on the outside, so a
sword pushed through it (paperdoll_layers.weapon_strips) comes out with the thumb on the
pommel end. To fix the hands, Gemini edits the body sheet with a guide rod through each
weapon fist: the rod lies the way paperdoll_rig.json points the sword, long on the blade
side and short on the pommel side, and Gemini redraws the hand gripping it with the thumb
wrapped next to the long end.

    python3 tools/art/grip_guide.py guide OUT.png      # the body sheet with the rods drawn on
    python3 tools/art/grip_guide.py hands EDIT.png     # put the edit's hands on the body sheet

`hands` takes only the hand around each grip from the edit (the rod taken out and painted
over), and pastes it into art/source/paperdoll_body.png, so nothing else on the sheet moves.
Then re-cut the body and rebuild the layers (slice_sheets.py paperdoll_body, then
paperdoll_layers.py).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paperdoll_layers as pl  # noqa: E402
import slice_sheets as ss  # noqa: E402

BODY = os.path.join(pl.ROOT, "art", "source", "paperdoll_body.png")
GREEN = (0, 255, 0)
BLADE = 1.4      # the rod reaches this far past the grip on the blade side (head radii)
POMMEL = 0.45    # and this far on the pommel side
THICK = 0.13     # rod thickness (head radii)
HAND = 0.55      # the hand taken from the edit reaches this far from the grip (head radii)


def grips():
    """Per frame that holds a weapon: (cell name, the grip on the body sheet, the sword's
    angle, the head radius), in body sheet pixels."""
    names, spec = pl.frame_names()
    strip = Image.open(pl.STRIP)
    fw, fh = strip.width // len(names), strip.height
    hands, _ = pl.hand_rig(fw)
    cells = {n: spec["frames"][n].split(":", 1)[1] for n in names}
    offsets = pl.body_offsets(names, cells, fw, fh)
    r = pl.analyse(np.asarray(strip.crop((0, 0, fw, fh))))["r"]
    with open(os.path.join(ss.SHEETS, "paperdoll_body.json")) as f:
        man = json.load(f)
    grid = man["grid"]
    where = {c: (row, col) for row, line in enumerate(man["cells"]) for col, c in enumerate(line)}
    out = {}
    for n in names:
        if "weapon" not in hands[n] or cells[n] in out:
            continue
        x, y, angle = hands[n]["weapon"]
        row, col = where[cells[n]]
        dx, dy = offsets[n]
        out[cells[n]] = ((grid["cols"][col] + x - dx, grid["rows"][row] + y - dy), angle, r)
    return out


def guide(path):
    sheet = Image.open(BODY).convert("RGB")
    draw = ImageDraw.Draw(sheet)
    for (x, y), angle, r in grips().values():
        c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
        a = (x - c * r * POMMEL, y - s * r * POMMEL)
        b = (x + c * r * BLADE, y + s * r * BLADE)
        draw.line([a, b], fill=GREEN, width=max(3, round(r * THICK)))
    sheet.save(path)
    print(f"guide: {path}")


def rod_mask(arr):
    rgb = arr[..., :3].astype(int)
    return (rgb[..., 1] > 170) & (rgb[..., 0] < 140) & (rgb[..., 2] < 140)


def hands(path):
    edit = Image.open(path).convert("RGBA")
    body = Image.open(BODY).convert("RGBA")
    if edit.size != body.size:
        edit = edit.resize(body.size, Image.LANCZOS)
    out = np.asarray(body).copy()
    arr = np.asarray(edit).copy()
    rod = ss.dilate(rod_mask(arr), 1)
    arr = pl.inpaint(arr, rod)
    for (x, y), _, r in grips().values():
        # the edit's hand: its skin and outline flooded from the grip, as paperdoll_layers
        # finds a fist, plus the body's old fist, so none of the old hand is left uncovered
        solid = arr.copy()
        solid[..., 3] = np.where((arr[..., :3].astype(int) - (255, 0, 255)).__abs__().sum(2) < 90, 0, 255)
        new = pl.fist_mask(solid, (x, y), r * HAND)
        old = pl.fist_mask(out, (x, y), r * HAND)
        take = new | (old & (solid[..., 3] > 0))
        out[take] = solid[take]
        out[old & ~take] = (255, 0, 255, 255)
    Image.fromarray(out, "RGBA").convert("RGB").save(BODY)
    print(f"hands: {os.path.relpath(BODY, pl.ROOT)}")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("guide", "hands"):
        sys.exit(__doc__)
    {"guide": guide, "hands": hands}[sys.argv[1]](sys.argv[2])
