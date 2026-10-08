#!/usr/bin/env python3
"""Build assets/sprites/hero.png from Cory's hero sprite sheet.

extract_hero_frames.py cuts the frames out of art/reference/hero_spritesheet.png
into hero_frames/. This script lines them up (feet on a common baseline, head
centred in the frame) and adds what the sheet doesn't have: the hand-drawn back
view for climbing (hero.txt, in his palette) and the fallen tombstone.

FRAMES (136x88 each, feet on row 86, facing right):
0-3 idle, 4-7 walk, 8 jump, 9-10 climb (back view), 11-12 attack, 13 hurt, 14 fallen.

Run from anywhere: python3 tools/pixel_art/build_hero.py
"""
import os

import numpy as np
from PIL import Image, ImageOps

from render import grid_img, load_all

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "sprites", "hero.png")
FRAMES = os.path.join(HERE, "hero_frames")
FW, FH = 136, 88
BASELINE = 86  # last row of the feet
GRIDS = load_all(os.path.join(HERE, "hero.txt"))


def g(name):
    return grid_img(GRIDS[name])


def new():
    return Image.new("RGBA", (FW, FH), (0, 0, 0, 0))


def head_x(im):
    """Centre of the head: the coloured (not pale steel) pixels in the upper part of the figure."""
    a = np.asarray(im).astype(int)
    top = a[int(im.height * 0.12):int(im.height * 0.45)]
    m = (top[..., 3] > 0) & (top[..., :3].min(2) < 170)
    return float(np.nonzero(m)[1].mean())


def sheet_frame(name):
    im = Image.open(os.path.join(FRAMES, name + ".png")).convert("RGBA")
    f = new()
    f.alpha_composite(im, (round(FW / 2 - head_x(im)), BASELINE + 1 - im.height))
    return f


def climb():
    f = new()
    cx = FW // 2
    rows = GRIDS["body_back"]
    cape = grid_img(rows[:14] + rows[8:14] + rows[14:])  # a longer cape
    f.alpha_composite(g("legs_back"), (cx - 15, 76))
    f.alpha_composite(cape, (cx - 19, 41))
    hb = g("head_back")
    f.alpha_composite(hb, (cx - hb.width // 2, 5))
    f.alpha_composite(g("arm_up"), (cx - 21, 34))
    f.alpha_composite(g("arm_up"), (cx + 15, 36))
    return f


def fallen():
    f = new()
    stone = Image.open(os.path.join(HERE, "fallen.png")).convert("RGBA")
    f.alpha_composite(stone, ((FW - stone.width) // 2, FH - stone.height))
    return f


def frames():
    fr = [sheet_frame(n) for n in ("idle1", "idle2", "idle3", "idle4", "walk1", "walk2", "walk3", "walk4", "run2")]
    c = climb()
    fr += [c, ImageOps.mirror(c)]
    fr += [sheet_frame(n) for n in ("attack1", "attack2", "hurt")]
    fr += [fallen()]
    return fr


def main():
    fr = frames()
    sheet = Image.new("RGBA", (FW * len(fr), FH), (0, 0, 0, 0))
    for i, x in enumerate(fr):
        sheet.alpha_composite(x, (i * FW, 0))
    sheet.save(OUT)
    print("wrote", os.path.normpath(OUT), sheet.size)


if __name__ == "__main__":
    main()
