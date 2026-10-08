#!/usr/bin/env python3
"""Build assets/sprites/hero.png from Cory's hero art.

hero_base.png is the character cut out of the reference image Cory supplied
(background removed, his outline kept, one pixel per art pixel, 68x85).
hero_base_nosword.png is the same with the sword taken out of his hand, for the
attack frames. hero.txt holds the hand-drawn extras in his palette: the back
view for climbing and the sword at other angles.

FRAMES (104x88 each, feet on row 86, facing right):
0-1 idle, 2-5 walk, 6 jump, 7-8 climb (back view), 9-11 attack, 12 fallen.

Run from anywhere: python3 tools/pixel_art/build_hero.py
"""
import os

from PIL import Image, ImageOps

from render import grid_img, load_all

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "sprites", "hero.png")
FW, FH = 104, 88
OX, OY = 16, 2  # where the 68x85 base sits in a frame: body centred, feet on row 86
HAND = (27, 55)  # his sword hand in base coordinates

GRIDS = load_all(os.path.join(HERE, "hero.txt"))
BASE = Image.open(os.path.join(HERE, "hero_base.png")).convert("RGBA")
NOSWORD = Image.open(os.path.join(HERE, "hero_base_nosword.png")).convert("RGBA")


def g(name):
    return grid_img(GRIDS[name])


def new():
    return Image.new("RGBA", (FW, FH), (0, 0, 0, 0))


def split(base):
    """Upper body, left boot and right boot as separate layers (base coordinates)."""
    upper, left, right = [Image.new("RGBA", base.size, (0, 0, 0, 0)) for _ in range(3)]
    src = base.load()
    for y in range(base.height):
        for x in range(base.width):
            p = src[x, y]
            if not p[3]:
                continue
            if y >= 71 and x <= 42:
                left.putpixel((x, y), p)
            elif y >= 70 and x >= 44:
                right.putpixel((x, y), p)
            else:
                upper.putpixel((x, y), p)
    return upper, left, right


def posed(base=BASE, dy=0, lx=0, ly=0, rx=0, ry=0, dx=0):
    """The base pose with the upper body bobbed by dy and each boot nudged."""
    upper, left, right = split(base)
    f = new()
    f.alpha_composite(left, (OX + dx + lx, OY + ly))
    f.alpha_composite(right, (OX + dx + rx, OY + ry))
    f.alpha_composite(upper, (OX + dx, OY + dy))
    return f


def attack(n):
    if n == 0:  # wind-up: sword drawn back, leaning back a pixel
        return posed(dx=-1)
    f = posed(NOSWORD, dx=1, lx=-1, rx=1)
    hx, hy = OX + 1 + HAND[0], OY + HAND[1]
    if n == 1:  # swing: blade straight out in front
        f.alpha_composite(g("sword_fwd"), (hx - 2, hy - 3))
    else:  # follow-through: blade angled down in front
        f.alpha_composite(g("sword_down"), (hx - 2, hy - 2))
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
    f.alpha_composite(stone, ((FW - stone.width) // 2, FH - 2 - stone.height + 2))
    return f


def frames():
    fr = [posed(), posed(dy=1)]
    fr += [posed(dy=1, lx=2, rx=-2), posed(), posed(dy=1, lx=-2, rx=2), posed()]
    fr += [posed(dy=-2, ly=-5, lx=1, ry=-3)]
    c = climb()
    fr += [c, ImageOps.mirror(c)]
    fr += [attack(i) for i in range(3)]
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
