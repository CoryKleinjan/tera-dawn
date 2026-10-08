#!/usr/bin/env python3
"""Build assets/sprites/hero.png from the hand-drawn pixel grids in hero.txt.

Everything in hero.txt is drawn facing left, like the MapleStory reference; the
frames are mirrored to face right at the end. This script only places the parts
(head, torso, arms, legs, sword) for each pose; every pixel is in hero.txt.

FRAMES (104x84 each, feet on row 82, body centred, facing right):
0-1 idle, 2-5 walk, 6 jump, 7-8 climb (back view), 9-11 attack, 12 fallen.

Run from anywhere: python3 tools/pixel_art/build_hero.py
"""
import os

from PIL import Image, ImageOps

from render import grid_img, load_all

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "sprites", "hero.png")
FW, FH = 104, 84
BX = 24  # shifts the facing-left layout so the body sits in the middle of the frame

GRIDS = load_all(os.path.join(HERE, "hero.txt"))
_cache = {}


def g(name, flip=None):
    if (name, flip) not in _cache:
        im = grid_img(GRIDS[name])
        if flip == "h":
            im = ImageOps.mirror(im)
        elif flip == "v":
            im = ImageOps.flip(im)
        _cache[(name, flip)] = im
    return _cache[(name, flip)]


def new():
    return Image.new("RGBA", (FW, FH), (0, 0, 0, 0))


def put(f, im, x, y):
    x += BX
    if x < 0:
        im = im.crop((-x, 0, im.width, im.height))
        x = 0
    f.alpha_composite(im, (x, y))


def front(legs="legs_stand", dy=0, sx=0, legs_dy=0):
    f = new()
    put(f, g("sword_diag"), 5 + sx, 46 + dy)
    put(f, g(legs), 14, 69 + legs_dy)
    put(f, g("torso_idle"), 14, 50 + dy)
    put(f, g("head"), 5, 1 + dy)
    return f


def attack(n):
    f = new()
    if n == 0:  # wind-up: sword drawn back behind the body
        put(f, g("sword_horiz", "h"), 28, 57)
        put(f, g("legs_walkA"), 14, 69)
        put(f, g("torso_noarm"), 14, 50)
        put(f, g("arm_back"), 21, 57)
        put(f, g("head"), 4, 2)
    elif n == 1:  # swing: sword straight out in front
        put(f, g("legs_walkA"), 14, 69)
        put(f, g("torso_noarm"), 14, 50)
        put(f, g("head"), 4, 2)
        put(f, g("sword_horiz"), -11, 55)
        put(f, g("arm_fwd"), 15, 56)
    else:  # follow-through: sword angled down in front
        put(f, g("legs_walkA"), 14, 69)
        put(f, g("torso_noarm"), 14, 50)
        put(f, g("head"), 4, 2)
        put(f, g("sword_diag", "v"), 4, 58)
        put(f, g("arm_down"), 16, 57)
    return f


def climb():
    f = new()
    cx = FW // 2
    ox = cx - 14
    f.alpha_composite(g("legs_climb"), (ox, 66))
    f.alpha_composite(g("torso_back"), (ox, 50))
    hb = g("head_back")
    f.alpha_composite(hb, (cx - hb.width // 2, 3))
    f.alpha_composite(g("arm_climb_hi"), (ox + 2, 47))
    f.alpha_composite(g("arm_climb_lo"), (ox + 21, 51))
    return f


def fallen():
    f = new()
    f.alpha_composite(Image.open(os.path.join(HERE, "fallen.png")).convert("RGBA"), ((FW - 72) // 2, 0))
    return f


def frames():
    fr = [front(), front(dy=1)]
    fr += [front("legs_walkA", dy=1, sx=1), front("legs_pass"), front("legs_walkB", dy=1, sx=-1), front("legs_pass")]
    fr += [front("legs_jump", dy=-1, legs_dy=-1)]
    fr = [ImageOps.mirror(x) for x in fr]
    c = climb()
    fr += [c, ImageOps.mirror(c)]
    fr += [ImageOps.mirror(attack(i)) for i in range(3)]
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
