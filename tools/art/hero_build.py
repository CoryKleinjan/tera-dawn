#!/usr/bin/env python3
"""Build the paperdoll hero from its painted sheets (art/source/hero/).

The hero is a boy or a girl body (the hairstyle picks it: tousled is the boy, ponytail the
girl), each painted as one 3x4 animation sheet (body_<body>.png). Everything he wears is a
Gemini edit of that same sheet with one thing changed (body_<body>_bald.png, _jerkin, _trousers),
so each piece is lifted off by comparing the edit with the sheet it was made from, and lines up
with the body frame for frame. The hats come from Cory's hat/hair template sheets
(hats_<body>.png: one cell per hat shape, and one bare head), placed on his head on every pose.

    python3 tools/art/hero_build.py             # everything
    python3 tools/art/hero_build.py --preview   # also art/build/hero_preview.png

Writes (every strip is laid out like the body strip, both bodies side by side):
- assets/sprites/characters/hero.png: the bald bodies with their painted faces.
  hero_regions.png: which pixels are skin (the skin tone recolours them). hero_rig.json: each
  frame's pose, body and where his head is.
- assets/animations/hero.tres and hero_girl.tres: each body's animations over the strip.
- layers/hair_<style>.png: the hair, greyscale (tinted with the hair colour), and
  layers/hair_<style>_<shape>.png, the hair under each hat shape (from its template cell).
- pieces/headcut_<shape>.png: where his body is cut away under each hat shape.
- layers/worn_item_<id>.png: worn gear (WORN, HAT_ITEMS), in its own colours.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slice_sheets import background_color, defringe, dilate, flood, key_magenta, label  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "art", "source", "hero")
CHARS = os.path.join(ROOT, "assets", "sprites", "characters")
LAYERS = os.path.join(CHARS, "layers")
PIECES = os.path.join(CHARS, "pieces")
ANIMS = os.path.join(ROOT, "assets", "animations")

BODIES = ("boy", "girl")
## Each body's hairstyle (the LookDef id without "hair_").
STYLES = {"boy": "tousled", "girl": "ponytail"}
ROWS, COLS = 3, 4
## The poses on each sheet, by (row, column). The wind-up (2, 0) is left out: it raises the
## wrong arm, so the attack is the lunge and the follow-through.
POSES = {
    "idle": (0, 0), "blink": (0, 1), "jump": (0, 2), "fall": (0, 3),
    "walk1": (1, 0), "walk2": (1, 1), "walk3": (1, 2), "walk4": (1, 3),
    "lunge": (2, 1), "follow": (2, 2), "hurt": (2, 3),
}
POSE_NAMES = list(POSES)
## The game's frame (Paperdoll.FRAME_SIZE) and how tall the idle body stands in it.
FRAME_W, FRAME_H = 256, 208
IDLE_HEIGHT = 157
GROUND = 206
## Where the idle body's middle stands across the frame.
MIDDLE = 138
## Pixels kept around a cut piece (its soft edge).
EDGE = 2
## How far an edit may have drifted from its base sheet, in sheet pixels, each way.
DRIFT = 16

## Each animation: its poses, frames a second, whether it loops, and each frame's length.
## Anything not drawn yet stands still in the nearest pose (the game falls back the same way).
ANIMATIONS = [
    ("idle", ["idle"], 1.0, True, None),
    ("blink", ["blink"], 1.0, True, None),
    ("walk", ["walk1", "walk2", "walk3", "walk4"], 9.0, True, None),
    ("run", ["walk1", "walk2", "walk3", "walk4"], 12.0, True, None),
    ("jump", ["jump"], 1.0, True, None),
    ("fall", ["fall"], 1.0, True, None),
    ("land", ["idle"], 1.0, True, None),
    ("crouch", ["idle"], 1.0, True, None),
    ("rope", ["idle"], 1.0, True, None),
    ("ladder", ["idle"], 1.0, True, None),
    ("climb_idle", ["idle"], 1.0, True, None),
    ("attack", ["lunge", "follow"], 10.0, False, [1.5, 1.0]),
    ("slash", ["lunge", "follow"], 10.0, False, [1.5, 1.6]),
    ("punch", ["lunge", "follow"], 12.0, False, [1.2, 1.0]),
    ("throw", ["lunge", "follow"], 12.0, False, [1.4, 1.0]),
    ("shoot", ["lunge", "follow"], 8.0, False, [1.6, 1.0]),
    ("gun", ["lunge", "follow"], 10.0, False, [1.4, 1.0]),
    ("heavy", ["lunge", "follow"], 8.0, False, [1.8, 1.0]),
    ("hit", ["hurt"], 1.0, True, None),
    ("hurt", ["hurt"], 1.0, True, None),
    ("faint", ["hurt"], 3.0, False, None),
    ("level_up", ["idle"], 1.0, True, None),
    ("sit", ["idle"], 1.0, True, None),
]

## Worn items with their own art, by the sheet they are lifted from (body_<body>_<sheet>.png).
## A body without the sheet doesn't show the item.
WORN = {"jerkin": "squire_jerkin", "trousers": "squire_trousers"}
## Hat shapes (EquipDef.look_shape): the cell of the hat/hair template sheets
## (hats_<body>.png) each is painted in, by (row, column). The hair under every hat of a
## shape is that cell's.
HAT_SHAPES = {"helm": (0, 0), "tricorn": (0, 1), "bandana": (0, 2), "hood": (1, 0), "wizard": (1, 1)}
## The cell of hats_<body>.png with no hat (to compare the others with).
HATLESS = (1, 2)
## Hats with their own art, by the template cell (shape) they are painted on.
HAT_ITEMS = {"squire_helm": "helm"}


def frame_index(body, pose):
    """A pose's frame in the strip: each body's poses in turn."""
    return BODIES.index(body) * len(POSES) + POSE_NAMES.index(pose)


# ---------- reading the sheets ----------

def read(name):
    """A sheet as float RGB, and its background colour."""
    rgb = np.asarray(Image.open(os.path.join(SRC, name + ".png")).convert("RGB")).astype(float)
    return rgb, background_color(rgb.astype(np.uint8))


def cell(rgb, row, col, rows=ROWS, cols=COLS):
    h, w = rgb.shape[0] // rows, rgb.shape[1] // cols
    return rgb[row * h + 6:(row + 1) * h - 6, col * w + 6:(col + 1) * w - 6]


def key(c, bg):
    """RGB (0-1) and alpha of a cell: the background keyed out, specks dropped."""
    if bg.min() > 200:  # a white background (Gemini sometimes swaps the magenta for white)
        dist = np.abs(c - bg).max(2)
        alpha = np.clip((dist - 6.0) / 30.0, 0.0, 1.0)
        rgb = c / 255.0
    else:
        rgb, alpha = key_magenta(c, bg)
        rgb, alpha = defringe(rgb, alpha, bg)
    # nothing enclosed by the figure is background: the magenta key reads dark violet (his
    # eyes) as dark magenta, and the white key his pale shirt as white, so put those back
    clear = ~close(alpha >= 0.5, 4)  # (gaps in his outline closed, so an eye at its edge counts)
    h, w = clear.shape
    border = [(y, x) for y in (0, h - 1) for x in range(0, w, 4)] + [(y, x) for x in (0, w - 1) for y in range(0, h, 4)]
    inside = ~dilate(flood(clear, border), 2, outside=True)
    inside &= ~magenta_like(c)  # (but not the bits of background caught in a gap)
    rgb = np.where(inside[..., None], c / 255.0, rgb)
    alpha = np.where(inside, 1.0, alpha)
    lab, n = label(alpha > 0.5)
    sizes = np.bincount(lab.ravel())
    sizes[0] = 0
    keep = sizes[lab] >= 1500
    alpha = alpha * dilate(keep, EDGE)
    return rgb, alpha


def magenta_like(c):
    """Pixels of a 0-255 cell that are the magenta background or its bright fringe."""
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    return (r > 140) & (b > 120) & (g < 0.6 * np.minimum(r, b))


def keyed(name, rows=ROWS, cols=COLS):
    """Every cell of a sheet, keyed: {(row, col): (rgb, alpha)}."""
    rgb, bg = read(name)
    return {(r, c): key(cell(rgb, r, c, rows, cols), bg) for r in range(rows) for c in range(cols)}


def shifted(a, dy, dx):
    """`a` moved by (dy, dx), the edges filled with zeros."""
    out = np.zeros_like(a)
    h, w = a.shape[:2]
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = a[ys, xs]
    return out


def drift(alpha, base_alpha, rows=None):
    """How far an edit's figure moved from its base's: the (dy, dx) that lines them up best,
    judged on `rows` (a slice) of the base, the part the edit didn't change."""
    a = (alpha > 0.5)[::2, ::2]
    b = (base_alpha > 0.5)[::2, ::2]
    if rows is not None:
        b = b.copy()
        keep = np.zeros_like(b)
        keep[rows.start // 2:rows.stop // 2] = True
        b &= keep
    best, at = -1, (0, 0)
    for dy in range(-DRIFT // 2, DRIFT // 2 + 1):
        for dx in range(-DRIFT // 2, DRIFT // 2 + 1):
            s = (shifted(a, dy, dx) & b).sum()
            if s > best:
                best, at = s, (dy * 2, dx * 2)
    return at


def aligned(edit, base, rows=None):
    """An edit's cells moved onto its base's: {(row, col): (rgb, alpha)}."""
    out = {}
    for rc, (rgb, a) in edit.items():
        dy, dx = drift(a, base[rc][1], rows)
        out[rc] = (shifted(rgb, dy, dx), shifted(a, dy, dx))
    return out


def changed(edit, base, threshold=0.16):
    """Where an edit differs from its base: (mask) the new art's pixels."""
    e_rgb, e_a = edit
    b_rgb, b_a = base
    diff = np.abs(e_rgb * e_a[..., None] - b_rgb * b_a[..., None]).max(2)
    m = (diff > threshold) & (e_a > 0.5)
    # small islands are the re-render's noise; the piece is the big parts
    lab, n = label(m)
    sizes = np.bincount(lab.ravel())
    sizes[0] = 0
    return sizes[lab] >= 300


def close(m, r):
    """Fills gaps up to about 2r pixels across in a mask (grow, then shrink)."""
    return ~dilate(~dilate(m, r), r, outside=True)


# ---------- placing on the game's frame ----------

class Fit:
    """How a body's sheet cells go onto the game's frames: one scale and offset for all of
    them, so the poses keep their places against each other."""

    def __init__(self, idle_alpha):
        ys, xs = np.nonzero(idle_alpha > 0.5)
        self.scale = IDLE_HEIGHT / (ys.max() - ys.min())
        self.dx = MIDDLE - (xs.min() + xs.max()) / 2 * self.scale
        self.dy = GROUND - ys.max() * self.scale

    def point(self, x, y):
        """A sheet cell point in frame pixels."""
        return [round(x * self.scale + self.dx, 1), round(y * self.scale + self.dy, 1)]

    def frame(self, rgb, alpha):
        """A cell as an RGBA frame image."""
        px = np.dstack([rgb * 255, alpha * 255]).round().clip(0, 255).astype(np.uint8)
        img = Image.fromarray(px, "RGBA")
        img = img.resize((round(img.width * self.scale), round(img.height * self.scale)), Image.LANCZOS)
        f = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
        f.alpha_composite(img, (round(self.dx), round(self.dy)))
        return f


def new_strip():
    return Image.new("RGBA", (FRAME_W * len(BODIES) * len(POSES), FRAME_H), (0, 0, 0, 0))


def put(strip, body, pose, frame):
    strip.alpha_composite(frame, (frame_index(body, pose) * FRAME_W, 0))


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", os.path.relpath(path, ROOT))


def luma(rgb):
    return (rgb * [0.299, 0.587, 0.114]).sum(2)


def grey(rgb, bright):
    """Greyscale art to tint (hair): its brightness, lifted so `bright` (the hair's bright
    brightness) is 0.85 and the hair colour shows."""
    lum = np.clip(luma(rgb) / max(bright, 1e-3) * 0.85, 0, 1)
    return np.repeat(lum[..., None], 3, 2)


# ---------- the parts ----------

class Body:
    """One body's sheets, keyed and lined up with its sheet with hair (the base)."""

    def __init__(self, name):
        self.name = name
        self.base = keyed("body_" + name)
        self.bald = aligned(keyed("body_%s_bald" % name), self.base)
        self.fit = Fit(self.base[POSES["idle"]][1])
        rgb, a = self.hair("idle")
        self.hair_bright = float(np.percentile(luma(rgb)[a > 0.9], 90))

    def hair_mask(self, rc):
        """His brown hair on a cell of the base sheet (what the bald sheet took away)."""
        rgb = self.base[rc][0]
        return dilate(close(changed(self.base[rc], self.bald[rc], 0.12) & hairish(rgb), 2), 2)

    def bare(self, rc):
        """A cell without hair: his body as painted (its face), with the bald sheet only where
        his hair was (the bald sheet repainted some eyes badly). Alpha is the bald sheet's."""
        rgb, a = self.base[rc]
        brgb, ba = self.bald[rc]
        own = ~self.hair_mask(rc) & (a > 0.5)
        return np.where(own[..., None], rgb, brgb), ba

    def hair_region(self, rc):
        """Where his hair is on a cell (what the bald sheet took away), a little grown."""
        return dilate(changed(self.base[rc], self.bald[rc], 0.12), 4)

    def hair(self, pose):
        """The hair on a pose: (rgb, alpha) of what the bald sheet took away."""
        rc = POSES[pose]
        rgb, a = self.base[rc]
        m = changed(self.base[rc], self.bald[rc], 0.12) & hairish(rgb)  # (not a repainted eye)
        m = close(m, 3) & (a > 0.02)
        return rgb, a * dilate(m, 1) * np.where(m, 1.0, 0.5)

    def worn(self, sheet):
        """A worn piece on every pose: {pose: (rgb, alpha)} of what the edit put on, or {} if
        this body has no such sheet."""
        if not os.path.exists(os.path.join(SRC, "body_%s_%s.png" % (self.name, sheet))):
            return {}
        edit = aligned(keyed("body_%s_%s" % (self.name, sheet)), self.base)
        out = {}
        for pose, rc in POSES.items():
            rgb, a = edit[rc]
            m = close(changed(edit[rc], self.base[rc]), 4) & (a > 0.02)
            # the edit redraws his hair a little differently; none of that is the piece
            m &= ~(self.hair_region(rc) & ~dilate(self.bald[rc][1] > 0.5, 3))
            if sheet == "trousers":  # his pale shirt re-rendered paler is not the trousers
                m &= ~((rgb.mean(2) > 0.7) & (self.base[rc][0].mean(2) > 0.6))
            m &= dilate(~dilate(~m, 5, outside=True), 5)  # and no thin lines (redrawn outlines)
            # still bare skin, much as it was (his feet under trousers; a top keeps all it has)
            bare = (skin_mask(rgb, a) & skin_mask(*self.base[rc])
                    & (np.abs(rgb - self.base[rc][0]).max(2) < 0.2) & (sheet == "trousers"))
            m = main_parts(fill_holes(m) & ~bare)
            out[pose] = (rgb, a * dilate(m, 1) * np.where(m, 1.0, 0.5))
        return out


def main_parts(m):
    """The big parts of a mask: its largest piece and any at least a fifth its size (an edit's
    other changes are noise: a tone shift, a redrawn eye or strand of hair)."""
    lab, n = label(m)
    sizes = np.bincount(lab.ravel(), minlength=n + 1)
    sizes[0] = 0
    return sizes[lab] >= max(300, sizes.max() * 0.2)


def skin_mask(rgb, alpha):
    """The bare skin of a body cell: warm pinks and tans, not the cream shirt or grey shorts."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return (alpha > 0.5) & (r > 0.45) & (r - b > 0.17) & (g / np.maximum(r, 1e-3) < 0.86) & (r - g > 0.08)


def build_bodies(bodies):
    strip, regions = new_strip(), new_strip()
    for body in bodies.values():
        for pose, rc in POSES.items():
            rgb, a = body.bare(rc)
            put(strip, body.name, pose, body.fit.frame(rgb, a))
            skin = skin_mask(rgb, a)
            reg = np.zeros_like(rgb)
            reg[..., 0] = np.where(skin, 2 * 16 / 255.0, 0.0)  # Paperdoll.Region.SKIN
            put(regions, body.name, pose, body.fit.frame(reg, a))
    save(strip, os.path.join(CHARS, "hero.png"))
    save(regions, os.path.join(CHARS, "hero_regions.png"))
    return strip


def build_hair(bodies):
    """Each hairstyle's hair, greyscale: hair_<style>.png. Returns the hair's colour (the
    tint that makes the greyscale look as painted) for the rig."""
    tints = []
    for body in bodies.values():
        strip = new_strip()
        for pose in POSES:
            rgb, a = body.hair(pose)
            put(strip, body.name, pose, body.fit.frame(grey(rgb, body.hair_bright), a))
        save(strip, os.path.join(LAYERS, "hair_%s.png" % STYLES[body.name]))
        rgb, a = body.hair("idle")
        m = a > 0.9
        g = grey(rgb, body.hair_bright)[m][:, 0]
        tints.append([float(np.median(rgb[m][:, i][g > 0.2] / g[g > 0.2])) for i in range(3)])
    return [round(min(1.0, sum(t[i] for t in tints) / len(tints)), 3) for i in range(3)]


def build_worn(bodies):
    worn = {}
    for sheet, item in WORN.items():
        strip = new_strip()
        for body in bodies.values():
            for pose, (rgb, a) in body.worn(sheet).items():
                put(strip, body.name, pose, body.fit.frame(rgb, a))
        worn[item] = strip
        save(strip, os.path.join(LAYERS, "worn_item_%s.png" % item))
    return worn


# ---------- where his head is ----------

def head_box(alpha):
    """The idle head on the bald sheet: from its top down to the chin (the narrowest row
    between head and shoulders), as (y0, y1, x0, x1)."""
    ys, xs = np.nonzero(alpha > 0.5)
    top, bottom = ys.min(), ys.max()
    widths = (alpha > 0.5).sum(1)
    lo = top + int((bottom - top) * 0.25)
    hi = top + int((bottom - top) * 0.5)
    chin = lo + int(np.argmin(widths[lo:hi]))
    cols = np.nonzero((alpha[top:chin] > 0.5).any(0))[0]
    return top, chin, cols.min(), cols.max() + 1


def rotate(img, deg, centre):
    """A float image turned `deg` degrees (clockwise on screen) about `centre` (x, y)."""
    pil = Image.fromarray((img * 255).clip(0, 255).astype(np.uint8))
    return np.asarray(pil.rotate(-deg, resample=Image.BILINEAR, center=centre)).astype(float) / 255.0


def track_head(body):
    """Where the idle head is on each pose: {pose: (dx, dy, degrees)} that move the idle head
    (turned about its centre) onto the pose's, on the bald sheet."""
    idle = body.bald[POSES["idle"]][1]
    y0, y1, x0, x1 = head_box(idle)
    head = np.zeros_like(idle)
    head[y0:y1, x0:x1] = idle[y0:y1, x0:x1]
    centre = ((x0 + x1) / 2, (y0 + y1) / 2)
    small = 4
    out = {}
    for pose, rc in POSES.items():
        target = body.bald[rc][1][::small, ::small]
        # overlap with the pose's figure, less what sticks out of it, for every shift at once
        weight = 3 * target - 2
        f_weight = np.fft.rfft2(weight)
        best, at = -1e9, (0, 0, 0)
        for deg in range(-30, 31, 3):
            h = rotate(head, deg, centre)[::small, ::small]
            score = np.fft.irfft2(f_weight * np.conj(np.fft.rfft2(h)), weight.shape)
            # only shifts that keep the head on the cell (no wrapping round)
            lim = 40
            score[lim + 1:-lim] = -1e9
            score[:, lim + 1:-lim] = -1e9
            dy, dx = np.unravel_index(np.argmax(score), score.shape)
            if score[dy, dx] > best:
                hh, ww = score.shape
                best = score[dy, dx]
                at = ((dx if dx <= lim else dx - ww) * small, (dy if dy <= lim else dy - hh) * small, deg)
        out[pose] = at
    return out, (y0, y1, x0, x1), centre


# ---------- hats ----------

def hair_coloured(rgb):
    """Brown hair pixels (orange hue, middling brightness): kept out of a hat's picture, so
    only his own hair ever shows under it."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(2), rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    return (r >= g) & (g >= b) & (sat > 0.25) & (mx < 0.8) & ((g - b) > 0.25 * (r - b))


def hairish(rgb):
    """Pixels that could be his hair, shadows and highlights too: warm (red over blue), not
    pale. The bald sheet also changed his eyes a little; they are blue, violet or white."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(2), rgb.min(2)
    pale = (mx > 0.8) & ((mx - mn) < 0.25 * mx)
    return (r > b * 1.05) & (r >= g) & ~pale


def fill_holes(m):
    """A mask with everything it encloses filled in."""
    h, w = m.shape
    border = [(y, x) for y in (0, h - 1) for x in range(w)] + [(y, x) for x in (0, w - 1) for y in range(h)]
    return ~flood(~m, border)


class Hats:
    """The hats painted on one body's idle pose (hats_<body>.png), and where its head is on
    every pose."""

    def __init__(self, body):
        self.body = body
        self.cells = keyed("hats_" + body.name, 2, 3)
        idle = body.base[POSES["idle"]]
        rows = slice(idle[1].shape[0] // 2, idle[1].shape[0])  # line them up by his legs
        self.cells = {rc: c for rc, c in aligned(self.cells, {rc: idle for rc in self.cells}, rows).items()}
        self.track, self.box, self.centre = track_head(body)

    def piece(self, rc):
        """A template cell's hat and the hair under it, on the idle cell: (rgb, alpha, shows),
        `shows` being where his face shows through it (his ear only if the hat leaves it out)."""
        body = self.body
        rgb, a = self.cells[rc]
        bald = body.bald[POSES["idle"]]
        y0, chin, x0, x1 = self.box
        # line the template's face up with his (the repaint moved the head a little): match
        # the eyes and mouth, between the brim and the chin
        base = body.base[POSES["idle"]]
        fy0 = chin - (chin - y0) * 2 // 5
        ref = base[0][fy0:chin, x0:x1] * base[1][fy0:chin, x0:x1, None]
        best = (1e9, 0, 0)
        for dy in range(-14, 15):
            for dx in range(-14, 15):
                r2, a2 = shifted(rgb, dy, dx), shifted(a, dy, dx)
                d = np.abs(r2[fy0:chin, x0:x1] * a2[fy0:chin, x0:x1, None] - ref).mean()
                if d < best[0]:
                    best = (d, dy, dx)
        _, dy, dx = best
        rgb, a = shifted(rgb, dy, dx), shifted(a, dy, dx)
        # his face stays his own on every pose: on the bald head only strong changes count
        # (the hat, hair over his forehead), not the re-painted face
        head = np.zeros_like(a, bool)
        head[y0:chin, x0:x1] = bald[1][y0:chin, x0:x1] > 0.5
        head = ~dilate(~head, 3, outside=True)
        out_m = changed((rgb, a), bald, 0.14) & ~head
        mx, mn = rgb.max(2), rgb.min(2)
        pale = (mx > 0.8) & ((mx - mn) < 0.25 * mx)
        strong = changed((rgb, a), bald, 0.4) & head & ~pale  # never the face's highlights
        strong &= dilate(~dilate(~strong, 3, outside=True), 3)  # no specks from the face
        # and all the hair painted over his head (fine strands too: they hide his ear)
        hairp = close(changed((rgb, a), bald, 0.12) & hair_coloured(rgb), 2) & head
        in_m = strong | hairp
        # above the hat's lower edge it is all hat: any change there counts (its band)
        m0 = out_m | in_m
        in_m |= changed((rgb, a), bald, 0.14) & head & (hair_cut(m0) | fill_holes(m0))
        m = out_m | in_m
        lab, n = label(m)
        touch = np.unique(lab[out_m & m])
        m = np.isin(lab, touch[touch > 0])  # only what comes in from around his head
        # below the chin all of it stays as painted: her whole tail, but not the thin lines
        # of a re-painted collar
        low = np.arange(m.shape[0])[:, None] > chin + 12
        m = (m & ~low) | (m & low & dilate(~dilate(~m, 4, outside=True), 4))
        m = main_parts(close(m, 3))
        holes = fill_holes(m) & ~m
        lab, n = label(holes)
        sizes = np.bincount(lab.ravel(), minlength=n + 1)
        sizes[0] = 0
        m = (m | (sizes[lab] < 6000) & holes) & (a > 0.02)  # a hood's opening stays his face
        shows = np.zeros_like(m)
        shows[y0:chin + 12] = (bald[1][y0:chin + 12] > 0.5) & ~m[y0:chin + 12]
        # a hat covering the side of his head: the back edge of the face opening is the
        # template's own (his cheek, no ear)
        if m[y0:chin, x0:x0 + (x1 - x0) // 3].mean() > 0.3:
            cols = np.arange(m.shape[1])[None, :]
            ring = shows & dilate(~shows, 18, outside=True) & (cols < x0 + (x1 - x0) * 0.4) & (a > 0.5)
            m |= ring
            shows &= ~ring
        return rgb, a * dilate(m, 1) * np.where(m, 1.0, 0.5), shows

    def place(self, img, pose):
        """Art on the idle cell moved onto a pose: turned about the head's centre, shifted."""
        dx, dy, deg = self.track[pose]
        if img.ndim == 3:  # one channel at a time (rotate takes greyscale, RGB or RGBA)
            return np.dstack([self.place(img[..., i], pose) for i in range(img.shape[2])])
        return shifted(rotate(img, deg, self.centre), int(dy), int(dx))

    def shape(self, rc):
        """A hat shape on every pose: {pose: (hat, hair, cut)}: the hat (rgb, alpha), the hair
        under it (rgb, alpha: the template's, and the strands painted over his face below it)
        and where his body is cut away under it (mask: bare head poking out, an ear it hides)."""
        body = self.body
        rgb, a, shows = self.piece(rc)
        hairs = close(hair_coloured(rgb) & (a > 0.02), 2) & (a > 0.02)
        y0, chin, x0, x1 = self.box
        idle_head = np.zeros_like(a)
        idle_head[y0:chin - 4, x0:x1] = body.bald[POSES["idle"]][1][y0:chin - 4, x0:x1]
        out = {}
        for pose, prc in POSES.items():
            dy = self.track[pose][1]
            placed = self.place(np.dstack([rgb, a, hairs, shows, idle_head]), pose)
            prgb, pa = placed[..., :3], placed[..., 3]
            on_hair = placed[..., 4] > 0.5
            hm = pa > 0.5
            above = hair_cut(hm) | fill_holes(hm)
            rows = np.arange(hm.shape[0])[:, None]
            # his own strands painted over his face below the hat stay as painted
            brgb, ba = body.base[prc]
            face = ~above & (body.bald[prc][1] > 0.5) & (rows < chin + dy + 10)
            strands = body.hair_mask(prc) & face & (ba > 0.5)
            hair_a = np.where(on_hair, pa, 0.0)
            hair_rgb = np.where(on_hair[..., None], prgb, 0.0)
            hair_rgb = np.where(strands[..., None], brgb, hair_rgb)
            hair_a = np.maximum(hair_a, np.where(strands, ba, 0.0))
            hat = (prgb, np.where(on_hair, 0.0, pa))
            # none of his bare head pokes out of the hat; on his head only what the
            # template shows (no ear where the hat covers it), never an arm beside it
            cut = hair_cut(hm)
            head = dilate(placed[..., 6] > 0.5, 4)
            cut |= head & ~dilate(placed[..., 5] > 0.5, 3) & ~hm
            out[pose] = (hat, (hair_rgb, hair_a), cut)
        return out


def place_mask(mask, track, centre):
    """A mask on the idle cell moved onto a pose: turned about the head's centre, then shifted."""
    dx, dy, deg = track
    return shifted(rotate(mask.astype(float), deg, centre), int(dy), int(dx)) > 0.5


def hair_cut(hat_mask):
    """Where his hair is hidden under a hat on a pose: hair outside the hat but above its
    lower edge (poking out of its top, sides or back). Hair hanging below the edge shows, and
    the hat covers the rest."""
    h, w = hat_mask.shape
    filled = fill_holes(hat_mask)
    cols = np.nonzero(filled.any(0))[0]
    if not len(cols):
        return np.zeros_like(hat_mask)
    bottom = np.full(w, -1)
    for x in cols:  # the end of the hat's first run down the column (not crumbs below it)
        ys = np.nonzero(filled[:, x])[0]
        gaps = np.nonzero(np.diff(ys) > 1)[0]
        bottom[x] = ys[gaps[0]] if len(gaps) else ys[-1]
    bottom[:cols.min()] = bottom[cols.min()]
    bottom[cols.max() + 1:] = bottom[cols.max()]
    above = np.arange(h)[:, None] < bottom[None, :]
    return above & ~filled


# ---------- writing it all ----------

def build_hats(bodies):
    """For each hat shape: the hair under it (hair_<style>_<shape>.png, greyscale like the hair)
    and where the body is cut away under it (pieces/headcut_<shape>.png, alpha). For each hat
    with its own art (HAT_ITEMS): its picture on every pose (worn_item_<id>.png)."""
    items = {item: new_strip() for item in HAT_ITEMS}
    for shape, rc in HAT_SHAPES.items():
        cuts = new_strip()
        for body in bodies.values():
            hair = new_strip()
            for pose, (hat, (hrgb, ha), cut) in hats_of(body).shape(rc).items():
                put(hair, body.name, pose, body.fit.frame(grey(hrgb, body.hair_bright), ha))
                white = np.ones(cut.shape + (3,))
                put(cuts, body.name, pose, body.fit.frame(white, cut.astype(float)))
                for item, item_shape in HAT_ITEMS.items():
                    if item_shape == shape:
                        put(items[item], body.name, pose, body.fit.frame(*hat))
            save(hair, os.path.join(LAYERS, "hair_%s_%s.png" % (STYLES[body.name], shape)))
        save(cuts, os.path.join(PIECES, "headcut_%s.png" % shape))
    for item, strip in items.items():
        save(strip, os.path.join(LAYERS, "worn_item_%s.png" % item))


_HATS = {}


def hats_of(body):
    """One body's Hats (its head tracked once)."""
    if body.name not in _HATS:
        _HATS[body.name] = Hats(body)
    return _HATS[body.name]


def build_rig(bodies, hair_tint):
    """hero_rig.json: per strip frame its pose and where his head is; the colours the art's
    regions are painted in (the skin tone and hair colour recolour from those)."""
    frames = []
    skin = []
    for body in bodies.values():
        hats = hats_of(body)
        y0, chin, x0, x1 = hats.box
        for pose, rc in POSES.items():
            dx, dy, _deg = hats.track[pose]
            cx, cy = (x0 + x1) / 2 + dx, (y0 + chin) / 2 + dy
            ys, xs = np.nonzero(body.bald[rc][1] > 0.5)
            frames.append({
                "name": pose, "body": body.name,
                "head": body.fit.point(cx, cy), "face": body.fit.point(cx, cy),
                "head_top": body.fit.point(cx, y0 + dy), "neck": body.fit.point(cx, chin + dy),
                "head_size": [round((x1 - x0) * body.fit.scale), round((chin - y0) * body.fit.scale)],
                "feet": body.fit.point((xs.min() + xs.max()) / 2, ys.max()),
            })
        rgb, a = body.bare(POSES["idle"])
        skin.append(rgb[skin_mask(rgb, a)].mean(0))
    skin = [round(float(v), 3) for v in np.mean(skin, 0)]
    colors = [[1, 1, 1]] * 11
    colors[1] = hair_tint  # Paperdoll.Region.HAIR
    colors[2] = skin  # SKIN
    rig = {"frame_size": [FRAME_W, FRAME_H],
           "regions": ["none", "hair", "skin", "eyes", "top", "bottom", "shoes", "cape", "weapon", "shield", "gloves"],
           "frames": frames, "weapons": {}, "region_colors": colors}
    path = os.path.join(CHARS, "hero_rig.json")
    with open(path, "w") as f:
        json.dump(rig, f, indent=1)
        f.write("\n")
    print("wrote", os.path.relpath(path, ROOT))


def build_animations():
    """Each body's animations over the strip: hero.tres (the boy) and hero_girl.tres."""
    for body in BODIES:
        used = []
        for _name, poses, _fps, _loop, _lengths in ANIMATIONS:
            for pose in poses:
                if frame_index(body, pose) not in used:
                    used.append(frame_index(body, pose))
        out = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (len(used) + 2), "",
               '[ext_resource type="Texture2D" path="res://assets/sprites/characters/hero.png" id="1_strip"]', ""]
        for i in used:
            out += ['[sub_resource type="AtlasTexture" id="f%d"]' % i, 'atlas = ExtResource("1_strip")',
                    "region = Rect2(%d, 0, %d, %d)" % (i * FRAME_W, FRAME_W, FRAME_H), ""]
        anims = []
        for name, poses, fps, loop, lengths in ANIMATIONS:
            frames = ", ".join('{"duration": %s, "texture": SubResource("f%d")}'
                               % (float(lengths[k]) if lengths else 1.0, frame_index(body, p)) for k, p in enumerate(poses))
            anims.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}'
                         % (frames, "true" if loop else "false", name, float(fps)))
        out += ["[resource]", "animations = [%s]" % ", ".join(anims), ""]
        path = os.path.join(ANIMS, "hero.tres" if body == "boy" else "hero_%s.tres" % body)
        with open(path, "w") as f:
            f.write("\n".join(out))
        print("wrote", os.path.relpath(path, ROOT))


def preview(bodies):
    """art/build/hero_preview.png: every frame of the body with each layer, to check by eye."""
    rows = [Image.open(os.path.join(CHARS, "hero.png"))]
    for name in sorted(os.listdir(LAYERS)):
        if name.startswith(("hair_", "worn_item_")) and name.endswith(".png"):
            layer = Image.open(os.path.join(LAYERS, name))
            if layer.width == rows[0].width:
                row = rows[0].copy()
                row.alpha_composite(layer)
                rows.append(row)
    out = Image.new("RGBA", (rows[0].width, FRAME_H * len(rows)), (60, 60, 60, 255))
    for i, r in enumerate(rows):
        out.alpha_composite(r, (0, i * FRAME_H))
    save(out, os.path.join(ROOT, "art", "build", "hero_preview.png"))


def main(argv):
    bodies = {name: Body(name) for name in BODIES}
    build_bodies(bodies)
    tint = build_hair(bodies)
    build_worn(bodies)
    build_hats(bodies)
    build_rig(bodies, tint)
    build_animations()
    if "--preview" in argv:
        preview(bodies)


if __name__ == "__main__":
    main(sys.argv[1:])
