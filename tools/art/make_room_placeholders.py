#!/usr/bin/env python3
"""Draws stand-in art for the rooms inside town buildings, one set per town style, into
assets/sprites/rooms/<style>/: the back wall (a strip the backdrop repeats), the floor's
top and front textures, the doorway out, and furniture (counter, shelves, bookcase,
table, barrels, crates, hearth, weapon rack, banner, hanging lamp, potted plant).

Part 9 of the art prompts asks for the painted versions; a sheet cut by slice_sheets.py
into the same folder replaces these with no data changes.

    python3 tools/art/make_room_placeholders.py            # every style
    python3 tools/art/make_room_placeholders.py lumewood   # only these
"""
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "rooms")

# wall: "plaster", "planks" or "stone"; the colours of each town's rooms
STYLES = {
    "dawnharbor": dict(wall="plaster", wall_col=(236, 226, 204), wood=(132, 86, 50), dark=(74, 46, 30),
                       accent=(56, 104, 178), accent2=(242, 192, 92), floor=(170, 120, 74), window=((255, 214, 160), (126, 176, 226))),
    "meadow": dict(wall="plaster", wall_col=(238, 222, 186), wood=(142, 98, 58), dark=(80, 52, 32),
                   accent=(98, 152, 72), accent2=(242, 156, 120), floor=(176, 128, 80), window=((255, 216, 150), (150, 200, 140))),
    "driftcove": dict(wall="planks", wall_col=(124, 90, 64), wood=(96, 64, 42), dark=(52, 34, 24),
                      accent=(44, 146, 146), accent2=(226, 206, 156), floor=(138, 98, 64), window=((255, 200, 140), (90, 170, 200))),
    "emberforge": dict(wall="stone", wall_col=(104, 88, 82), wood=(86, 56, 38), dark=(46, 34, 30),
                       accent=(184, 54, 42), accent2=(255, 152, 62), floor=(112, 84, 66), window=((255, 170, 90), (220, 110, 70))),
    "greenbough": dict(wall="planks", wall_col=(158, 118, 74), wood=(112, 78, 46), dark=(62, 44, 26),
                       accent=(94, 154, 66), accent2=(236, 206, 124), floor=(150, 108, 64), window=((255, 226, 150), (150, 206, 120))),
    "lanternfall": dict(wall="planks", wall_col=(88, 64, 84), wood=(70, 46, 46), dark=(38, 26, 32),
                        accent=(214, 154, 62), accent2=(206, 72, 70), floor=(104, 72, 66), window=((255, 190, 110), (110, 90, 160))),
    "lumewood": dict(wall="stone", wall_col=(106, 98, 142), wood=(76, 60, 88), dark=(42, 34, 54),
                     accent=(124, 176, 244), accent2=(204, 164, 255), floor=(98, 84, 120), window=((210, 230, 255), (150, 120, 220))),
}

INK_ALPHA = 255


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


def noise(im, amount, seed):
    """Paints a little grain over the opaque pixels so flat fills read as painted."""
    rnd = random.Random(seed)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                n = rnd.uniform(-amount, amount)
                px[x, y] = (max(0, min(255, int(r * (1 + n)))), max(0, min(255, int(g * (1 + n)))), max(0, min(255, int(b * (1 + n)))), a)


def box(d, r, fill, outline=None, light=True):
    """A filled box with a dark outline, a lit top edge and a shaded bottom edge."""
    x0, y0, x1, y1 = r
    d.rectangle(r, fill=fill)
    if light and y1 - y0 > 3:
        d.line([(x0 + 1, y0 + 1), (x1 - 1, y0 + 1)], fill=shade(fill, 1.25))
        d.line([(x0 + 1, y1 - 1), (x1 - 1, y1 - 1)], fill=shade(fill, 0.7))
    if outline:
        d.rectangle(r, outline=outline)


def planks_v(d, r, col, dark, step, seed):
    """Upright boards."""
    rnd = random.Random(seed)
    x0, y0, x1, y1 = r
    x = x0
    while x < x1:
        w = step + rnd.randint(-2, 2)
        box(d, (x, y0, min(x + w, x1), y1), shade(col, rnd.uniform(0.88, 1.08)), light=False)
        d.line([(x, y0), (x, y1)], fill=dark)
        x += w


def stones(d, r, col, dark, seed):
    rnd = random.Random(seed)
    x0, y0, x1, y1 = r
    y = y0
    row = 0
    while y < y1:
        h = 22 + rnd.randint(-3, 3)
        x = x0 - (14 if row % 2 else 0)
        while x < x1:
            w = 34 + rnd.randint(-6, 8)
            c = shade(col, rnd.uniform(0.85, 1.1))
            d.rounded_rectangle((x + 1, y + 1, x + w - 1, y + h - 1), 4, fill=c, outline=dark)
            d.line([(x + 4, y + 3), (x + w - 5, y + 3)], fill=shade(c, 1.18))
            x += w
        y += h
        row += 1


# ---------- the room's shell ----------

def wall(s):
    # tall enough to fill the view from the ceiling down to behind the floor
    W, H = 320, 440
    RAIL = 330  # the chair rail; wainscot below it
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    col, wood, dark = s["wall_col"] + (255,), s["wood"] + (255,), s["dark"] + (255,)
    if s["wall"] == "plaster":
        for y in range(0, RAIL):  # soft light falling from the windows, darker toward the ceiling
            d.line([(0, y), (W, y)], fill=shade(col, 0.8 + 0.2 * min(1.0, y / 220)))
    elif s["wall"] == "planks":
        planks_v(d, (0, 0, W, RAIL), col, dark, 22, 3)
    else:
        stones(d, (0, 0, W, RAIL), col, dark, 5)
    # ceiling beams and the posts holding them
    box(d, (0, 0, W, 34), shade(wood, 0.85), dark)
    box(d, (0, 34, W, 46), wood, dark)
    for x in (0, 160):
        box(d, (x, 0, x + 14, RAIL + 6), shade(wood, 0.9), dark)
    # a window letting the dawn in
    wx0, wy0, wx1, wy1 = 48, 150, 116, 250
    sun, sky = s["window"]
    d.rounded_rectangle((wx0 - 6, wy0 - 6, wx1 + 6, wy1 + 6), 10, fill=wood, outline=dark)
    for y in range(wy0, wy1):
        d.line([(wx0, y), (wx1, y)], fill=mix(sky, sun, (y - wy0) / (wy1 - wy0)))
    d.line([((wx0 + wx1) // 2, wy0), ((wx0 + wx1) // 2, wy1)], fill=dark, width=3)
    d.line([(wx0, (wy0 + wy1) // 2), (wx1, (wy0 + wy1) // 2)], fill=dark, width=3)
    box(d, (wx0 - 10, wy1 + 4, wx1 + 10, wy1 + 12), wood, dark)
    # a banner in the town's colour
    bx, by = 222, 120
    d.polygon([(bx, by), (bx + 44, by), (bx + 44, by + 100), (bx + 22, by + 86), (bx, by + 100)], fill=s["accent"] + (255,), outline=dark)
    d.ellipse((bx + 10, by + 24, bx + 34, by + 48), fill=s["accent2"] + (255,), outline=dark)
    d.line([(bx - 4, by), (bx + 48, by)], fill=dark, width=3)
    # chair rail and wainscot
    box(d, (0, RAIL - 4, W, RAIL + 6), wood, dark)
    box(d, (0, RAIL + 6, W, H), shade(wood, 0.85), dark, light=False)
    for x in range(8, W, 52):
        d.rectangle((x, RAIL + 16, x + 42, H - 12), outline=shade(wood, 0.6))
        d.line([(x + 1, RAIL + 17), (x + 41, RAIL + 17)], fill=shade(wood, 1.1))
    noise(im, 0.04, 11)
    return im


def floor_top(s):
    im = Image.new("RGBA", (128, 128))
    d = ImageDraw.Draw(im)
    rnd = random.Random(2)
    col, dark = s["floor"] + (255,), s["dark"] + (255,)
    for row in range(8):
        y = row * 16
        off = rnd.randint(0, 127)
        d.rectangle((0, y, 128, y + 15), fill=shade(col, rnd.uniform(0.9, 1.06)))
        d.line([(0, y), (128, y)], fill=shade(col, 0.6))
        for x in (off % 128, (off + 64) % 128):
            d.line([(x, y), (x, y + 15)], fill=shade(col, 0.65))
    noise(im, 0.05, 3)
    return im


def floor_side(s, f=1.0):
    im = Image.new("RGBA", (128, 128))
    d = ImageDraw.Draw(im)
    wood, dark = shade(s["wood"], f), shade(s["dark"], f)
    box(d, (0, 0, 128, 20), shade(wood, 1.05), dark)
    planks_v(d, (0, 20, 128, 128), shade(wood, 0.8), dark, 32, 4)
    for x in (16, 80):
        d.ellipse((x - 2, 8, x + 2, 12), fill=s["accent2"] + (255,))
    noise(im, 0.05, 4)
    return im


def door(s):
    W, H = 72, 104
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    wood, dark = s["wood"] + (255,), s["dark"] + (255,)
    sun, sky = s["window"]
    d.rounded_rectangle((0, 0, W - 1, H - 1), 30, fill=wood, outline=dark)
    inner = (10, 10, W - 11, H - 1)
    d.rounded_rectangle(inner, 24, fill=sun + (255,))
    for y in range(10, H):  # daylight outside, brightest at the bottom
        t = (y - 10) / (H - 10)
        d.line([(12, y), (W - 13, y)], fill=mix(sky, (255, 246, 214), t))
    mask = Image.new("L", (W, H))
    ImageDraw.Draw(mask).rounded_rectangle(inner, 24, fill=255)
    lit = Image.new("RGBA", (W, H))
    lit.paste(im, mask=mask)
    out = Image.new("RGBA", (W, H))
    ImageDraw.Draw(out).rounded_rectangle((0, 0, W - 1, H - 1), 30, fill=wood, outline=dark)
    out.alpha_composite(lit)
    # the door leaf swung open against the frame
    od = ImageDraw.Draw(out)
    od.polygon([(10, 24), (20, 30), (20, H - 4), (10, H - 1)], fill=shade(wood, 0.8), outline=dark)
    box(od, (0, H - 6, W, H), shade(wood, 0.7), dark)
    noise(out, 0.03, 6)
    return out


# ---------- furniture ----------

def counter(s):
    im = Image.new("RGBA", (136, 64))
    d = ImageDraw.Draw(im)
    wood, dark = s["wood"] + (255,), s["dark"] + (255,)
    box(d, (6, 24, 130, 63), shade(wood, 0.9), dark)
    for x in range(12, 126, 30):
        d.rectangle((x, 30, x + 24, 58), outline=shade(wood, 0.6))
    box(d, (0, 16, 135, 25), shade(wood, 1.15), dark)
    for i, x in enumerate((14, 30, 92, 108)):  # jars and a ledger on the top
        c = (s["accent"], s["accent2"])[i % 2] + (255,)
        d.rounded_rectangle((x, 2, x + 11, 16), 3, fill=c, outline=dark)
    box(d, (52, 9, 78, 16), (232, 222, 196, 255), dark)
    noise(im, 0.04, 7)
    return im


def shelf(s, books=False):
    W, H = 96, 124
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    wood, dark = s["wood"] + (255,), s["dark"] + (255,)
    box(d, (0, 0, W - 1, H - 1), shade(wood, 0.75), dark)
    rnd = random.Random(8 if books else 9)
    for row in range(3):
        y = 8 + row * 38
        box(d, (4, y + 30, W - 5, y + 35), wood, dark)
        x = 8
        while x < W - 14:
            if books:
                w, h = rnd.randint(6, 10), rnd.randint(20, 28)
                c = rnd.choice([s["accent"], s["accent2"], (180, 70, 60), (90, 120, 80), (220, 200, 150)])
                box(d, (x, y + 30 - h, x + w, y + 30), c + (255,), dark, light=False)
                x += w + 1
            else:
                w = rnd.randint(9, 12)
                c = rnd.choice([s["accent"], s["accent2"], (226, 70, 90), (90, 150, 230), (236, 230, 210)])
                d.rounded_rectangle((x, y + 14, x + w, y + 30), 3, fill=c + (255,), outline=dark)
                d.rectangle((x + w // 2 - 2, y + 9, x + w // 2 + 2, y + 14), fill=(200, 180, 150, 255), outline=dark)
                x += w + 4
    noise(im, 0.04, 10)
    return im


def table(s):
    im = Image.new("RGBA", (84, 48))
    d = ImageDraw.Draw(im)
    wood, dark = s["wood"] + (255,), s["dark"] + (255,)
    box(d, (0, 10, 83, 18), shade(wood, 1.15), dark)
    for x in (6, 70):
        box(d, (x, 18, x + 7, 47), shade(wood, 0.8), dark, light=False)
    d.ellipse((30, 0, 46, 11), fill=s["accent2"] + (255,), outline=dark)  # a bowl of fruit
    d.rounded_rectangle((54, 2, 62, 11), 2, fill=(236, 230, 212, 255), outline=dark)  # a mug
    noise(im, 0.04, 12)
    return im


def barrel(s):
    im = Image.new("RGBA", (36, 46))
    d = ImageDraw.Draw(im)
    wood, dark = s["wood"] + (255,), s["dark"] + (255,)
    d.rounded_rectangle((0, 0, 35, 45), 10, fill=shade(wood, 1.05), outline=dark)
    for x in (9, 18, 27):
        d.line([(x, 2), (x, 43)], fill=shade(wood, 0.75))
    for y in (8, 37):
        d.line([(1, y), (34, y)], fill=(70, 70, 76, 255), width=3)
    noise(im, 0.05, 13)
    return im


def crate(s):
    im = Image.new("RGBA", (44, 40))
    d = ImageDraw.Draw(im)
    wood, dark = s["wood"] + (255,), s["dark"] + (255,)
    box(d, (0, 0, 43, 39), shade(wood, 1.1), dark)
    d.rectangle((4, 4, 39, 35), outline=shade(wood, 0.7))
    d.line([(4, 4), (39, 35)], fill=shade(wood, 0.7), width=3)
    noise(im, 0.05, 14)
    return im


def hearth(s):
    W, H = 120, 124
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    dark = s["dark"] + (255,)
    stone = (128, 116, 108, 255)
    stones(d, (0, 0, W, H), stone[:3], dark, 15)
    d.rounded_rectangle((26, 52, W - 26, H - 1), 20, fill=(34, 20, 16, 255), outline=dark)
    for i in range(18):  # the fire, brightest at its heart
        t = i / 18
        r = 26 * (1 - t)
        d.ellipse((W / 2 - r, H - 14 - r * 1.3, W / 2 + r, H - 6), fill=mix((255, 110, 40), (255, 236, 150), t))
    box(d, (12, 40, W - 12, 50), s["wood"] + (255,), dark)
    out = Image.new("RGBA", (W, H))
    out.alpha_composite(im)
    noise(out, 0.04, 16)
    return out


def rack(s):
    im = Image.new("RGBA", (100, 100))
    d = ImageDraw.Draw(im)
    wood, dark = s["wood"] + (255,), s["dark"] + (255,)
    for x in (4, 88):
        box(d, (x, 6, x + 8, 99), wood, dark, light=False)
    for y in (24, 60):
        box(d, (0, y, 99, y + 6), shade(wood, 1.1), dark)
    metal = (198, 204, 214, 255)
    for i, x in enumerate((22, 40, 58, 76)):  # blades, a staff and a bow resting on it
        if i == 2:
            d.arc((x - 10, 10, x + 10, 92), 270, 90, fill=wood, width=3)
            d.line([(x, 10), (x, 92)], fill=(236, 230, 210, 255))
        else:
            d.polygon([(x - 3, 14), (x + 3, 14), (x + 3, 78), (x, 86), (x - 3, 78)], fill=metal, outline=dark)
            box(d, (x - 7, 78, x + 7, 82), s["accent2"] + (255,), dark, light=False)
    noise(im, 0.03, 17)
    return im


def lamp(s):
    C = 110  # chain length up to the ceiling beam
    im = Image.new("RGBA", (28, C + 38))
    d = ImageDraw.Draw(im)
    dark = s["dark"] + (255,)
    for y in range(0, C, 6):  # chain links
        d.ellipse((11, y, 17, y + 7), outline=dark)
    d.polygon([(4, C + 6), (24, C + 6), (20, C), (8, C)], fill=s["wood"] + (255,), outline=dark)
    d.rounded_rectangle((5, C + 6, 23, C + 30), 4, fill=(255, 214, 130, 255), outline=dark)
    d.rectangle((9, C + 12, 19, C + 24), fill=(255, 246, 200, 255))
    d.polygon([(4, C + 30), (24, C + 30), (14, C + 37)], fill=s["wood"] + (255,), outline=dark)
    return im


def plant(s):
    im = Image.new("RGBA", (40, 60))
    d = ImageDraw.Draw(im)
    dark = s["dark"] + (255,)
    for i, (dx, dy) in enumerate(((-12, -22), (12, -24), (0, -32), (-6, -12), (8, -14))):
        d.ellipse((20 + dx - 8, 38 + dy - 6, 20 + dx + 8, 38 + dy + 6), fill=shade((94, 158, 72), 0.85 + 0.06 * i), outline=dark)
    d.polygon([(8, 38), (32, 38), (28, 59), (12, 59)], fill=(186, 104, 70, 255), outline=dark)
    return im


PIECES = {
    "wall": wall, "floor_top": floor_top, "floor_side": floor_side,
    "floor_soil": lambda s: floor_side(s, 0.7), "door": door,
    "counter": counter, "shelf": shelf, "bookcase": lambda s: shelf(s, True), "table": table,
    "barrel": barrel, "crate": crate, "hearth": hearth, "rack": rack, "lamp": lamp, "plant": plant,
}


def main():
    names = sys.argv[1:] or list(STYLES)
    for name in names:
        out = os.path.join(OUT, name)
        os.makedirs(out, exist_ok=True)
        for piece, draw in PIECES.items():
            draw(STYLES[name]).save(os.path.join(out, piece + ".png"))
        print(f"{name}: {len(PIECES)} pieces -> assets/sprites/rooms/{name}")


if __name__ == "__main__":
    main()
