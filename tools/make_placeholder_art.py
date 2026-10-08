#!/usr/bin/env python3
"""Generates the placeholder pixel-art sprite sheets in assets/sprites/.

The art is drawn from simple shapes at native pixel resolution, then each part is
shaded (highlight on the upper-left rim, shade on the lower-right rim) and the
whole frame gets a dark outline. It is meant to be replaced by hand-made sprites
with the same frame sizes and order (see the FRAMES notes below).

    python3 tools/make_placeholder_art.py
"""
import math
import os
import random

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")


def hexc(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


OUTLINE = hexc("24152f")


class Part:
    """A set of pixels in one color ramp (highlight, base, shade)."""

    def __init__(self, base, shade=None, hi=None, rim=True):
        self.px = set()
        self.base = hexc(base)
        self.shade = hexc(shade) if shade else None
        self.hi = hexc(hi) if hi else None
        self.rim = rim
        self.over = {}  # explicit per-pixel colors (eyes, details)

    def dot(self, x, y):
        self.px.add((int(round(x)), int(round(y))))
        return self

    def rect(self, x, y, w, h):
        for j in range(int(h)):
            for i in range(int(w)):
                self.px.add((int(x) + i, int(y) + j))
        return self

    def ellipse(self, cx, cy, rx, ry, y_min=-1e9, y_max=1e9):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if y < y_min or y > y_max:
                    continue
                dx = (x + 0.5 - cx) / rx
                dy = (y + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0:
                    self.px.add((x, y))
        return self

    def line(self, x0, y0, x1, y1, width=1):
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for k in range(n + 1):
            t = k / n
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            for i in range(width):
                for j in range(width):
                    self.px.add((int(math.floor(x)) + i - width // 2, int(math.floor(y)) + j - width // 2))
        return self

    def poly(self, pts):
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            yc = y + 0.5
            xs = []
            for i in range(len(pts)):
                (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
                if (ay <= yc < by) or (by <= yc < ay):
                    xs.append(ax + (yc - ay) * (bx - ax) / (by - ay))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(math.ceil(xs[i] - 0.5)), int(math.floor(xs[i + 1] - 0.5)) + 1):
                    self.px.add((x, y))
        return self

    def carve(self, other):
        self.px -= other.px if isinstance(other, Part) else set(other)
        return self

    def color(self, x, y, c):
        self.over[(x, y)] = hexc(c) if isinstance(c, str) else c
        return self


class Frame:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.img.putpixel((x, y), c)

    def draw(self, part):
        for (x, y) in part.px:
            c = part.base
            if part.rim:
                if part.shade and ((x + 1, y + 1) not in part.px or (x, y + 1) not in part.px):
                    c = part.shade
                elif part.hi and ((x - 1, y - 1) not in part.px or (x, y - 1) not in part.px):
                    c = part.hi
            self.put(x, y, c)
        for (x, y), c in part.over.items():
            self.put(x, y, c)

    def outline(self, col=OUTLINE):
        src = self.img.copy()
        for y in range(self.h):
            for x in range(self.w):
                if src.getpixel((x, y))[3] > 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and src.getpixel((nx, ny))[3] > 0:
                        self.put(x, y, col)
                        break


def sheet(frames, name):
    w, h = frames[0].w, frames[0].h
    img = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        img.paste(f.img, (i * w, 0))
    img.save(os.path.join(OUT, name))
    print("wrote", name, img.size)


# ---------------------------------------------------------------- hero

HERO_W, HERO_H = 48, 56  # feet on row 54, body centred on x=24, facing right


def hero_frame(pose="idle", t=0):
    """FRAMES (hero.png, 48x56 each): 0-1 idle, 2-5 walk, 6 jump, 7-8 climb, 9-11 attack, 12 fallen."""
    f = Frame(HERO_W, HERO_H)
    cx, foot = 24, 54
    bob = 0
    lf, rf = 0, 0  # leg x offsets (back leg, front leg)
    lift_b, lift_f = 0, 0
    if pose == "idle":
        bob = t % 2
    elif pose == "walk":
        lf, rf = [(-3, 3), (-1, 1), (3, -3), (1, -1)][t]
        lift_b, lift_f = [(0, 1), (1, 0), (1, 0), (0, 1)][t]
        bob = [0, 1, 0, 1][t]
    elif pose == "jump":
        lf, rf, lift_b, lift_f = -2, 3, 3, 2
    elif pose == "attack":
        lf, rf = -3, 3
        bob = 1 if t > 0 else 0

    skin = ("ffd9b8", "e8a98a", "fff0e0")
    hair = ("ff9a3c", "d9662a", "ffc070")
    tunic = ("ff8a5b", "d4553a", "ffb38a")
    pants = ("4a3570", "33234f", "5f4890")
    boot = ("2e1f3f", "1e142b", "47355f")
    belt = ("ffd166", "d9a640", "fff0a8")
    steel = ("e8ecff", "9aa8e0", "ffffff")

    if pose == "fallen":
        stone = Part("c9b8d9", "9a86b3", "e8dcf2")
        stone.rect(cx - 8, foot - 16, 16, 16).ellipse(cx, foot - 16, 8, 6)
        f.draw(stone)
        for x, y in [(cx - 3, foot - 12), (cx - 3, foot - 11), (cx - 3, foot - 10), (cx - 3, foot - 9), (cx - 3, foot - 8),
                     (cx - 1, foot - 12), (cx - 1, foot - 11), (cx - 1, foot - 10), (cx - 1, foot - 9), (cx - 1, foot - 8),
                     (cx + 1, foot - 12), (cx + 1, foot - 11), (cx + 1, foot - 10), (cx + 1, foot - 9), (cx + 1, foot - 8),
                     (cx + 2, foot - 12), (cx + 3, foot - 13), (cx + 2, foot - 10), (cx + 3, foot - 10)]:
            f.put(x, y, hexc("5b4682"))
        grass = Part("8fd16a", "5e9a45")
        for i in range(-10, 11, 2):
            grass.rect(cx + i, foot - (2 if i % 4 == 0 else 1), 1, 3)
        f.draw(grass)
        f.outline()
        return f

    climb = pose == "climb"
    top = foot - 30 - bob  # top of torso

    # legs
    legs_b = Part(*pants)
    legs_f = Part(*pants)
    boots_b = Part(*boot)
    boots_f = Part(*boot)
    if climb:
        a = 2 if t == 0 else -2
        legs_b.rect(cx - 5, top + 13, 4, 12 + a)
        legs_f.rect(cx + 1, top + 13, 4, 12 - a)
        boots_b.rect(cx - 5, top + 25 + a, 4, 3)
        boots_f.rect(cx + 1, top + 25 - a, 4, 3)
    else:
        hb = foot - 3 - lift_b
        hf = foot - 3 - lift_f
        legs_b.rect(cx - 5 + lf, top + 13, 4, hb - (top + 13))
        legs_f.rect(cx + 1 + rf, top + 13, 4, hf - (top + 13))
        boots_b.rect(cx - 6 + lf, hb, 6, 3)
        boots_f.rect(cx + rf, hf, 6, 3)
    f.draw(legs_b)
    f.draw(boots_b)
    f.draw(legs_f)
    f.draw(boots_f)

    # torso: tunic with a belt and a short skirt flare
    body = Part(*tunic)
    body.rect(cx - 6, top, 12, 14).rect(cx - 7, top + 10, 14, 5)
    f.draw(body)
    b = Part(*belt, rim=False)
    b.rect(cx - 7, top + 9, 14, 2)
    f.draw(b)
    f.put(cx + 1, top + 9, hexc("fff3c4"))

    # head
    hy = top - 9
    head = Part(*skin)
    head.ellipse(cx + 1, hy, 7.5, 7.0)
    hr = Part(*hair)
    if climb:
        hr.ellipse(cx + 1, hy - 1, 8.5, 8.0)
        hr.poly([(cx - 4, hy + 3), (cx + 6, hy + 3), (cx + 1, hy + 9)])
    else:
        hr.ellipse(cx, hy - 3, 8.5, 6.0, y_max=hy - 1)
        hr.poly([(cx - 8, hy - 4), (cx - 13, hy + 6), (cx - 5, hy + 1)])  # back spike
        hr.poly([(cx - 9, hy - 6), (cx - 14, hy - 3), (cx - 7, hy - 2)])
        hr.poly([(cx - 2, hy - 9), (cx + 1, hy - 14), (cx + 3, hy - 8)])  # top tuft
        hr.rect(cx - 8, hy - 2, 4, 5)  # sideburn behind ear
        hr.rect(cx + 2, hy - 2, 7, 2)  # bangs
        hr.dot(cx + 8, hy)
        hr.dot(cx + 4, hy)
    f.draw(head)
    f.draw(hr)
    if not climb:
        for dy in (1, 2, 3):
            f.put(cx + 3, hy + dy, hexc("24152f"))
            f.put(cx + 7, hy + dy, hexc("24152f"))
        f.put(cx + 3, hy + 1, hexc("ffffff"))
        f.put(cx + 7, hy + 1, hexc("ffffff"))
        f.put(cx + 8, hy + 4, hexc("ff8a8a"))
        f.put(cx + 2, hy + 4, hexc("ff8a8a"))

    # arm and sword
    sx, sy = cx + 2, top + 3
    if climb:
        arm = Part(*skin)
        a = -2 if t == 0 else 2
        arm.rect(cx - 7, top - 5 + a, 3, 9)
        arm.rect(cx + 5, top - 5 - a, 3, 9)
        sleeve = Part(*tunic)
        sleeve.rect(cx - 7, top + 1 + a, 3, 3).rect(cx + 5, top + 1 - a, 3, 3)
        f.draw(arm)
        f.draw(sleeve)
    else:
        ang = {"idle": 1.15, "walk": 1.15, "jump": -0.6}.get(pose, 0)
        if pose == "attack":
            ang = [-2.3, -0.15, 0.95][t]
        hx = sx + math.cos(ang) * 6
        hy2 = sy + math.sin(ang) * 6
        if pose in ("idle", "walk"):
            hx, hy2 = sx + 3, sy + 7 + (bob if pose == "walk" else 0)
            ang = 0.35  # sword held low and forward
            blade_ang = -0.9 if pose == "idle" else -0.75
        else:
            blade_ang = ang - 0.2 if pose == "attack" else -1.2
        sleeve = Part(*tunic)
        sleeve.rect(sx - 1, sy - 1, 4, 4)
        arm = Part(*skin, rim=False)
        arm.line(sx + 1, sy + 1, hx, hy2, 2)
        sword = Part(*steel)
        L = 17
        bx, by = hx + math.cos(blade_ang) * 3, hy2 + math.sin(blade_ang) * 3
        ex, ey = hx + math.cos(blade_ang) * L, hy2 + math.sin(blade_ang) * L
        sword.line(bx, by, ex, ey, 2)
        guard = Part(*belt, rim=False)
        px_, py_ = -math.sin(blade_ang), math.cos(blade_ang)
        guard.line(bx - px_ * 3, by - py_ * 3, bx + px_ * 3, by + py_ * 3, 1)
        hilt = Part("8a5a43", "5e3a2e", rim=False)
        hilt.line(hx - math.cos(blade_ang) * 2, hy2 - math.sin(blade_ang) * 2, hx, hy2, 2)
        f.draw(sword)
        f.draw(hilt)
        f.draw(guard)
        f.draw(arm)
        f.draw(sleeve)
    f.outline()
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

def dewling():
    """dewling.png: 32x32 frames, 0-3 bounce cycle. Feet on row 30."""
    frames = []
    for t in range(4):
        f = Frame(32, 32)
        sq = [0.0, 0.08, 0.0, -0.08][t]
        rx, ry = 11 * (1 + sq), 10 * (1 - sq)
        base = 30
        body = Part("6fd8d0", "2f9a9a", "c2fff6")
        body.ellipse(16, base - ry, rx, ry)
        tip_h = 9 * (1 - sq)
        body.poly([(16 - rx * 0.55, base - ry * 1.5), (16 + rx * 0.2, base - ry * 1.5), (14, base - ry * 2 - tip_h + 4)])
        f.draw(body)
        cy = int(base - ry)
        for x, y in [(10, cy - 3), (11, cy - 4), (10, cy - 4), (12, cy - 5)]:
            f.put(x, y, hexc("ffffff"))
        for dx in (19, 23):
            f.put(dx, cy, hexc("24152f"))
            f.put(dx, cy + 1, hexc("24152f"))
        f.put(21, cy + 3, hexc("24152f"))
        f.put(17, cy + 2, hexc("ff9ab0"))
        f.put(25, cy + 2, hexc("ff9ab0"))
        f.outline(hexc("163a4a"))
        frames.append(f)
    sheet(frames, "dewling.png")


def sproutcap():
    """sproutcap.png: 32x40 frames, 0-3 hop cycle. Feet on row 38."""
    frames = []
    for t in range(4):
        f = Frame(32, 40)
        lift = [0, 2, 4, 2][t]
        base = 38 - lift
        stem = Part("f2dcc0", "c9a98a", "fff6e8")
        stem.ellipse(16, base - 8, 8, 8.5)
        feet = Part("c9a98a", "9a7a60")
        if lift:
            feet.rect(11, base - 1, 4, 2).rect(18, base - 1, 4, 2)
        else:
            feet.rect(10, base - 1, 5, 2).rect(18, base - 1, 5, 2)
        f.draw(feet)
        f.draw(stem)
        cap = Part("e8566b", "b02f4a", "ff8a98")
        cap.ellipse(16, base - 15, 14, 9, y_max=base - 13)
        f.draw(cap)
        for (x, y, r) in [(9, base - 19, 2.2), (19, base - 21, 2.0), (25, base - 16, 1.6), (14, base - 16, 1.2)]:
            spot = Part("fff3e4", rim=False)
            spot.ellipse(x, y, r, r * 0.9)
            f.draw(spot)
        sprout = Part("4f9a4a", rim=False)
        sprout.line(16, base - 24, 16, base - 28, 1)
        f.draw(sprout)
        leaf = Part("7ccf5f", "4f9a4a", "b5f08e")
        leaf.ellipse(12.5, base - 29, 3.5, 1.8).ellipse(19.5, base - 30, 3.5, 1.8)
        f.draw(leaf)
        ey = base - 9
        for x in (18, 22):
            f.put(x, ey, hexc("24152f"))
            f.put(x, ey + 1, hexc("24152f"))
        f.put(20, ey + 3, hexc("24152f"))
        f.put(23, ey + 2, hexc("ff9ab0"))
        f.outline()
        frames.append(f)
    sheet(frames, "sproutcap.png")


def emberboar(glow=False):
    """emberboar.png: 48x36 frames, 0-3 trot cycle. Feet on row 34.
    emberboar_glow.png has only the flame pixels, drawn additively for bloom."""
    frames = []
    rnd = random.Random(4)
    for t in range(4):
        f = Frame(48, 36)
        base = 34
        st = [2, 0, -2, 0][t]
        legs = Part("4a2c22", "2e1a14", "6b4433")
        for lx, o in ((12, st), (19, -st), (29, -st), (35, st)):
            legs.rect(lx + o // 2, base - 9, 4, 9)
        hooves = Part("2e1a14", rim=False)
        for lx, o in ((12, st), (19, -st), (29, -st), (35, st)):
            hooves.rect(lx + o // 2, base - 2, 4, 2)
        body = Part("8a5a40", "5e3a2e", "b07a58")
        body.ellipse(23, base - 15, 16, 9.5)
        head = Part("9a6448", "6b4433", "c08a68")
        head.ellipse(37, base - 14, 8, 7)
        snout = Part("c08a68", "8a5a43", "e0aa88")
        snout.ellipse(44, base - 11, 3.5, 3.5)
        tusk = Part("fff3e4", "c9b8a0", rim=True)
        tusk.poly([(41, base - 9), (44, base - 9), (45, base - 15)])
        ear = Part("6b4433", "4a2c22")
        ear.poly([(33, base - 21), (36, base - 20), (33, base - 26)])
        tail = Part("6b4433", rim=False)
        tail.line(7, base - 18, 4, base - 21, 1)
        flames = Part("ff7a3c", "e0482a", "ffd166")
        for i in range(6):
            x = 12 + i * 4
            hgt = 6 + ((i * 7 + t * 3) % 5)
            flames.poly([(x - 2, base - 21), (x + 3, base - 21), (x + 1 + (t % 2), base - 21 - hgt)])
        core = Part("fff0a0", rim=False)
        for i in range(6):
            x = 12 + i * 4
            core.rect(x, base - 23, 2, 2)
        if glow:
            f.draw(flames)
            f.draw(core)
        else:
            f.draw(tail)
            f.draw(legs)
            f.draw(hooves)
            f.draw(body)
            f.draw(flames)
            f.draw(core)
            f.draw(ear)
            f.draw(head)
            f.draw(snout)
            f.draw(tusk)
            f.put(38, base - 16, hexc("24152f"))
            f.put(38, base - 17, hexc("ffd166"))
            f.put(45, base - 11, hexc("4a2c22"))
            f.outline()
        frames.append(f)
    sheet(frames, "emberboar_glow.png" if glow else "emberboar.png")


# ---------------------------------------------------------------- items and props

def shard():
    """shard.png: one 12x14 Dawnshard gem."""
    f = Frame(12, 14)
    g = Part("ffd166", "ff7a59", "fff6c8")
    g.poly([(6, 0), (11.5, 6), (6, 13.5), (0.5, 6)])
    f.draw(g)
    for x, y in [(5, 3), (4, 4), (4, 5)]:
        f.put(x, y, hexc("ffffff"))
    f.outline(hexc("7a2e1a"))
    f.img.save(os.path.join(OUT, "shard.png"))


def soft_dot(name, size, falloff=2.0):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / (size / 2)
            a = max(0.0, 1.0 - d) ** falloff
            img.putpixel((x, y), (255, 255, 255, int(a * 255)))
    img.save(os.path.join(OUT, name))


def blob_shadow():
    img = Image.new("RGBA", (24, 10), (0, 0, 0, 0))
    for y in range(10):
        for x in range(24):
            dx = (x + 0.5 - 12) / 12
            dy = (y + 0.5 - 5) / 5
            d = dx * dx + dy * dy
            if d < 1:
                img.putpixel((x, y), (20, 10, 30, 150 if d < 0.55 else 90))
    img.save(os.path.join(OUT, "blob_shadow.png"))


def tree(name, leaf, leaf_shade, leaf_hi, trunk=("6b4433", "4a2c22", "8a5a43"), seed=1, dead=False):
    rnd = random.Random(seed)
    f = Frame(64, 96)
    tr = Part(*trunk)
    tr.poly([(28, 95), (36, 95), (34, 40), (30, 40)])
    tr.poly([(26, 95), (38, 95), (35, 88), (29, 88)])
    if dead:
        tr.line(32, 60, 18, 40, 2).line(33, 55, 48, 36, 2).line(32, 45, 26, 22, 2).line(33, 44, 40, 18, 2)
        tr.line(18, 40, 12, 36, 1).line(48, 36, 54, 30, 1)
        f.draw(tr)
        f.outline()
        f.img.save(os.path.join(OUT, name))
        return
    f.draw(tr)
    crown = Part(leaf, leaf_shade, leaf_hi)
    for (x, y, r) in [(32, 30, 18), (20, 42, 12), (44, 42, 12), (24, 22, 11), (40, 22, 11), (32, 14, 10), (32, 46, 12)]:
        crown.ellipse(x, y, r, r * 0.92)
    f.draw(crown)
    for _ in range(26):
        x, y = rnd.randint(16, 48), rnd.randint(10, 50)
        if (x, y) in crown.px and (x + 1, y + 1) in crown.px:
            f.put(x, y, hexc(leaf_hi))
            f.put(x + 1, y, hexc(leaf_hi))
    for _ in range(30):
        x, y = rnd.randint(14, 50), rnd.randint(24, 56)
        if (x, y) in crown.px:
            f.put(x, y, hexc(leaf_shade))
    f.outline()
    f.img.save(os.path.join(OUT, name))


def bush(name, c, s, h, flower=None, seed=2):
    rnd = random.Random(seed)
    f = Frame(32, 20)
    b = Part(c, s, h)
    b.ellipse(10, 12, 9, 8).ellipse(21, 11, 10, 9).ellipse(16, 8, 7, 7)
    b.carve([(x, y) for x in range(32) for y in range(19, 20)])
    f.draw(b)
    if flower:
        for _ in range(7):
            x, y = rnd.randint(4, 27), rnd.randint(4, 15)
            if (x, y) in b.px:
                f.put(x, y, hexc(flower))
    f.outline()
    f.img.save(os.path.join(OUT, name))


def tufts(name, c, s, h, flowers=(), seed=3):
    """4 frames 16x12 of grass tufts / flowers, bottom row is the ground line."""
    rnd = random.Random(seed)
    frames = []
    for k in range(4):
        f = Frame(16, 12)
        g = Part(c, s, h)
        for i in range(5):
            x = 2 + i * 3 + rnd.randint(-1, 1)
            hgt = rnd.randint(5, 10)
            lean = rnd.choice((-2, -1, 1, 2))
            g.poly([(x - 1, 12), (x + 2, 12), (x + lean + 0.5, 12 - hgt)])
        f.draw(g)
        if flowers and k >= 2:
            fc = flowers[k % len(flowers)]
            for _ in range(2):
                x, y = rnd.randint(3, 12), rnd.randint(2, 5)
                fl = Part(fc, rim=False)
                fl.dot(x, y).dot(x - 1, y).dot(x + 1, y).dot(x, y - 1).dot(x, y + 1)
                f.draw(fl)
                f.put(x, y, hexc("fff3c4"))
        f.outline()
        frames.append(f)
    sheet(frames, name)


def rock(name, c, s, h, glow=None):
    f = Frame(24, 16)
    r = Part(c, s, h)
    r.poly([(1, 16), (4, 6), (10, 2), (17, 4), (23, 10), (23, 16)])
    f.draw(r)
    if glow:
        for x, y in [(8, 10), (9, 9), (10, 9), (11, 10), (12, 11), (16, 8), (17, 9), (15, 12), (14, 13)]:
            f.put(x, y, hexc(glow))
    f.outline()
    f.img.save(os.path.join(OUT, name))


def lantern():
    f = Frame(16, 48)
    post = Part("4a2c22", "2e1a14", "6b4433")
    post.rect(7, 12, 3, 36).rect(5, 45, 7, 3)
    arm = Part("4a2c22", rim=False)
    arm.rect(7, 8, 3, 4)
    f.draw(post)
    f.draw(arm)
    cage = Part("2e1f3f", rim=False)
    cage.rect(4, 0, 9, 2).rect(4, 8, 9, 2).rect(4, 0, 1, 10).rect(12, 0, 1, 10)
    glass = Part("ffe39a", "ffb347", "fff8e0")
    glass.rect(5, 2, 7, 6)
    f.draw(glass)
    f.draw(cage)
    f.outline()
    f.img.save(os.path.join(OUT, "lantern.png"))


def signpost():
    f = Frame(64, 40)
    post = Part("6b4433", "4a2c22", "8a5a43")
    post.rect(30, 16, 4, 24)
    board = Part("c08a5a", "8a5a43", "e0aa78")
    board.rect(2, 2, 60, 16)
    f.draw(post)
    f.draw(board)
    for x in range(4, 60, 9):
        f.put(x, 9, hexc("a77a5a"))
        f.put(x + 1, 9, hexc("a77a5a"))
    f.outline()
    f.img.save(os.path.join(OUT, "signpost.png"))


def cloud():
    f = Frame(64, 24)
    c = Part("ffffff", "e8d6f0", "ffffff")
    c.ellipse(18, 15, 14, 7).ellipse(34, 11, 14, 9).ellipse(48, 15, 12, 7).rect(6, 15, 52, 7)
    f.draw(c)
    f.img.save(os.path.join(OUT, "cloud.png"))


# ---------------------------------------------------------------- terrain tiles

def tiles(prefix, grass, grass_s, grass_h, dirt, dirt_s, dirt_h, seed):
    """<prefix>_top.png (grass seen from above), <prefix>_side.png (front face with a grass lip),
    <prefix>_soil.png (plain earth). All 32x32 and tile horizontally."""
    rnd = random.Random(seed)
    top = Image.new("RGBA", (32, 32), hexc(grass))
    for _ in range(140):
        x, y = rnd.randrange(32), rnd.randrange(32)
        top.putpixel((x, y), hexc(rnd.choice((grass_s, grass_h, grass_s))))
    for _ in range(18):
        x, y = rnd.randrange(32), rnd.randrange(31)
        top.putpixel((x, y), hexc(grass_h))
        top.putpixel((x, (y + 1) % 32), hexc(grass_s))
    top.save(os.path.join(OUT, prefix + "_top.png"))

    def soil_img():
        img = Image.new("RGBA", (32, 32), hexc(dirt))
        for _ in range(120):
            x, y = rnd.randrange(32), rnd.randrange(32)
            img.putpixel((x, y), hexc(rnd.choice((dirt_s, dirt_h, dirt_s))))
        for _ in range(5):  # pebbles
            x, y = rnd.randrange(31), rnd.randrange(31)
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                img.putpixel(((x + dx) % 32, (y + dy) % 32), hexc(dirt_h))
            img.putpixel(((x + 1) % 32, (y + 2) % 32), hexc(dirt_s))
            img.putpixel(((x + 2) % 32, (y + 1) % 32), hexc(dirt_s))
        return img

    soil = soil_img()
    soil.save(os.path.join(OUT, prefix + "_soil.png"))
    side = soil_img()
    for x in range(32):
        lip = 4 + (1 if (x * 7) % 5 == 0 else 0) + (2 if (x * 13) % 11 == 0 else 0)
        for y in range(lip + 1):
            c = grass_h if y == 0 else (grass if y < lip - 1 else grass_s)
            side.putpixel((x, y), hexc(c))
        side.putpixel((x, lip + 1), hexc(dirt_s))
    side.save(os.path.join(OUT, prefix + "_side.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    hero()
    dewling()
    sproutcap()
    emberboar()
    emberboar(glow=True)
    shard()
    soft_dot("soft_dot.png", 16)
    soft_dot("glow.png", 64, 1.6)
    blob_shadow()
    tree("tree_dawn.png", "5fae5a", "3f7a4a", "9fdc78", seed=1)
    tree("tree_dawn_pink.png", "f29ab8", "c0628e", "ffd0e0", seed=5)
    tree("tree_ember.png", "", "", "", trunk=("4a2c33", "2e1a24", "6b3c44"), dead=True)
    bush("bush_dawn.png", "5fae5a", "3f7a4a", "9fdc78", flower="ffd166")
    bush("bush_ember.png", "8a3a3a", "5c2430", "c0584a", flower="ffb35c")
    tufts("tufts_dawn.png", "8fd16a", "5e9a45", "c3ef8e", flowers=("ff9ab0", "ffd166", "b8a4ff"))
    tufts("tufts_ember.png", "d9774f", "9a4a3a", "ffa577", flowers=("ffd166",), seed=7)
    rock("rock_dawn.png", "9a8aa8", "6a5a7a", "c9bcd6")
    rock("rock_ember.png", "4a3038", "2e1a24", "6b4450", glow="ff9b5c")
    lantern()
    signpost()
    cloud()
    tiles("ground_dawn", "8fd16a", "6fb054", "c3ef8e", "8a5a43", "6e4635", "a87055", seed=11)
    tiles("ground_ember", "c8664a", "9a4a3a", "ff9a70", "5c3433", "432428", "7a4844", seed=12)


if __name__ == "__main__":
    main()
