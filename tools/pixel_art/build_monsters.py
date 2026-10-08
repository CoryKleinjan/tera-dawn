#!/usr/bin/env python3
"""Build the monster sheets from the hand-drawn pixel grids in monsters.txt.

Each monster is drawn once, facing right, in the same chibi style as the hero
(thick outlines, cel shading, big glossy eyes). This script only poses those
pixels for each animation frame (moving, hopping, dropping a row for a squash);
it draws nothing itself.

dewling.png      48x48 frames, 0-3 bounce cycle, feet on row 46
sproutcap.png    56x60 frames, 0-3 hop cycle, feet on row 58
emberboar.png    84x64 frames, 0-3 trot cycle, feet on row 62
emberboar_glow.png  the boar's flame pixels only, drawn additively for bloom

Run from anywhere: python3 tools/pixel_art/build_monsters.py
"""
import os

from PIL import Image

from pal_monsters import MPAL
from render import grid_img, load_all

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "sprites")
GRIDS = load_all(os.path.join(HERE, "monsters.txt"))
FLAME = set("1234")


def img(rows):
    return grid_img(rows, MPAL)


def save(frames, name):
    w, h = frames[0].size
    sheet = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, (i * w, 0))
    sheet.save(os.path.join(OUT, name))
    print("wrote", name, sheet.size)


def dewling():
    rows = GRIDS["dew"]
    squash = rows[:14] + rows[15:28] + rows[29:]  # two rows lower: a squashed bounce
    frames = []
    for grid, lift in ((rows, 0), (squash, 0), (rows, 3), (rows, 1)):
        f = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
        f.alpha_composite(img(grid), (8, 47 - len(grid) - lift))
        frames.append(f)
    save(frames, "dewling.png")


def sproutcap():
    body, feet = img(GRIDS["sprout"]), img(GRIDS["feet"])
    frames = []
    for lift in (0, 3, 6, 3):
        f = Image.new("RGBA", (56, 60), (0, 0, 0, 0))
        top = 59 - feet.height - lift
        spread = 1 if lift else 0
        left, right = feet.crop((0, 0, 15, feet.height)), feet.crop((15, 0, 30, feet.height))
        f.alpha_composite(left, (14 - spread, top))
        f.alpha_composite(right, (29 + spread, top))
        f.alpha_composite(body, (6, top - body.height + 1))
        frames.append(f)
    save(frames, "sproutcap.png")


def boar_body(t):
    rows = GRIDS["boar"]
    if t % 2:  # flicker: the flame tips lean one pixel back
        rows = [r[1:] + "." if y < 9 else r for y, r in enumerate(rows)]
    return rows


def emberboar():
    near, far = img(GRIDS["leg_near"]), img(GRIDS["leg_far"])
    frames, glows = [], []
    for t in range(4):
        st = (3, 0, -3, 0)[t]
        bob = 0 if st else 1
        f = Image.new("RGBA", (84, 64), (0, 0, 0, 0))
        f.alpha_composite(far, (22 - st, 55))
        f.alpha_composite(far, (54 + st, 55))
        rows = boar_body(t)
        f.alpha_composite(img(rows), (4, 14 + bob))
        f.alpha_composite(near, (16 + st, 54))
        f.alpha_composite(near, (48 - st, 54))
        frames.append(f)
        flames = ["".join(c if c in FLAME else "." for c in r) for r in rows]
        gf = Image.new("RGBA", (84, 64), (0, 0, 0, 0))
        gf.alpha_composite(img(flames), (4, 14 + bob))
        glows.append(gf)
    save(frames, "emberboar.png")
    save(glows, "emberboar_glow.png")


def main():
    dewling()
    sproutcap()
    emberboar()


if __name__ == "__main__":
    main()
