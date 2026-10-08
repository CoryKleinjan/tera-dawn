#!/usr/bin/env python3
"""Generates the placeholder pixel-art sprite sheets in assets/sprites/.

The style follows classic MapleStory sprites: chibi proportions (the head is about
half the character), big glossy eyes, a dark outline around every shape, and soft
cel shading in three or four tones lit from the upper left. One texel is one game
pixel. Shapes are drawn back to front; each part gets its own outline so that
overlapping parts stay readable.

The art is meant to be replaced by hand-made sprites with the same frame sizes and
frame order (listed in each function's docstring).

    python3 tools/make_placeholder_art.py
"""
import math
import os
import random

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
INK = "1c1224"  # outline


def rgba(s, a=255):
    s = s.lstrip("#")
    return np.array([int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a], dtype=np.uint8)


def ramp(base, shade, deep, hi):
    return [rgba(deep), rgba(shade), rgba(base), rgba(hi)]


def _blur(m, r):
    out = m.astype(np.float32)
    for _ in range(2):
        p = np.pad(out, r, mode="constant")
        c = np.cumsum(np.cumsum(p, 0), 1)
        c = np.pad(c, ((1, 0), (1, 0)))
        k = 2 * r + 1
        out = (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)
    return out


class Shape:
    """A filled region built from primitives, drawn with cel shading and an outline."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        yy, xx = np.mgrid[0:h, 0:w]
        self.xx, self.yy = xx + 0.5, yy + 0.5
        self.m = np.zeros((h, w), dtype=bool)

    def ellipse(self, cx, cy, rx, ry, add=True):
        e = ((self.xx - cx) / rx) ** 2 + ((self.yy - cy) / ry) ** 2 <= 1.0
        self.m = self.m | e if add else self.m & ~e
        return self

    def rect(self, x, y, w, h, add=True):
        r = (self.xx >= x) & (self.xx < x + w) & (self.yy >= y) & (self.yy < y + h)
        self.m = self.m | r if add else self.m & ~r
        return self

    def poly(self, pts, add=True):
        inside = np.zeros_like(self.m)
        n = len(pts)
        for i in range(n):
            (ax, ay), (bx, by) = pts[i], pts[(i + 1) % n]
            cond = ((ay <= self.yy) & (self.yy < by)) | ((by <= self.yy) & (self.yy < ay))
            with np.errstate(divide="ignore", invalid="ignore"):
                xint = ax + (self.yy - ay) * (bx - ax) / (by - ay)
            inside ^= cond & (self.xx < xint)
        self.m = self.m | inside if add else self.m & ~inside
        return self

    def line(self, x0, y0, x1, y1, width):
        dx, dy = x1 - x0, y1 - y0
        L2 = dx * dx + dy * dy or 1
        t = np.clip(((self.xx - x0) * dx + (self.yy - y0) * dy) / L2, 0, 1)
        d = np.hypot(self.xx - (x0 + t * dx), self.yy - (y0 + t * dy))
        self.m |= d <= width / 2.0
        return self

    def clip(self, other):
        self.m &= other.m
        return self

    def cut(self, other):
        self.m &= ~other.m
        return self


class Frame:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 4), dtype=np.uint8)

    def shape(self):
        return Shape(self.w, self.h)

    def draw(self, s, tones, outline=True, soft=None, flat=False, ink=INK, vgrad=0.5):
        m = s.m
        if not m.any():
            return
        if outline:
            ring = np.zeros_like(m)
            ring[1:, :] |= m[:-1, :]
            ring[:-1, :] |= m[1:, :]
            ring[:, 1:] |= m[:, :-1]
            ring[:, :-1] |= m[:, 1:]
            ring &= ~m
            self.px[ring] = rgba(ink)
        if flat:
            self.px[m] = tones[2] if len(tones) > 2 else tones[0]
            return
        ys, xs = np.nonzero(m)
        size = max(ys.max() - ys.min(), xs.max() - xs.min()) + 1
        r = soft or max(1, int(size / 7))
        b = _blur(m, r)
        gx = np.zeros_like(b)
        gy = np.zeros_like(b)
        gx[:, 1:-1] = b[:, 2:] - b[:, :-2]
        gy[1:-1, :] = b[2:, :] - b[:-2, :]
        n = np.hypot(gx, gy) + 1e-6
        # outward normal is -grad; light comes from the upper left
        lit = ((-gx / n) * -0.6 + (-gy / n) * -0.8) * np.clip(n * r * 1.2, 0, 1)
        top, bot = ys.min(), ys.max() + 1
        lit = lit - ((np.arange(self.h)[:, None] - top) / max(1, bot - top) - 0.4) * vgrad
        idx = np.full(m.shape, 2)
        idx[lit < -0.18] = 1
        idx[lit < -0.55] = 0
        idx[lit > 0.38] = 3
        for i in range(4):
            sel = m & (idx == i)
            self.px[sel] = tones[i]

    def put(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y, x] = rgba(c) if isinstance(c, str) else c

    def image(self):
        return Image.fromarray(self.px, "RGBA")


def save(img, name):
    img.save(os.path.join(OUT, name))
    print("wrote", name, img.size)


def sheet(frames, name):
    w, h = frames[0].w, frames[0].h
    img = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        img.paste(f.image(), (i * w, 0))
    save(img, name)


# ---------------------------------------------------------------- palettes

SKIN = ramp("ffe0c8", "f5b896", "d98a72", "fff3e8")
HAIR = ramp("ff9a3c", "e06a28", "a8461e", "ffc879")
TUNIC = ramp("ff7a5a", "d9483f", "9a2a38", "ffae8a")
CLOTH = ramp("fff6ea", "dcd2e6", "b0a4c8", "ffffff")
PANTS = ramp("5b4a8a", "3f3268", "2a2048", "7a6ab0")
BOOT = ramp("8a5a43", "6b4433", "4a2c22", "b07a58")
GOLD = ramp("ffd166", "e0a040", "b07028", "fff0a8")
STEEL = ramp("eef2ff", "b6c2ee", "7a86c8", "ffffff")
WOOD = ramp("9a6a4a", "7a4e36", "583424", "c08a62")


def eye(f, x, y, w, h, iris_top="1e4a9a", iris_bot="58c8ff", narrow=False):
    """A small eye for monsters. (x, y) is the top-left of the iris."""
    for j in range(h):
        t = j / max(1, h - 1)
        c = np.array(rgba(iris_top), dtype=float) * (1 - t) + np.array(rgba(iris_bot), dtype=float) * t
        for i in range(w):
            f.put(x + i, y + j, c.astype(np.uint8))
    for j in range(2, h - 2):
        f.put(x + w // 2, y + j, rgba("0e1a3a"))
        if w > 3:
            f.put(x + w // 2 - 1, y + j, rgba("16285a"))
    for i in range(-1, w + 1):
        f.put(x + i, y - 1, rgba(INK))
        f.put(x + i, y - 2, rgba(INK))
    if not narrow:
        f.put(x + w + 1, y - 2, rgba(INK))
        f.put(x + w + 1, y - 3, rgba(INK))
    for j in range(h // 2):
        f.put(x + w, y + j, rgba(INK))
    for i in range(1, w):
        f.put(x + i, y + h, rgba("b06a6a"))
    f.put(x, y, rgba("ffffff"))
    f.put(x + 1, y, rgba("ffffff"))
    f.put(x, y + 1, rgba("ffffff"))
    f.put(x + 1, y + 1, rgba("ffffff"))
    f.put(x + w - 1, y + h - 2, rgba("ffffff"))


# Hand-placed anime eye for the hero, 7 wide x 12 tall including lids. Facing right:
# "near" is the eye closer to the viewer, "far" is narrower. Characters:
# K lash/outline, k soft lid, W white, 1-5 iris from darkest to lightest, p pupil, . skin (untouched)
HERO_EYE_NEAR = [
    "KKKKKKKK.",
    ".KKKKKKKK",
    "kW11111K.",
    "kWW1112K.",
    ".W22pp2K.",
    ".222pp3W.",
    ".233pp3..",
    ".3334443.",
    ".3444554.",
    ".4455W55.",
    "..k55555.",
    "...kkkk..",
]
HERO_EYE_FAR = [
    "KKKKKKK",
    "KKKKKK.",
    "WW1111K",
    "W1112K.",
    "22pp2K.",
    "22pp3W.",
    "23pp3..",
    "33443..",
    "34454..",
    "4455W..",
    "k5555..",
    ".kkkk..",
]
EYE_COLORS = {"K": "1c1224", "k": "6a3a4a", "W": "ffffff", "1": "16245a", "2": "1f4aa0", "3": "2f7ad8",
              "4": "4aaeee", "5": "8ae4ff", "p": "0a1230"}


def stamp(f, x, y, rows, colors):
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch in colors:
                f.put(x + i, y + j, colors[ch])


def strand(f, p0, p1, p2, col, only, width=1):
    """Paints a quadratic Bezier strand, only over pixels whose color is in `only`."""
    only = [tuple(c[:3]) for c in only]
    c = rgba(col) if isinstance(col, str) else col
    for k in range(60):
        t = k / 59
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        for dx in range(width):
            xi, yi = int(x) + dx, int(y)
            if 0 <= xi < f.w and 0 <= yi < f.h and tuple(f.px[yi, xi][:3]) in only:
                f.px[yi, xi] = c


# ---------------------------------------------------------------- hero

HERO_W, HERO_H = 72, 84
HAIR_SHINE = rgba("ffe0a8")


def hero_head(f, hx, hy, back=False):
    """The head: about 60% of the character's height. (hx, hy) is the centre of the hair mass."""
    if back:
        tail = f.shape().ellipse(hx - 1, hy + 20, 7, 11).ellipse(hx - 1, hy + 31, 6, 5)
        f.draw(tail, HAIR, soft=3)
        hair = f.shape().ellipse(hx, hy, 22, 21)
        hair.poly([(hx - 6, hy - 18), (hx - 1, hy - 28), (hx + 3, hy - 18)])
        hair.poly([(hx + 4, hy - 18), (hx + 13, hy - 25), (hx + 11, hy - 14)])
        f.draw(hair, HAIR, soft=5, vgrad=0.3)
        for (x0, y0, x1, y1) in [(hx - 8, hy - 14, hx - 10, hy + 14), (hx + 1, hy - 18, hx, hy + 18), (hx + 9, hy - 14, hx + 11, hy + 14)]:
            st = f.shape().line(x0, y0, x1, y1, 1.0)
            f.draw(st, [HAIR[1]] * 4, outline=False, flat=True)
        band = f.shape().rect(hx - 4, hy + 15, 6, 4)
        f.draw(band, GOLD, flat=True)
        return
    # ponytail at the back of the head (left side, since the hero faces right)
    tail = f.shape().ellipse(hx - 22, hy + 4, 7, 12).ellipse(hx - 21, hy + 17, 6.5, 6)
    tail.poly([(hx - 14, hy - 14), (hx - 6, hy - 10), (hx - 22, hy + 6), (hx - 28, hy)])
    f.draw(tail, HAIR, soft=3)
    band = f.shape().ellipse(hx - 16, hy - 9, 3, 3)
    f.draw(band, GOLD, soft=1)
    # face
    face = f.shape().ellipse(hx + 2, hy + 7, 17, 14.5)
    f.draw(face, ramp("fff0e4", "fbd2b8", "f5c0a2", "fffaf4"), soft=8, vgrad=0.0)
    # hair: one outlined mass (crown, cowlick, bangs, side locks) so the bangs have a jagged edge
    hair = f.shape().ellipse(hx, hy - 2, 22, 19)
    opening = f.shape().ellipse(hx + 2, hy + 7, 17, 14.5)
    opening.rect(0, 0, 200, hy - 1, add=False)
    hair.cut(opening)  # the face shows below the bangs line
    hair.poly([(hx + 1, hy - 19), (hx + 7, hy - 26), (hx + 9, hy - 18)])  # cowlick
    tips = [(hx - 9, hy + 9), (hx - 2, hy + 4), (hx + 3, hy + 9), (hx + 9, hy + 4), (hx + 15, hy + 7)]
    xs = [hx - 13, hx - 5, hx + 1, hx + 6, hx + 12, hx + 18]
    for k, (tx, ty) in enumerate(tips):
        hair.poly([(xs[k], hy - 2), (xs[k + 1], hy - 2), (tx, ty)])
    hair.poly([(hx - 21, hy - 4), (hx - 10, hy - 4), (hx - 12, hy + 12), (hx - 17, hy + 19)])  # back side lock
    hair.poly([(hx + 14, hy - 4), (hx + 21, hy - 6), (hx + 21, hy + 10), (hx + 19, hy + 18)])  # front side lock
    f.draw(hair, HAIR, soft=5, vgrad=0.35)
    for k, (tx, ty) in enumerate(tips[:-1]):  # strand separations
        sep = f.shape().line(xs[k + 1], hy - 4, xs[k + 1] + (tx - xs[k + 1]) * 0.2, hy + 1, 1.0)
        f.draw(sep, [HAIR[1]] * 4, outline=False, flat=True)
    # shine band across the top of the hair
    shine = f.shape().ellipse(hx - 2, hy + 6, 20, 19)
    shine.cut(f.shape().ellipse(hx - 2, hy + 7, 18, 17))
    shine.rect(0, hy - 6, 200, 200, add=False)
    shine.rect(0, 0, hx - 15, 200, add=False)
    sel = shine.m & np.all(f.px == HAIR[2], axis=2) | shine.m & np.all(f.px == HAIR[3], axis=2)
    f.px[sel] = HAIR_SHINE
    # hair strands: shade lines fanning from the crown, each with a light edge on its lit side
    hair_tones = [HAIR[1], HAIR[2], HAIR[3], HAIR_SHINE]
    crown = (hx + 2, hy - 17)
    for (mx, my, ex_, ey_) in [(hx - 12, hy - 12, hx - 17, hy + 17), (hx - 8, hy - 8, hx - 10, hy + 10),
                               (hx - 3, hy - 8, hx - 2, hy + 4), (hx + 2, hy - 8, hx + 3, hy + 8),
                               (hx + 8, hy - 8, hx + 9, hy + 4), (hx + 14, hy - 9, hx + 15, hy + 6),
                               (hx + 19, hy - 6, hx + 20, hy + 15), (hx - 16, hy - 14, hx - 22, hy - 2)]:
        strand(f, (crown[0] - 1, crown[1] + 1), (mx - 1, my), (ex_ - 1, ey_), HAIR[3], hair_tones)
        strand(f, crown, (mx, my), (ex_, ey_), HAIR[1], hair_tones)
    for (x0, y0, x1, y1, x2, y2) in [(hx - 26, hy - 2, hx - 28, hy + 8, hx - 23, hy + 20),
                                     (hx - 20, hy - 6, hx - 22, hy + 6, hx - 19, hy + 19)]:
        strand(f, (x0, y0), (x1, y1), (x2, y2), HAIR[1], hair_tones)
    for yy in range(hy + 2, hy + 10):  # shadow under the bangs where they meet the face
        for xx in range(hx - 12, hx + 22):
            if tuple(f.px[yy, xx][:3]) == tuple(rgba(INK)[:3]) and yy + 1 < f.h:
                below = f.px[yy + 1, xx]
                if tuple(below[:3]) in [tuple(c[:3]) for c in ramp("fff0e4", "fbd2b8", "f5c0a2", "fffaf4")]:
                    f.px[yy + 1, xx] = rgba("f0b8a0")
    # eyes: huge and low on the face
    ey = hy + 3
    stamp(f, hx - 6, ey, HERO_EYE_NEAR, EYE_COLORS)
    stamp(f, hx + 6, ey, HERO_EYE_FAR, EYE_COLORS)
    # nose, mouth, blush
    f.put(hx + 4, ey + 11, "e8a088")
    f.put(hx + 3, ey + 14, "8a3a4a")
    f.put(hx + 4, ey + 14, "8a3a4a")
    f.put(hx + 5, ey + 14, "c06070")
    f.put(hx + 4, ey + 15, "f08a98")
    for (bx_, by_, c_) in [(hx - 6, ey + 13, "ff9aa8"), (hx - 5, ey + 13, "ffb4bc"), (hx - 4, ey + 13, "ff9aa8"),
                           (hx + 10, ey + 13, "ff9aa8"), (hx + 11, ey + 13, "ffb4bc")]:
        f.put(bx_, by_, c_)


def hero_frame(pose="idle", t=0):
    """FRAMES (hero.png, 72x84 each, feet on row 82, facing right):
    0-1 idle, 2-5 walk, 6 jump, 7-8 climb, 9-11 attack, 12 fallen."""
    f = Frame(HERO_W, HERO_H)
    foot = 82
    cx = 35
    bob = 0
    lf = rf = 0
    lift_b = lift_f = 0
    if pose == "idle":
        bob = t % 2
    elif pose == "walk":
        lf, rf = [(-3, 3), (-1, 1), (3, -3), (1, -1)][t]
        lift_b, lift_f = [(0, 2), (2, 0), (2, 0), (0, 2)][t]
        bob = [0, 1, 0, 1][t]
    elif pose == "jump":
        lf, rf, lift_b, lift_f = -2, 3, 4, 2
    elif pose == "attack":
        lf, rf = -3, 4
        bob = [0, 1, 1][t]

    if pose == "fallen":
        stone = f.shape().rect(cx - 13, foot - 26, 26, 26).ellipse(cx, foot - 26, 13, 10)
        f.draw(stone, ramp("d6cce6", "aa9cc6", "7a6a9a", "f4f0fa"))
        for (x0, y0, x1, y1) in [(cx - 7, foot - 20, cx - 7, foot - 11), (cx - 3, foot - 20, cx - 3, foot - 11),
                                 (cx + 1, foot - 20, cx + 1, foot - 11), (cx + 1, foot - 20, cx + 5, foot - 20),
                                 (cx + 5, foot - 20, cx + 5, foot - 16), (cx + 1, foot - 16, cx + 5, foot - 16),
                                 (cx + 3, foot - 16, cx + 6, foot - 11)]:
            s_ = f.shape().line(x0, y0, x1, y1, 1.6)
            f.draw(s_, [rgba("5b4682")] * 4, outline=False, flat=True)
        grass = f.shape()
        for i in range(-16, 17, 4):
            grass.poly([(cx + i - 2, foot + 1), (cx + i + 2, foot + 1), (cx + i + (1 if i % 8 else -1), foot - 5)])
        f.draw(grass, ramp("8fd16a", "5e9a45", "3f7a3a", "c3ef8e"))
        return f

    climb = pose == "climb"
    waist = foot - 15 - bob  # bottom of the tunic
    neck = foot - 30 - bob   # top of the tunic
    hx, hy = cx - 1, neck - 22

    def leg(x, lift):
        l = f.shape().rect(x, waist - 2, 5, foot - 5 - lift - (waist - 2))
        f.draw(l, PANTS, soft=1)
        b = f.shape().rect(x - 1, foot - 7 - lift, 7, 6).ellipse(x + 5, foot - 3 - lift, 3.5, 3)
        f.draw(b, BOOT, soft=2)
        cuff = f.shape().rect(x - 1, foot - 8 - lift, 7, 2)
        f.draw(cuff, GOLD, outline=False, flat=True)
        f.put(x + 1, waist + 3, PANTS[3])  # knee highlight
        f.put(x + 1, waist + 4, PANTS[3])
        f.put(x + 5, foot - 4 - lift, BOOT[3])  # toe shine
        f.put(x + 6, foot - 4 - lift, BOOT[3])
        for xx in range(x - 1, x + 8):  # sole
            if f.px[foot - 2 - lift, xx, 3]:
                f.put(xx, foot - 2 - lift, "3a2418")
        f.put(x + 1, foot - 6 - lift, BOOT[0])  # laces
        f.put(x + 3, foot - 6 - lift, BOOT[0])

    if climb:
        a = 2 if t == 0 else -2
        leg(cx - 6, a + 2)
        leg(cx + 1, -a + 2)
    else:
        # back arm, mostly hidden behind the body
        arm_b = f.shape().line(cx - 6, neck + 3, cx - 9, neck + 11, 4)
        f.draw(arm_b, SKIN, soft=1)
        leg(cx - 6 + lf, lift_b)
        leg(cx + 1 + rf, lift_f)

    torso = f.shape().poly([(cx - 7, neck), (cx + 7, neck), (cx + 9, waist - 5), (cx + 12, waist),
                            (cx - 12, waist), (cx - 9, waist - 5)])
    f.draw(torso, TUNIC, soft=3)
    collar = f.shape().poly([(cx - 4, neck), (cx + 4, neck), (cx, neck + 4)])
    f.draw(collar, CLOTH, outline=False, flat=True)
    belt = f.shape().rect(cx - 10, waist - 6, 20, 2)
    f.draw(belt, GOLD, outline=False, flat=True)
    tunic_tones = [TUNIC[1], TUNIC[2], TUNIC[3]]
    for (x0, x1) in [(cx - 4, cx - 7), (cx + 3, cx + 6), (cx - 1, cx - 1)]:  # skirt folds
        strand(f, (x0, waist - 4), ((x0 + x1) / 2, waist - 2), (x1, waist), TUNIC[0], tunic_tones)
    strand(f, (cx - 6, neck + 2), (cx - 7, neck + 6), (cx - 7, waist - 7), TUNIC[3], tunic_tones)
    for (xx, yy, c_) in [(cx - 2, waist - 6, "b07028"), (cx + 1, waist - 6, "b07028"), (cx - 2, waist - 5, "b07028"),
                         (cx + 1, waist - 5, "b07028"), (cx - 1, waist - 6, "fff6c8"), (cx, waist - 5, "fff6c8")]:
        f.put(xx, yy, c_)  # buckle
    for (xx, yy) in [(cx, neck + 6), (cx, neck + 9)]:  # buttons
        f.put(xx, yy, "ffd166")

    if climb:
        a = -2 if t == 0 else 2
        for (x, dy) in ((cx - 11, a), (cx + 7, -a)):
            arm = f.shape().rect(x, neck - 9 + dy, 4, 12)
            f.draw(arm, SKIN, soft=1)
            sl = f.shape().rect(x - 1, neck + dy, 6, 4)
            f.draw(sl, TUNIC, soft=1)
        hero_head(f, hx + 1, hy, back=True)
        return f

    hero_head(f, hx, hy)

    # front arm and sword, drawn over the body
    sx, sy = cx + 5, neck + 3
    if pose in ("idle", "walk"):
        hx2, hy2 = sx + 4, sy + 8 + (bob if pose == "walk" else 0)
        blade_ang = -0.5 if pose == "idle" else -0.4
    elif pose == "jump":
        hx2, hy2 = sx + 5, sy - 2
        blade_ang = -1.3
    else:
        arm_ang = [-2.2, -0.2, 0.8][t]
        hx2, hy2 = sx + math.cos(arm_ang) * 7, sy + math.sin(arm_ang) * 7
        blade_ang = [-2.4, -0.15, 0.85][t]
    L = 24
    bx, by = hx2 + math.cos(blade_ang) * 3, hy2 + math.sin(blade_ang) * 3
    ex, ey = hx2 + math.cos(blade_ang) * L, hy2 + math.sin(blade_ang) * L
    blade = f.shape().line(bx, by, ex, ey, 3.5)
    blade.poly([(ex + math.cos(blade_ang) * 4, ey + math.sin(blade_ang) * 4),
                (ex - math.sin(blade_ang) * 1.8, ey + math.cos(blade_ang) * 1.8),
                (ex + math.sin(blade_ang) * 1.8, ey - math.cos(blade_ang) * 1.8)])
    f.draw(blade, STEEL, soft=1)
    px_, py_ = -math.sin(blade_ang), math.cos(blade_ang)
    guard = f.shape().line(bx - px_ * 4, by - py_ * 4, bx + px_ * 4, by + py_ * 4, 3)
    f.draw(guard, GOLD, soft=1)
    arm = f.shape().line(sx, sy, hx2, hy2, 4)
    f.draw(arm, SKIN, soft=1)
    hand = f.shape().ellipse(hx2, hy2, 2.8, 2.8)
    f.draw(hand, SKIN, soft=1)
    sleeve = f.shape().ellipse(sx, sy, 3.5, 3.5)
    f.draw(sleeve, TUNIC, soft=1)
    return f


def hero():
    frames = [hero_frame("idle", 0), hero_frame("idle", 1)]
    frames += [hero_frame("walk", i) for i in range(4)]
    frames += [hero_frame("jump")]
    frames += [hero_frame("climb", 0), hero_frame("climb", 1)]
    frames += [hero_frame("attack", i) for i in range(3)]
    frames += [hero_frame("fallen")]
    sheet(frames, "hero.png")


# ---------------------------------------------------------------- monsters

def face_dots(f, x, y, gap, h=5, mouth=True):
    for ex in (x, x + gap):
        for j in range(h):
            f.put(ex, y + j, INK)
            f.put(ex + 1, y + j, INK)
        f.put(ex, y, "ffffff")
    if mouth:
        f.put(x + gap // 2, y + h + 2, INK)
        f.put(x + gap // 2 + 1, y + h + 2, INK)
        f.put(x + gap // 2 - 1, y + h + 1, INK)
        f.put(x + gap // 2 + 2, y + h + 1, INK)


def dewling():
    """dewling.png: 48x48 frames, 0-3 bounce cycle. Feet on row 46."""
    frames = []
    tones = ramp("7fe6dc", "3fb8b4", "1f7e8a", "d4fff8")
    for t in range(4):
        f = Frame(48, 48)
        sq = [0.0, 0.1, 0.0, -0.1][t]
        rx, ry = 18 * (1 + sq), 15 * (1 - sq)
        base = 46
        body = f.shape().ellipse(24, base - ry, rx, ry)
        body.poly([(24 - rx * 0.62, base - ry * 1.35), (24 + rx * 0.3, base - ry * 1.5), (21, base - ry * 2 - 12 * (1 - sq))])
        f.draw(body, tones)
        cy = int(base - ry)
        gloss = f.shape().ellipse(14, cy - 6, 3, 5)
        f.draw(gloss, [rgba("ffffff")] * 4, outline=False, flat=True)
        eye(f, 26, cy - 2, 3, 6, iris_top="0e1a3a", iris_bot="2a4a8a", narrow=True)
        eye(f, 34, cy - 2, 3, 6, iris_top="0e1a3a", iris_bot="2a4a8a", narrow=True)
        f.put(31, cy + 7, INK)
        f.put(32, cy + 7, INK)
        f.put(23, cy + 6, "ff9ab0")
        f.put(24, cy + 6, "ff9ab0")
        f.put(39, cy + 6, "ff9ab0")
        frames.append(f)
    sheet(frames, "dewling.png")


def sproutcap():
    """sproutcap.png: 56x60 frames, 0-3 hop cycle. Feet on row 58."""
    frames = []
    for t in range(4):
        f = Frame(56, 60)
        lift = [0, 3, 6, 3][t]
        base = 58 - lift
        feet = f.shape()
        spread = 2 if lift else 0
        feet.ellipse(19 - spread, base - 2, 6, 3).ellipse(37 + spread, base - 2, 6, 3)
        f.draw(feet, ramp("c9a07a", "a07a5a", "7a5a40", "e8c8a0"))
        stem = f.shape().ellipse(28, base - 13, 13, 12.5)
        f.draw(stem, ramp("fbe8d0", "e8c8a4", "c49a78", "fffaf0"))
        cap = f.shape().ellipse(28, base - 24, 24, 15)
        cap.rect(0, base - 21, 56, 30, add=False)
        cap.ellipse(28, base - 22, 22, 4)
        f.draw(cap, ramp("ff6a5a", "e0404a", "a82438", "ffa08a"))
        for (x, y, r) in [(15, base - 31, 3.6), (31, base - 35, 3.2), (42, base - 27, 2.6), (24, base - 26, 2.0)]:
            spot = f.shape().ellipse(x, y, r, r * 0.85)
            f.draw(spot, ramp("fff8ee", "eadce8", "cbbcd6", "ffffff"), outline=False)
        stalk = f.shape().line(28, base - 38, 28, base - 44, 2)
        f.draw(stalk, ramp("5ea84a", "3f8a3a", "2a6a2a", "8fd16a"), outline=True, flat=True)
        leaf = f.shape().ellipse(21, base - 46, 7, 3.5).ellipse(35, base - 47, 7, 3.5)
        f.draw(leaf, ramp("8fe06a", "5eb04a", "3f8a3a", "c8ff9a"))
        ey = base - 17
        eye(f, 29, ey, 3, 6, iris_top="0e1a3a", iris_bot="3a2a5a", narrow=True)
        eye(f, 37, ey, 3, 6, iris_top="0e1a3a", iris_bot="3a2a5a", narrow=True)
        f.put(34, ey + 9, INK)
        f.put(35, ey + 9, INK)
        f.put(27, ey + 8, "ff9ab0")
        f.put(42, ey + 8, "ff9ab0")
        frames.append(f)
    sheet(frames, "sproutcap.png")


def emberboar(glow=False):
    """emberboar.png: 84x64 frames, 0-3 trot cycle. Feet on row 62.
    emberboar_glow.png holds only the flame pixels, drawn additively for bloom."""
    frames = []
    FUR = ramp("a8684a", "84503a", "5e3428", "d08e68")
    FLAME = ramp("ffb347", "ff7a3c", "e0482a", "fff0a0")
    for t in range(4):
        f = Frame(84, 64)
        base = 62
        st = [3, 0, -3, 0][t]
        flames = f.shape()
        for i in range(7):
            x = 20 + i * 7
            hgt = 12 + ((i * 7 + t * 3) % 6) * 2
            flames.poly([(x - 5, base - 34), (x + 6, base - 34), (x + 2 + (t % 2) * 2, base - 34 - hgt)])
        core = f.shape()
        for i in range(7):
            x = 20 + i * 7
            core.ellipse(x + 1, base - 37, 2.2, 3.5)
        if glow:
            f.draw(flames, FLAME, outline=False)
            f.draw(core, [rgba("fff6c8")] * 4, outline=False, flat=True)
            frames.append(f)
            continue
        tail = f.shape().line(14, base - 30, 7, base - 36, 2.5)
        f.draw(tail, FUR, soft=1)
        for lx, o in ((20, st), (30, -st), (48, -st), (58, st)):
            leg = f.shape().rect(lx + o // 2, base - 16, 8, 14)
            f.draw(leg, ramp("6b4433", "4a2c22", "2e1a14", "8a5a43"))
            hoof = f.shape().rect(lx + o // 2, base - 4, 8, 4)
            f.draw(hoof, ramp("3a2a2a", "2a1a1a", "1a1010", "5a4a4a"), flat=True)
        f.draw(flames, FLAME)
        f.draw(core, [rgba("fff6c8")] * 4, outline=False, flat=True)
        body = f.shape().ellipse(38, base - 24, 26, 15)
        f.draw(body, FUR)
        belly = f.shape().ellipse(40, base - 15, 16, 5)
        belly.clip(body)
        f.draw(belly, ramp("d8a888", "c08a68", "a87050", "f0c8a8"), outline=False)
        head = f.shape().ellipse(62, base - 24, 14, 13)
        f.draw(head, FUR)
        ear = f.shape().poly([(55, base - 34), (62, base - 33), (55, base - 44)])
        f.draw(ear, FUR, soft=1)
        snout = f.shape().ellipse(74, base - 18, 7, 6)
        f.draw(snout, ramp("f0b898", "d8987a", "b07058", "ffd8c0"))
        tusk = f.shape().poly([(70, base - 13), (75, base - 13), (77, base - 24)])
        f.draw(tusk, ramp("fffaf0", "e8dcc8", "c0b098", "ffffff"), soft=1)
        f.put(75, base - 19, INK)
        f.put(76, base - 19, INK)
        brow = f.shape().line(60, base - 31, 68, base - 28, 2)
        f.draw(brow, [rgba(INK)] * 4, outline=False, flat=True)
        eye(f, 64, base - 27, 3, 5, iris_top="ffd166", iris_bot="ff7a3c", narrow=True)
        frames.append(f)
    sheet(frames, "emberboar_glow.png" if glow else "emberboar.png")


# ---------------------------------------------------------------- items and props

def shard():
    """shard.png: one 20x26 Dawnshard gem."""
    f = Frame(20, 26)
    g = f.shape().poly([(10, 1), (18.5, 11), (10, 24.5), (1.5, 11)])
    f.draw(g, ramp("ffd166", "ff9a4a", "e0603a", "fff6c8"), ink="7a2e1a")
    facet = f.shape().poly([(10, 4), (14, 11), (10, 20), (6, 11)])
    f.draw(facet, ramp("ffe9a0", "ffc070", "ff9a4a", "fffbe8"), outline=False)
    for x, y in [(7, 7), (7, 8), (8, 6), (6, 9)]:
        f.put(x, y, "ffffff")
    save(f.image(), "shard.png")


def soft_dot(name, size, falloff=2.0):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / (size / 2)
            a = max(0.0, 1.0 - d) ** falloff
            img.putpixel((x, y), (255, 255, 255, int(a * 255)))
    save(img, name)


def blob_shadow():
    img = Image.new("RGBA", (48, 18), (0, 0, 0, 0))
    for y in range(18):
        for x in range(48):
            dx = (x + 0.5 - 24) / 24
            dy = (y + 0.5 - 9) / 9
            d = dx * dx + dy * dy
            if d < 1:
                img.putpixel((x, y), (20, 10, 30, int(160 * (1 - d) ** 0.6)))
    save(img, "blob_shadow.png")


def tree(name, leaf, trunk=WOOD, seed=1, dead=False, blossoms=None):
    """A 128x180 tree: rounded outlined leaf clumps on a curved trunk."""
    rnd = random.Random(seed)
    f = Frame(128, 180)
    tr = f.shape()
    tr.poly([(54, 179), (74, 179), (70, 150), (68, 100), (62, 80), (58, 100), (58, 150)])
    tr.poly([(46, 179), (82, 179), (74, 170), (54, 170)])
    if dead:
        for (x0, y0, x1, y1, w) in [(63, 110, 34, 70, 6), (65, 100, 96, 62, 6), (63, 85, 52, 40, 5), (66, 84, 82, 34, 5),
                                    (34, 70, 20, 62, 3), (96, 62, 110, 52, 3), (52, 40, 46, 26, 3), (82, 34, 90, 22, 3)]:
            tr.line(x0, y0, x1, y1, w)
        f.draw(tr, trunk)
        save(f.image(), name)
        return
    f.draw(tr, trunk)
    clumps = [(64, 62, 40, 34), (34, 82, 26, 22), (94, 82, 26, 22), (44, 44, 26, 24), (84, 44, 26, 24), (64, 28, 26, 22),
              (64, 92, 30, 18)]
    for (x, y, rx, ry) in sorted(clumps, key=lambda c: -c[1]):
        s = f.shape().ellipse(x, y, rx, ry)
        f.draw(s, leaf)
    if blossoms:
        for _ in range(26):
            x, y = rnd.randint(18, 110), rnd.randint(14, 108)
            if f.px[y, x, 3] and tuple(f.px[y, x][:3]) != tuple(rgba(INK)[:3]):
                fl = f.shape().ellipse(x, y, 2.2, 2.2)
                f.draw(fl, blossoms, outline=False, flat=True)
                f.put(x, y, "fff6c8")
    save(f.image(), name)


def bush(name, leaf, flower=None, seed=2):
    """A 64x40 bush."""
    rnd = random.Random(seed)
    f = Frame(64, 40)
    for (x, y, rx, ry) in [(18, 26, 16, 13), (46, 26, 17, 13), (32, 18, 15, 14)]:
        f.draw(f.shape().ellipse(x, y, rx, ry).rect(0, 39, 64, 1, add=False), leaf)
    if flower:
        for _ in range(8):
            x, y = rnd.randint(8, 56), rnd.randint(8, 30)
            if f.px[y, x, 3] and tuple(f.px[y, x][:3]) != tuple(rgba(INK)[:3]):
                fl = f.shape().ellipse(x, y, 2.5, 2.5)
                f.draw(fl, flower, flat=True)
                f.put(x, y, "fff6c8")
    save(f.image(), name)


def tufts(name, leaf, flowers=(), seed=3):
    """tufts_*.png: 4 frames 32x24 of grass tufts and flowers; the bottom row is the ground line."""
    rnd = random.Random(seed)
    frames = []
    for k in range(4):
        f = Frame(32, 24)
        g = f.shape()
        for i in range(5):
            x = 4 + i * 6 + rnd.randint(-1, 1)
            hgt = rnd.randint(10, 19)
            lean = rnd.choice((-4, -2, 2, 4))
            g.poly([(x - 2.5, 24), (x + 2.5, 24), (x + lean, 24 - hgt)])
        f.draw(g, leaf)
        if flowers and k >= 2:
            for _ in range(2):
                fc = flowers[rnd.randrange(len(flowers))]
                x, y = rnd.randint(7, 25), rnd.randint(5, 10)
                st = f.shape().line(x, y, x + rnd.randint(-2, 2), 23, 1.4)
                f.draw(st, leaf, outline=False, flat=True)
                petal = f.shape()
                for a in range(5):
                    ang = a * math.tau / 5
                    petal.ellipse(x + math.cos(ang) * 2.4, y + math.sin(ang) * 2.4, 2, 2)
                f.draw(petal, fc)
                f.put(x, y, "fff0a0")
                f.put(x + 1, y, "fff0a0")
        frames.append(f)
    sheet(frames, name)


def rock(name, tones, glow=None):
    f = Frame(48, 32)
    r = f.shape().poly([(2, 32), (7, 13), (19, 4), (33, 7), (46, 20), (46, 32)])
    f.draw(r, tones)
    if glow:
        for (x0, y0, x1, y1) in [(16, 20, 22, 16), (22, 16, 26, 22), (30, 14, 34, 20), (26, 26, 30, 23)]:
            s = f.shape().line(x0, y0, x1, y1, 1.6)
            f.draw(s, [rgba(glow)] * 4, outline=False, flat=True)
    save(f.image(), name)


def lantern():
    f = Frame(28, 92)
    post = f.shape().rect(12, 22, 5, 66).rect(7, 86, 15, 6)
    f.draw(post, ramp("4a2c22", "3a2018", "2a140e", "6b4433"))
    glass = f.shape().rect(7, 4, 15, 13)
    f.draw(glass, ramp("fff0a8", "ffd166", "ffa040", "fffbe8"))
    cap = f.shape().poly([(4, 4), (25, 4), (14.5, -3)]).rect(5, 17, 19, 4)
    f.draw(cap, ramp("3a2a48", "2a1e36", "1c1224", "5a4a6a"))
    save(f.image(), "lantern.png")


def signpost():
    f = Frame(120, 76)
    post = f.shape().rect(56, 30, 8, 46)
    f.draw(post, WOOD)
    board = f.shape().rect(3, 3, 114, 32)
    f.draw(board, ramp("e0aa78", "c08a5a", "9a6a44", "f6cc9a"))
    for y in (13, 24):
        s = f.shape().line(6, y, 114, y, 1)
        f.draw(s, [rgba("b07a50")] * 4, outline=False, flat=True)
    for (x, y) in [(8, 8), (111, 8), (8, 29), (111, 29)]:
        f.put(x, y, "6b4433")
    save(f.image(), "signpost.png")


def cloud():
    f = Frame(128, 48)
    c = f.shape().ellipse(36, 30, 28, 14).ellipse(68, 22, 28, 18).ellipse(96, 30, 24, 14).rect(10, 30, 106, 14)
    f.draw(c, ramp("ffffff", "eee4f6", "d6c8ea", "ffffff"), outline=False)
    save(f.image(), "cloud.png")


# ---------------------------------------------------------------- terrain tiles

def tiles(prefix, grass, dirt, stone, seed):
    """<prefix>_top.png (grass seen from above), <prefix>_side.png (front face with a scalloped
    grass lip and an outline), <prefix>_soil.png (earth with outlined pebbles). 64x64, tiling."""
    rnd = random.Random(seed)
    S = 64

    def wrap_draw(f, shape_fn, tones, outline=True):
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                s = f.shape()
                shape_fn(s, ox, oy)
                f.draw(s, tones, outline=outline)

    top = Frame(S, S)
    top.px[:] = grass[2]
    for _ in range(26):
        x, y = rnd.randrange(S), rnd.randrange(S)
        lean = rnd.choice((-2, -1, 1, 2))
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                s = top.shape().poly([(x + ox - 2, y + oy + 4), (x + ox + 2, y + oy + 4), (x + ox + lean, y + oy - 4)])
                top.draw(s, [grass[1]] * 4, outline=False, flat=True)
    for _ in range(14):
        x, y = rnd.randrange(S), rnd.randrange(S)
        top.put(x, y, grass[3])
        top.put(x + 1, y, grass[3])
    save(top.image(), prefix + "_top.png")

    def soil_frame():
        f = Frame(S, S)
        f.px[:] = dirt[2]
        for _ in range(60):
            x, y = rnd.randrange(S), rnd.randrange(S)
            f.put(x, y, dirt[1])
        for _ in range(5):
            x, y, r = rnd.randrange(S), rnd.randrange(S), rnd.uniform(3, 5)
            wrap_draw(f, lambda s, ox, oy: s.ellipse(x + ox, y + oy, r * 1.3, r), stone)
        return f

    save(soil_frame().image(), prefix + "_soil.png")
    side = soil_frame()
    lip = side.shape()
    lip.rect(0, 0, S, 9)
    for i in range(8):
        x = i * 8 + 4
        lip.ellipse(x, 9, 5, 5 + (i * 3) % 4)
    side.draw(lip, grass)
    for i in range(8):  # outline the scallops onto the soil
        pass
    save(side.image(), prefix + "_side.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    # The hero, monsters, trees, bushes and rocks are hand-drawn now: see tools/pixel_art/.
    shard()
    soft_dot("soft_dot.png", 16)
    soft_dot("glow.png", 64, 1.6)
    blob_shadow()
    tufts("tufts_dawn.png", ramp("8fe06a", "5eb04a", "3f8a3a", "c8ff9a"),
          flowers=(ramp("ffb0c8", "ff7a9a", "d04a70", "ffe0ea"), ramp("ffe080", "ffc040", "d08a20", "fff6c8"),
                   ramp("c8b8ff", "9a86f0", "6a56c0", "ece6ff")))
    tufts("tufts_ember.png", ramp("e88a5a", "c0603e", "8a3a2e", "ffb88a"),
          flowers=(ramp("ffe080", "ffc040", "d08a20", "fff6c8"),), seed=7)
    lantern()
    signpost()
    cloud()
    tiles("ground_dawn", ramp("8fe06a", "6cc050", "4a9a3e", "c8ff9a"), ramp("b07a52", "8a5a3e", "64402e", "c8946a"),
          ramp("d4c4b0", "b0a090", "8a7a6a", "f0e6d8"), seed=11)
    tiles("ground_ember", ramp("e07a52", "c0603e", "8a3a2e", "ffa880"), ramp("6a3a3a", "54282e", "3a1a22", "8a4e4a"),
          ramp("8a5a5a", "6a4044", "4a2a32", "aa7a76"), seed=12)


if __name__ == "__main__":
    main()
