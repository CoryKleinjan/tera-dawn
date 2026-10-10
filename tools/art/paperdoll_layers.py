#!/usr/bin/env python3
"""Build the hero's layers from the part 2 paperdoll sheets.

The hero is drawn in layers: a bald, faceless body (assets/sprites/characters/hero.png, cut
by the paperdoll_body manifest), with hair, a face and worn gear on top. The hair, face and
shield sheets draw each piece once (or once per pose) in its own cell, not where it sits on
every frame, so this tool finds the head, neck and hands in each body frame and places the
pieces there; the cape sheet is drawn on the body sheet's grid where the cape hangs in each
pose, so each pose's cape is put where it sits on the body (body_offsets), writing one strip per layer that lines up frame for frame with
the body. The game plays a layer in step with the body (Paperdoll, PaperdollSprite).

    python3 tools/art/slice_sheets.py paperdoll_body   # the body strip first
    python3 tools/art/paperdoll_layers.py              # then the layers, mask and rig
    python3 tools/art/paperdoll_layers.py --preview    # also art/build/paperdoll_preview.png

Writes:
- assets/sprites/characters/hero_regions.png: the body strip's twin. Red channel = region
  id * 16 (Paperdoll.Region): skin, top (the chest a worn top covers), bottom (the shorts),
  shoes (the feet a worn pair covers). Alpha copies the body's.
- assets/sprites/characters/hero_rig.json: per frame, where the head, face, neck, hand and
  shield are (frame pixels), and whether the frame is seen from behind; plus each weapon's
  grip point.
- assets/sprites/characters/layers/*.png and assets/animations/paperdoll/*.tres: hair (front,
  back, under a hat) per hairstyle, face and eyes per face, cape (behind, and in front for
  back views), round and kite shields, gloves.
- layers/weapon_<kind>.png (+ _behind): each weapon kind in his fist in every frame, greyscale,
  with a hole where his fingers wrap the grip so the hand shows over it; on his back while he
  climbs or sits. layers/weapon_item_<id>.png: the same for a weapon with its own held picture
  (art/sheets/held_*.json, cells named by item id), in full colour.

A hairstyle with a sheet drawn in every pose (art/sheets/hair_<style>_frames.json, the body
wearing the hair on the body sheet's grid) uses that instead of its one front piece: the
hair is lifted off each pose and set on the hero's head, so it sways with him. Under every
hairstyle the top and back of his bald head are repainted in hair greys, so no pose shows
scalp where the hair doesn't reach.

Gloves come from a sheet of the body wearing them in every pose (art/sheets/gloves_frames.json):
each pose's two gloves are lifted off and set on the hero's hands (the rig's grip and shield
points), at the size the drawn body is to his.

How each kind is held (a bow upright, a staff planted, a gun pointed) and which frames hold
the weapon behind his body are in art/sheets/paperdoll_rig.json ("holds", "weapon_behind").

Hair, cape, shields, gloves and weapons are greyscale; the game tints them (hair colour, the worn
item's colour). The irises are split off the faces into their own layer for the eye colour.
"""
import json
import math
import os
import re
import sys
from collections import deque

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import slice_sheets as ss  # noqa: E402

ROOT = ss.ROOT
CHAR = os.path.join(ROOT, "assets", "sprites", "characters")
STRIP = os.path.join(CHAR, "hero.png")
MASK = os.path.join(CHAR, "hero_regions.png")
RIG = os.path.join(CHAR, "hero_rig.json")
LAYERS = os.path.join(CHAR, "layers")
ANIMS = os.path.join(ROOT, "assets", "animations", "paperdoll")
BODY_MANIFEST = os.path.join(ss.SHEETS, "paperdoll_body.json")
PREVIEW = os.path.join(ROOT, "art", "build", "paperdoll_preview.png")

# Must match Paperdoll.Region in scripts/components/paperdoll.gd.
REGIONS = ["none", "hair", "skin", "eyes", "top", "bottom", "shoes", "cape", "weapon", "shield", "gloves"]
R = {name: i for i, name in enumerate(REGIONS)}
# The colour the hair art is shown in when no hair colour is picked (the hero's chestnut).
DEFAULT_HAIR = (0.55, 0.33, 0.2)
# And the irises (the painted hero's blue).
DEFAULT_EYES = (0.25, 0.42, 0.75)
# Greyscale art's middle grey is brightened to this (of 255); see lift().
LIFT_TO = 200

# Frames seen from behind: no face, the hair's "from behind" piece, the cape in front.
BACK_VIEW = ("rope1", "rope2", "ladder1", "ladder2", "climb_idle")
# The face's expression per frame (anything not listed: normal).
EXPRESSIONS = {"idle3": "blink", "hit": "ouch", "hurt": "ouch", "faint1": "dizzy", "faint2": "dizzy"}
HAIRSTYLES = ["tousled", "long", "ponytail", "twin_tails", "bun", "crest"]
FACES = ["bright", "determined", "rosy", "freckled", "cheeky"]
WEAPON_KINDS = ["sword", "bow", "wand", "staff", "claw", "knuckle", "gun"]

# Sizes against the head's radius r (measured on the body).
HAIR_WIDTH = 2.5      # a hairstyle's front piece is this wide
HAIR_LIFT = 0.12      # and starts this far above the scalp
SCALP = 0.1           # the scalp under the hair: the head above this far over its centre,
SCALP_BACK = 0.45     # and behind this far back of it (any height down to SCALP_NAPE)
SCALP_NAPE = 0.55
SCALP_COVERED = 0.6   # drawn hair over this much of the scalp: the scalp is only repainted near it
FACE_WIDTH = 1.1      # the face (eyes to mouth) is this wide
FACE_AT = (0.2, 0.3)  # and centred this far forward and down from the head's centre
NECK = 0.95           # the neck is this far below the head's centre
SHIELD_HEIGHT = 1.25
GLOVE_REACH = 0.9     # a glove is put on a hand only if the drawn one is this near it (head radii)
SWORD_LENGTH = 1.9    # every weapon is drawn at the scale that makes the sword this long
WEAPON_LENGTH = 20    # rig "tip" is this far from "grip" along the weapon (only its direction matters)
FIST = 0.4            # the fist around a grip reaches this far from the grip point (head radii)

# Weapons worn on the fist are drawn smaller than the template sheet has them, so they fit
# his hand rather than swallowing it (the rest keep the sheet's size against the sword).
WORN_SIZE = {"claw": 0.6, "knuckle": 0.75}
# Weapons held in the fist: his fingers draw over the grip. The others are worn on the fist.
GRIPPED = ("sword", "wand", "staff", "bow", "gun")
# Weapons carried on his back while he climbs or sits, and at what angle; the rest are put away.
ON_BACK = {"sword": 125, "staff": -70, "bow": 60}
SHEATHED = BACK_VIEW + ("sit",)
# Sheets of weapons with their own held picture: one cell per weapon, named by item id.
HELD_SHEETS = "held_"
ITEMS = os.path.join(ROOT, "data", "items")

# The scale the body sheet is cut at (paperdoll_body.json): sheets drawn on its grid fit the
# hero at about this scale. Set by frame_names().
BODY_SCALE = 0.5

# Where the weapon hand and shield are, and how the head is tilted, per frame: placed by hand,
# since the hands are hard to tell apart from the rest of the body.
HAND_RIG = os.path.join(ss.SHEETS, "paperdoll_rig.json")


# ---------- reading the body ----------

def frame_names():
    global BODY_SCALE
    with open(BODY_MANIFEST) as f:
        man = json.load(f)
    BODY_SCALE = man["scale"]
    spec = man["sets"]["hero"]
    return list(spec["frames"]), spec


def distance_inside(mask):
    """Chessboard distance from each pixel of `mask` to the nearest pixel outside it."""
    d = np.zeros(mask.shape, int)
    cur = mask.copy()
    while cur.any():
        d += cur
        shrunk = cur.copy()
        shrunk[1:] &= cur[:-1]
        shrunk[:-1] &= cur[1:]
        shrunk[:, 1:] &= cur[:, :-1]
        shrunk[:, :-1] &= cur[:, 1:]
        cur = shrunk
    return d


def analyse(px):
    """The head, body axis and regions of one body frame (RGBA uint8 array)."""
    a = px[..., 3] > 127
    rgb = px[..., :3].astype(float) / 255
    mx, mn = rgb.max(2), rgb.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-3), 0)
    grey = a & (sat < 0.16) & (mx > 0.18) & (mx < 0.75)
    dark = a & (mx < 0.22)
    dist = distance_inside(a)
    r = dist.max()
    ys, xs = np.nonzero(dist >= r * 0.8)
    head = np.array([xs.mean(), ys.mean()])
    gy, gx = np.nonzero(grey)
    hips = np.array([gx.mean(), gy.mean()]) if len(gx) else head + [0, 2.5 * r]
    up = head - hips
    up /= max(np.linalg.norm(up), 1e-3)
    down = -up
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    along = (xx - head[0]) * down[0] + (yy - head[1]) * down[1]
    side = (xx - head[0]) * -down[1] + (yy - head[1]) * down[0]
    skin = a & ~grey & ~dark
    region = np.zeros(a.shape, np.uint8)
    region[skin] = R["skin"]
    region[grey] = R["bottom"]
    neck = r * NECK
    shorts_top = along[grey].min() if grey.any() else neck + 1.5 * r
    shorts_bottom = along[grey].max() if grey.any() else shorts_top + r
    feet = along[a].max()
    chest = skin & (along > neck) & (along < shorts_top + 2) & (np.abs(side) < r * 0.62)
    region[chest] = R["top"]
    soles = skin & (along > shorts_bottom + (feet - shorts_bottom) * 0.62)
    region[soles] = R["shoes"]
    return {"r": float(r), "head": head, "up": up, "region": region,
            "neck": head + down * neck, "feet_y": float(np.nonzero(a)[0].max()), "top_y": float(np.nonzero(a)[0].min())}


# ---------- placing pieces ----------

def scaled(piece_img, s):
    """A piece (PIL RGBA, sheet pixels) shrunk to game pixels."""
    arr = np.asarray(piece_img).astype(float) / 255
    rgb, alpha = ss.shrink(arr[..., :3], arr[..., 3], s)
    out = np.zeros(alpha.shape + (4,), np.uint8)
    out[..., :3] = (rgb * 255).round()
    out[..., 3] = ((alpha > 0.5) * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def place(canvas, img, anchor, at, angle=0.0):
    """Draws `img` on `canvas` with its point `anchor` on `at`, turned by `angle` degrees
    (clockwise on screen)."""
    if abs(angle) >= 0.5:
        pad = int(max(img.size) * 1.5)
        big = Image.new("RGBA", (pad * 2, pad * 2))
        big.paste(img, (int(round(pad - anchor[0])), int(round(pad - anchor[1]))))
        img = big.rotate(-angle, resample=Image.NEAREST, center=(pad, pad))
        anchor = (pad, pad)
    _paste(canvas, img, int(round(at[0] - anchor[0])), int(round(at[1] - anchor[1])))


def _paste(canvas, img, x, y):
    """alpha_composite that clips at the canvas edges."""
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(canvas.width, x + img.width), min(canvas.height, y + img.height)
    if x1 <= x0 or y1 <= y0:
        return
    canvas.alpha_composite(img.crop((x0 - x, y0 - y, x1 - x, y1 - y)), (x0, y0))


class Piece:
    """A cut piece and where its cell's origin is, in sheet pixels."""
    def __init__(self, sprite):
        self.img = sprite["image"]
        self.x, self.y = sprite["x"], sprite["y"]


def cut(manifest):
    sprites = {}
    ss.process(os.path.join(ss.SHEETS, manifest + ".json"), sprites=sprites)
    return {k.split(":", 1)[1]: Piece(v) for k, v in sprites.items()}


def body_offsets(names, cells, fw, fh):
    """Per frame, (dx, dy) that takes a point of its cell on the body sheet (in cut pixels, from
    the cell's corner) to the strip frame, the way slice_sheets.build_set put the body there
    (anchor "head", baseline "bottom"). Sheets drawn by editing the body sheet line up with it
    pixel for pixel, so their pieces land on the hero with this."""
    body = cut("paperdoll_body")
    BODY_PIECES.update(body)
    out = {}
    for n in names:
        p = body[cells[n]]
        x = round(fw / 2 - ss.head_x(p.img))
        y = fh - 1 - p.img.height
        out[n] = (x - p.x, y - p.y)
    return out


BODY_PIECES = {}  # the body sheet's cut cells, by cell name (set by body_offsets)


def without_shorts(piece, cell):
    """The pixels of a piece cut from a sheet of the body wearing something (on the body sheet's
    grid) as an RGBA array, with the body's grey shorts taken out: they are greys like the worn
    piece's, so they'd pass for hair or gloves. The shorts are where the body sheet has them."""
    arr = np.asarray(piece.img).copy()
    b = BODY_PIECES.get(cell)
    if b is None:
        return arr
    px = np.asarray(b.img).astype(float)
    mx, mn = px[..., :3].max(2), px[..., :3].min(2)
    shorts = (px[..., 3] > 0) & (mx - mn < 0.15 * np.maximum(mx, 1)) & (mx > 40) & (mx < 150)
    shorts = ss.dilate(shorts, 3)
    h, w = arr.shape[:2]
    dx, dy = b.x - piece.x, b.y - piece.y
    out = np.zeros((h, w), bool)
    ys, xs = np.nonzero(shorts)
    ys, xs = ys + dy, xs + dx
    ok = (ys >= 0) & (ys < h) & (xs >= 0) & (xs < w)
    out[ys[ok], xs[ok]] = True
    arr[out, 3] = 0
    return arr


def aligned(piece, offset):
    """A piece of a sheet drawn on the body sheet's grid, put on a blank frame where it sits on
    the body; returns (image, top-left)."""
    return piece.img, (piece.x + offset[0], piece.y + offset[1])


# ---------- the scalp ----------

def hair_grey(img):
    """The middle grey of a hair piece (0..255)."""
    arr = np.asarray(img).astype(float)
    solid = arr[..., 3] > 0
    return float(np.median(arr[solid][:, :3].mean(1))) if solid.any() else 128.0


def scalp(px, fi, back_view, grey):
    """The top and back of the bald head in one body frame, repainted in hair greys with the
    head's own shading. It goes under the hairstyle, so no pose shows a bald patch where the
    hair piece doesn't reach (the back of the head in a slash, the crown when he looks up)."""
    h, w = px.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    dx, dy = xx - fi["head"][0], yy - fi["head"][1]
    r = fi["r"]
    up, fwd = turned((0, -1), fi["tilt"]), turned((1, 0), fi["tilt"])
    above = (dx * up[0] + dy * up[1]) / r
    ahead = (dx * fwd[0] + dy * fwd[1]) / r
    head = (dx * dx + dy * dy <= (1.45 * r) ** 2) & (px[..., 3] > 127)
    if back_view:
        on = head & (above > -SCALP_NAPE)
    else:
        on = head & ((above > SCALP) | ((ahead < -SCALP_BACK) & (above > -SCALP_NAPE)))
    rgb = px[..., :3].astype(float)
    lum = rgb.mean(2)
    skin = on & (lum > 90)
    ref = np.median(lum[skin]) if skin.any() else 200.0
    out = np.zeros((h, w, 4), np.uint8)
    shade = (lum * grey / ref).clip(0, 255)
    out[..., 0] = out[..., 1] = out[..., 2] = np.where(skin, shade, lum).round().astype(np.uint8)
    out[..., 3] = np.where(on, 255, 0)
    return Image.fromarray(out, "RGBA")


# ---------- hair drawn in every pose ----------

# Poses where the drawn body matches the hero's closely enough to measure how the drawn
# heads line up with his (the others are placed by the head alone, see posed_hair).
STEADY_POSES = ("idle1", "idle2", "idle3", "idle4", "walk1", "walk2", "walk3", "walk4")


def hair_mask(arr):
    """The hair in a cell of a hair_<style>_frames sheet (RGBA): everything near its greys
    that isn't the body it's drawn on (peach skin, sky-blue shorts)."""
    rgb = arr[..., :3].astype(float)
    mx, mn = rgb.max(2), rgb.min(2)
    solid = arr[..., 3] > 0
    grey = solid & (mx - mn < 0.15 * np.maximum(mx, 1)) & (mx > 60)
    skin = solid & (rgb[..., 0] > 150) & (rgb[..., 0] > rgb[..., 2] + 40)
    shorts = solid & (rgb[..., 2] > rgb[..., 0] + 40)
    hair = solid & ~skin & ~shorts & ss.dilate(grey, 3)
    lab, n = ss.label(hair)  # drop specks of the body's outline caught near the hair
    if n > 1:
        sizes = np.bincount(lab.ravel())[1:]
        hair &= np.isin(lab, 1 + np.nonzero(sizes >= sizes.max() * 0.05)[0])
    return hair


def drawn_head(arr):
    """The centre and radius of the head (with its hair) in a drawn pose."""
    d = distance_inside(arr[..., 3] > 0)
    r = d.max()
    ys, xs = np.nonzero(d >= r * 0.8)
    return np.array([xs.mean(), ys.mean()]), float(r)


def body_fit(arr, hair, px, scales=None):
    """Lines the body a pose was drawn on up with the hero's: (scale, x, y) of the best overlap.
    The sheets are drawn at the size of the body sheet's cells, so the scale is near the body's
    own cut scale (BODY_SCALE)."""
    if scales is None:
        scales = [BODY_SCALE * k for k in (0.92, 0.96, 1.0, 1.04, 1.08)]
    slack = int(round(24 * BODY_SCALE))
    figure = (arr[..., 3] > 0) & ~ss.dilate(hair, 1)
    ours = px[..., 3] > 127
    oy, ox = np.nonzero(ours)
    best = None
    for s in scales:
        m = np.asarray(Image.fromarray((figure * 255).astype(np.uint8)).resize(
            (max(1, round(figure.shape[1] * s)), max(1, round(figure.shape[0] * s))), Image.BOX)) > 127
        my, mx_ = np.nonzero(m)
        if not len(my):
            continue
        x0 = int(round(ox.mean() - mx_.mean()))
        y0 = int(oy.max() - my.max())
        for dy in range(-slack, slack + 1):
            for dx in range(-slack, slack + 1):
                score = overlap(m, ours, x0 + dx, y0 + dy)
                if best is None or score > best[0]:
                    best = (score, s, x0 + dx, y0 + dy)
    return best[1:]


def overlap(m, ours, x, y):
    """How well mask `m` placed at (x, y) covers `ours`: shared pixels minus half the pixels
    it puts off the body."""
    h, w = ours.shape
    mh, mw = m.shape
    sx0, sy0 = max(0, -x), max(0, -y)
    ex, ey = min(mw, w - x), min(mh, h - y)
    if ex <= sx0 or ey <= sy0:
        return -1e9
    part = m[sy0:ey, sx0:ex]
    under = ours[y + sy0:y + ey, x + sx0:x + ex]
    return (part & under).sum() - 0.5 * (part & ~under).sum() - 0.5 * (m.sum() - part.sum())


def head_link(cells, names, info, frames):
    """How a drawn head maps onto the hero's, measured on the steady poses: the scale against
    the two heads' radii, and where the drawn head's centre lands, in hero head radii from
    his head's centre."""
    ks, offs = [], []
    for n, fi, px in zip(names, info, frames):
        arr = cells.get(n)
        if n not in STEADY_POSES or arr is None:
            continue
        s, x, y = body_fit(arr, hair_mask(arr), px)
        c, r = drawn_head(arr)
        ks.append(s * r / fi["r"])
        offs.append((np.array([x, y]) + c * s - fi["head"]) / fi["r"])
    return float(np.median(ks)), np.median(np.array(offs), axis=0)


def hides_face(img, fi):
    """Whether hair covers most of the face (the middle of it, where the eyes are)."""
    at = fi["head"] + turned(FACE_AT, fi["tilt"]) * fi["r"]
    a = np.asarray(img)[..., 3] > 0
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    face = (xx - at[0]) ** 2 + (yy - at[1]) ** 2 <= (fi["r"] * 0.35) ** 2
    return a[face].mean() > 0.5


def posed_hair(arr, fi, link):
    """The hair of one drawn pose, shrunk to the hero's size, with the drawn head's centre on
    his. Returns (image, top-left)."""
    k, off = link
    hair = hair_mask(arr)
    c, r = drawn_head(arr)
    s = k * fi["r"] / r
    at = fi["head"] + turned(off, fi["tilt"]) * fi["r"] - c * s
    cut = arr.copy()
    cut[~hair] = 0
    grey = cut[..., :3].mean(2, keepdims=True)
    cut[..., :3] = np.repeat(grey, 3, 2).round().astype(np.uint8)
    return scaled(Image.fromarray(cut, "RGBA"), s), (int(round(at[0])), int(round(at[1])))


# ---------- gloves drawn on the body ----------

def worn_mask(arr):
    """A worn piece in a cell of a sheet of the body wearing it (RGBA): its greys and their
    outline, without the body (peach skin, a cream undershirt, sky-blue shorts) or coloured
    fringe left by the background."""
    rgb = arr[..., :3].astype(float)
    mx, mn = rgb.max(2), rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1)
    solid = arr[..., 3] > 0
    grey = solid & (sat < 0.15) & (mx > 60)
    skin = solid & (rgb[..., 0] > 150) & (rgb[..., 0] > rgb[..., 2] + 40)
    shorts = solid & (rgb[..., 2] > rgb[..., 0] + 40)
    return solid & ~skin & ~shorts & ss.dilate(grey, 2) & ((sat < 0.3) | (mx < 90))


def posed_gloves(arr, px, hands, reach):
    """The two gloves of one drawn pose, sized to the hero, each centred on the hand of his
    nearest to where it sits on the drawn body (no further than `reach`). Returns
    [(image, top-left)]."""
    ys = np.nonzero(arr[..., 3] > 0)[0]
    ours = np.nonzero(px[..., 3] > 127)[0]
    base = (ours.max() - ours.min() + 1) / (ys.max() - ys.min() + 1)
    s, x, y = body_fit(arr, np.zeros(arr.shape[:2], bool), px, [base * k for k in (0.92, 0.96, 1.0, 1.04, 1.08)])
    mask = worn_mask(arr)
    lab, n = ss.label(mask)
    if not n:
        return []
    # each hand takes the nearest sizeable piece that sits near it on the fitted body (a
    # piece of shirt or a stray outline elsewhere stays behind)
    sizes = np.bincount(lab.ravel())[1:]
    centres = {}
    for i in np.nonzero(sizes >= max(sizes.max() * 0.15, 8))[0]:
        gy, gx = np.nonzero(lab == i + 1)
        if max(np.ptp(gy), np.ptp(gx)) * s <= reach:  # glove-sized
            centres[i] = np.array([x + gx.mean() * s, y + gy.mean() * s])
    out = []
    for hand in hands:
        near = sorted((np.hypot(*(c - hand)), i) for i, c in centres.items())
        if not near or near[0][0] > reach:
            continue
        i = near[0][1]
        del centres[i]
        gy, gx = np.nonzero(lab == i + 1)
        y0, y1, x0, x1 = gy.min(), gy.max() + 1, gx.min(), gx.max() + 1
        part = lab[y0:y1, x0:x1] == i + 1
        cut = arr[y0:y1, x0:x1].copy()
        cut[~part] = 0
        grey = cut[..., :3].mean(2, keepdims=True)
        cut[..., :3] = np.repeat(grey, 3, 2).round().astype(np.uint8)
        img = scaled(Image.fromarray(cut, "RGBA"), s)
        out.append((img, (int(round(hand[0] - img.width / 2)), int(round(hand[1] - img.height / 2)))))
    return out


# ---------- weapons ----------

def weapon(piece, s):
    """A weapon shrunk to game pixels, its green grip dot painted over; returns (image, grip)."""
    arr = np.asarray(piece.img).astype(int)
    green = (arr[..., 1] > 170) & (arr[..., 0] < 120) & (arr[..., 2] < 120) & (arr[..., 3] > 0)
    # dots drawn off the weapon (beside it on the background, as some held_* sheets have them)
    # are dropped, and don't count for the grip
    lab, n = ss.label(green)
    solid = (arr[..., 3] > 0) & ~green
    for i in range(1, n + 1):
        dot = lab == i
        ring = ss.dilate(dot, 3) & ~ss.dilate(green, 0)
        if ring.any() and solid[ring].mean() < 0.3:
            arr[dot, 3] = 0
            green &= ~dot
    gy, gx = np.nonzero(green)
    grip = (gx.mean(), gy.mean()) if len(gx) else (arr.shape[1] * 0.15, arr.shape[0] / 2)
    if len(gx):
        solid = (arr[..., 3] > 0) & ~green
        fill = arr[solid][:, :3].mean(0)
        near = ss.dilate(green, 2) & solid
        if near.any():
            fill = arr[near][:, :3].mean(0)
        arr[ss.dilate(green, 1) & (arr[..., 3] > 0), :3] = fill
        grey = arr[..., :3].mean(2, keepdims=True)  # the dot's surroundings are grey already
        arr[..., :3] = np.where(ss.dilate(green, 1)[..., None], grey, arr[..., :3])
    img = scaled(Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA"), s)
    return img, [round(grip[0] * s, 1), round(grip[1] * s, 1)]


def hand_rig(fw):
    """paperdoll_rig.json's frames and holds, its points scaled from the frame size they were
    placed on to the strip's."""
    with open(HAND_RIG) as f:
        spec = json.load(f)
    k = fw / spec.get("frame_size", [fw])[0]
    frames = {}
    for n, h in spec["frames"].items():
        h = dict(h)
        if "weapon" in h:
            h["weapon"] = [h["weapon"][0] * k, h["weapon"][1] * k, h["weapon"][2]]
        if "shield" in h:
            h["shield"] = [h["shield"][0] * k, h["shield"][1] * k]
        frames[n] = h
    holds = {}
    for kind, h in spec.get("holds", {}).items():
        h = dict(h)
        h["frames"] = {n: [v[0] * k, v[1] * k, v[2]] if isinstance(v, list) else v for n, v in h.get("frames", {}).items()}
        holds[kind] = h
    return frames, holds


def holds(hands, spec, names):
    """Per weapon kind, per frame: [x, y, angle] of the fist and the weapon in it (the sword's
    are the hand-placed "weapon" points), or None when the weapon isn't in his hand."""
    out = {"sword": {n: hands[n].get("weapon") for n in names}}

    def resolve(kind):
        if kind not in out:
            h = spec.get(kind, {"like": "sword"})
            base = resolve(h["like"]) if "like" in h else out["sword"]
            frames = {}
            for n in names:
                v = h.get("frames", {}).get(n, h.get("angle"))
                if base[n] is None:
                    frames[n] = None
                elif isinstance(v, list):
                    frames[n] = [round(float(c), 1) for c in v]
                else:
                    frames[n] = [base[n][0], base[n][1], base[n][2] if v is None else v]
            out[kind] = frames
        return out[kind]

    for kind in WEAPON_KINDS:
        resolve(kind)
    return out


def fist_mask(px, grip, reach):
    """The fist around `grip` on a body frame: the pixels inside its outline that a flood from the
    grip reaches without crossing the outline or going further than `reach`, plus the outline
    around them."""
    a = px[..., 3] > 127
    inside = a & (px[..., :3].max(2) > 90)
    h, w = a.shape
    yy, xx = np.mgrid[0:h, 0:w]
    near = (xx - grip[0]) ** 2 + (yy - grip[1]) ** 2 <= reach ** 2
    ok = inside & near
    if not ok.any():
        return np.zeros(a.shape, bool)
    d = np.where(ok, (xx - grip[0]) ** 2 + (yy - grip[1]) ** 2, np.inf)
    sy, sx = np.unravel_index(np.argmin(d), d.shape)
    seen = np.zeros(a.shape, bool)
    seen[sy, sx] = True
    todo = deque([(sy, sx)])
    while todo:
        y, x = todo.popleft()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < h and 0 <= nx < w and ok[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                todo.append((ny, nx))
    return ss.dilate(seen, 1) & a


def draw_turned(canvas, img, anchor, at, angle):
    """Draws `img` on `canvas` with its point `anchor` exactly on `at` (sub-pixel), turned by
    `angle` degrees clockwise, smoothly (the game filters sprites smoothly too)."""
    c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    m = (c, s, anchor[0] - c * at[0] - s * at[1], -s, c, anchor[1] + s * at[0] - c * at[1])
    layer = img.convert("RGBa").transform(canvas.size, Image.AFFINE, m, resample=Image.BICUBIC).convert("RGBA")
    canvas.alpha_composite(layer)


def weapon_strips(img, grip, kind, names, frames, info, hold, hands, r):
    """A weapon picture in his hand on every frame: (in front of him, behind him). A held weapon
    has a hole where his fist wraps it, so his fingers show over the grip."""
    front, behind = [], []
    for n, px, fi in zip(names, frames, info):
        f, b = Image.new("RGBA", (px.shape[1], px.shape[0])), Image.new("RGBA", (px.shape[1], px.shape[0]))
        if hold[n] is not None:
            x, y, angle = hold[n]
            layer = Image.new("RGBA", f.size)
            draw_turned(layer, img, grip, (x, y), angle)
            far = hands[n].get("weapon_behind", False)
            if kind in GRIPPED and not far:
                arr = np.asarray(layer).copy()
                arr[fist_mask(px, (x, y), r * FIST), 3] = 0
                layer = Image.fromarray(arr, "RGBA")
            (b if far else f).alpha_composite(layer)
        elif kind in ON_BACK and n in SHEATHED:
            down = -fi["up"]
            at = fi["neck"] + down * fi["r"] * 0.3
            centre = (img.width / 2, img.height / 2)
            (f if n in BACK_VIEW else b).alpha_composite(_turned_on(f.size, img, centre, at, ON_BACK[kind]))
        front.append(f)
        behind.append(b)
    return front, behind


def _turned_on(size, img, anchor, at, angle):
    layer = Image.new("RGBA", size)
    draw_turned(layer, img, anchor, at, angle)
    return layer


def held_pictures():
    """(item id, weapon kind, piece, sheet) for every weapon drawn on a held_*.json sheet that's there."""
    kinds = {}
    for folder, _, files in os.walk(ITEMS):
        for f in files:
            if not f.endswith(".tres"):
                continue
            with open(os.path.join(folder, f)) as fh:
                text = fh.read()
            item, kind = re.search(r'^id = &"(\w+)"', text, re.M), re.search(r'^weapon_kind = &"(\w+)"', text, re.M)
            if item and kind:
                kinds[item.group(1)] = kind.group(1)
    out = []
    for f in sorted(os.listdir(ss.SHEETS)):
        if not (f.startswith(HELD_SHEETS) and f.endswith(".json")):
            continue
        with open(os.path.join(ss.SHEETS, f)) as fh:
            source = json.load(fh)["source"]
        if not os.path.exists(os.path.join(ROOT, source)):
            continue
        for item, piece in cut(f[:-5]).items():
            if item not in kinds:
                sys.exit(f"{f}: no weapon item called {item}")
            out.append((item, kinds[item], piece, f[:-5]))
    return out


# ---------- writing ----------

def lift(img):
    """Brightens greyscale art so its middle grey is near white: the game tints it by
    multiplying with a colour (Sprite3D/CanvasItem modulate), which then comes out close to
    that colour, with the art's shading."""
    arr = np.asarray(img).astype(float)
    solid = arr[..., 3] > 0
    if solid.any():
        mid = max(np.median(arr[solid][:, :3].mean(1)), 1)
        arr[..., :3] = (arr[..., :3] * LIFT_TO / mid).clip(0, 255)
    return Image.fromarray(arr.round().astype(np.uint8), "RGBA")


def save_layer(name, frames, fw, fh, index, anims, tinted=True):
    os.makedirs(LAYERS, exist_ok=True)
    os.makedirs(ANIMS, exist_ok=True)
    strip = Image.new("RGBA", (fw * len(frames), fh))
    for i, im in enumerate(frames):
        strip.alpha_composite(im, (i * fw, 0))
    if tinted:
        strip = lift(strip)
    png = os.path.join(LAYERS, name + ".png")
    strip.save(png)
    ss.write_sprite_frames(os.path.join(ANIMS, name + ".tres"), "res://" + os.path.relpath(png, ROOT),
                           fw, fh, index, anims)


def turned(v, angle):
    """A vector turned clockwise on screen by `angle` degrees."""
    a = math.radians(angle)
    return np.array([v[0] * math.cos(a) - v[1] * math.sin(a), v[0] * math.sin(a) + v[1] * math.cos(a)])


def main():
    names, spec = frame_names()
    index = {n: i for i, n in enumerate(names)}
    anims = spec["animations"]
    strip = Image.open(STRIP).convert("RGBA")
    fw, fh = strip.width // len(names), strip.height
    frames = [np.asarray(strip.crop((i * fw, 0, (i + 1) * fw, fh))) for i in range(len(names))]
    info = [analyse(f) for f in frames]
    hands, hold_spec = hand_rig(fw)
    missing = [n for n in names if n not in hands]
    if missing:
        sys.exit(f"{os.path.relpath(HAND_RIG, ROOT)} has no entry for {missing}")
    for n, fi in zip(names, info):
        fi["tilt"] = float(hands[n].get("head_tilt", 0))
    ref = info[0]  # idle1: pieces are sized against this frame
    r = ref["r"]

    hair, faces, weapons = cut("paperdoll_hair"), cut("paperdoll_faces"), cut("paperdoll_weapons")
    blank = lambda: Image.new("RGBA", (fw, fh))  # noqa: E731
    body_cells = {n: spec["frames"][n].split(":", 1)[1] for n in names}  # frame -> its cell on the body sheet
    offsets = body_offsets(names, body_cells, fw, fh)

    # hair: one transform per style from its front piece, used for all four pieces
    old = {}
    for style in HAIRSTYLES:
        front = hair[style + "_front"]
        s = r * HAIR_WIDTH / front.img.width
        head_cell = (front.x + front.img.width / 2, front.y + (r * (1 + HAIR_LIFT)) / s)
        grey = hair_grey(front.img)
        out = {"": [], "_back": [], "_hat": []}
        for n, fi, px in zip(names, info, frames):
            back_view = n in BACK_VIEW
            fs = s * fi["r"] / r  # heads are drawn a little bigger or smaller in some poses
            pieces = {"": "_behind" if back_view else "_front", "_back": None if back_view else "_back",
                      "_hat": "_behind" if back_view else "_hat"}
            for layer, which in pieces.items():
                canvas = blank()
                p = hair.get(style + which) if which else None
                if p:
                    if layer != "_back":
                        canvas.alpha_composite(scalp(px, fi, back_view, grey))
                    img = scaled(p.img, fs)
                    anchor = ((head_cell[0] - p.x) * fs, (head_cell[1] - p.y) * fs)
                    place(canvas, img, anchor, fi["head"], fi["tilt"])
                out[layer].append(canvas)
        old[style] = out[""]
        for layer, fr in out.items():
            if any(im.getbbox() for im in fr):
                save_layer(f"hair_{style}{layer}", fr, fw, fh, index, anims)

    # hairstyles drawn in every pose (hair_<style>_frames sheets) replace the front piece
    for style in HAIRSTYLES:
        manifest = os.path.join(ss.SHEETS, f"hair_{style}_frames.json")
        if os.path.exists(manifest):
            drawn = cut(f"hair_{style}_frames")
            cells = {n: without_shorts(drawn[body_cells[n]], body_cells[n]) for n in names if body_cells[n] in drawn}
            link = head_link(cells, names, info, frames)
            out = []
            for n, fi, px in zip(names, info, frames):
                canvas = blank()
                drawn_hair = blank()
                if n in cells:
                    hair_img, at = posed_hair(cells[n], fi, link)
                    _paste(drawn_hair, hair_img, *at)
                # where the drawn hair covers the scalp, the scalp only just around it (it fills
                # slivers where the heads don't quite line up, and doesn't show as a band under a
                # high hairline); where it leaves the crown bald (a ponytail drawn as the tail
                # alone), all of it, so the top of his head is hair
                bald = np.asarray(scalp(px, fi, n in BACK_VIEW, 128)).copy()
                near = ss.dilate(np.asarray(drawn_hair)[..., 3] > 0, 3)
                top = bald[..., 3] > 0
                if top.any() and (near & top).sum() > top.sum() * SCALP_COVERED:
                    bald[~near, 3] = 0
                canvas.alpha_composite(Image.fromarray(bald, "RGBA"))
                if n in BACK_VIEW or not hides_face(drawn_hair, fi):
                    canvas.alpha_composite(drawn_hair)
                else:  # drawn in a pose too unlike his (lying face down): the one-piece hair
                    canvas = old[style][index[n]]
                out.append(canvas)
            save_layer(f"hair_{style}", out, fw, fh, index, anims)
            for gone in ("_back",):  # the drawn poses include the hair behind the head
                for path in (os.path.join(LAYERS, f"hair_{style}{gone}.png"), os.path.join(ANIMS, f"hair_{style}{gone}.tres")):
                    if os.path.exists(path):
                        os.remove(path)

    # faces: the irises (drawn in greys) go on their own layer for the eye colour
    for face in FACES:
        normal = faces[face + "_normal"]
        s = r * FACE_WIDTH / normal.img.width
        centre = (normal.x + normal.img.width / 2, normal.y + normal.img.height / 2)
        out, eyes = [], []
        for n, fi in zip(names, info):
            canvas, iris = blank(), blank()
            if n not in BACK_VIEW:
                p = faces[face + "_" + EXPRESSIONS.get(n, "normal")]
                img = scaled(p.img, s)
                anchor = ((centre[0] - p.x) * s, (centre[1] - p.y) * s)
                at = fi["head"] + turned(FACE_AT, fi["tilt"]) * fi["r"]
                place(canvas, img, anchor, at, fi["tilt"])
                px = np.asarray(canvas).copy()
                rgb = px[..., :3].astype(float) / 255
                mx, mn = rgb.max(2), rgb.min(2)
                grey = (px[..., 3] > 0) & (mx - mn < 0.1) & (mx > 0.28) & (mx < 0.8)
                ip = np.zeros_like(px)
                ip[grey] = px[grey]
                px[grey] = 0
                canvas, iris = Image.fromarray(px, "RGBA"), Image.fromarray(ip, "RGBA")
            out.append(canvas)
            eyes.append(iris)
        save_layer(f"face_{face}", out, fw, fh, index, anims, tinted=False)
        save_layer(f"face_{face}_eyes", eyes, fw, fh, index, anims)

    # the rig: the head, face and neck found on the body, the hands placed by hand
    held = holds(hands, hold_spec, names)
    rig_frames = []
    for n, fi in zip(names, info):
        h = hands[n]
        r2 = lambda v: [round(float(c), 1) for c in v]  # noqa: E731
        entry = {"name": n, "back": n in BACK_VIEW,
                 "head": r2(fi["head"]),
                 "head_top": r2(fi["head"] + turned((0, -fi["r"]), fi["tilt"])),
                 "head_angle": fi["tilt"],
                 "head_size": [round(fi["r"] * 2), round(fi["r"] * 2)],
                 "neck": r2(fi["neck"]),
                 "feet": [round(float(fi["head"][0]), 1), fi["feet_y"]]}
        if "weapon" in h:
            x, y, angle = h["weapon"]
            entry["grip"] = [x, y]
            entry["tip"] = r2(np.array([x, y]) + turned((WEAPON_LENGTH, 0), angle))
            entry["holds"] = {k: held[k][n] for k in WEAPON_KINDS if held[k][n] is not None}
            if h.get("weapon_behind"):
                entry["weapon_behind"] = True
        if "shield" in h:
            entry["shield"] = list(h["shield"])
        if n not in BACK_VIEW:
            entry["face"] = entry["head"]
        rig_frames.append(entry)

    # cape: behind the body, except in back views where it hangs over the back
    # (paperdoll_cape is drawn on the body sheet's grid: each pose's cape sits where it hangs)
    cape = cut("paperdoll_cape")
    behind, front = [], []
    for n in names:
        canvas = blank()
        p = cape.get(body_cells[n])
        if p:
            img, at = aligned(p, offsets[n])
            _paste(canvas, img, *at)
        (front if n in BACK_VIEW else behind).append(canvas)
        (behind if n in BACK_VIEW else front).append(blank())
    save_layer("cape", behind, fw, fh, index, anims)
    save_layer("cape_back_view", front, fw, fh, index, anims)

    # shields, on the arm (or on the back in back views): one picture per pose, put on the rig's
    # shield point. The round sheet is on the body sheet's grid (cells named by pose); the kite
    # sheet has its own layout, so its manifest's "poses" names the cell each pose uses.
    for style in ("round", "kite"):
        drawn = cut(f"paperdoll_shield_{style}")
        with open(os.path.join(ss.SHEETS, f"paperdoll_shield_{style}.json")) as f:
            poses = json.load(f).get("poses", body_cells)
        s_sh = r * SHIELD_HEIGHT / drawn[poses["idle1"]].img.height
        out = []
        for n, entry in zip(names, rig_frames):
            canvas = blank()
            p = drawn.get(poses.get(n, ""))
            if p and "shield" in entry:
                img = scaled(p.img, s_sh)
                place(canvas, img, (img.width / 2, img.height / 2), entry["shield"])
            out.append(canvas)
        save_layer(f"shield_{style}", out, fw, fh, index, anims)

    # gloves, on both hands
    if os.path.exists(os.path.join(ss.SHEETS, "gloves_frames.json")):
        drawn = cut("gloves_frames")
        out = []
        for n, px, entry in zip(names, frames, rig_frames):
            canvas = blank()
            cell = drawn.get(spec["frames"][n].split(":", 1)[1])
            points = [entry[k] for k in ("grip", "shield") if k in entry]
            if cell and points and n not in BACK_VIEW:  # climbing: his hands are off the rig's points
                for img, at in posed_gloves(np.asarray(cell.img), px, points, r * GLOVE_REACH):
                    _paste(canvas, img, *at)
            out.append(canvas)
        save_layer("gloves", out, fw, fh, index, anims)

    # weapons: every kind (greyscale, tinted per item) and every weapon with its own picture
    s_w = r * SWORD_LENGTH / weapons["sword"].img.width
    grips = {}
    pictures = [(kind, kind, weapons[kind], True, 1.0) for kind in WEAPON_KINDS]
    drawn_weapons = held_pictures()
    # a held_* sheet is drawn at its own size: it is shrunk so its weapons are, on the median,
    # as long as the template of their kind (keeping their sizes against each other)
    size = lambda p: max(p.img.size)  # noqa: E731
    by_sheet = {}
    for item, kind, piece, sheet in drawn_weapons:
        by_sheet.setdefault(sheet, []).append(size(weapons[kind]) / size(piece))
    pictures += [("item_" + item, kind, piece, False, float(np.median(by_sheet[sheet]))) for item, kind, piece, sheet in drawn_weapons]
    for name, kind, piece, tinted, k in pictures:
        img, grip = weapon(piece, s_w * WORN_SIZE.get(kind, 1.0) * k)
        if tinted:
            grips[kind] = {"grip": grip, "size": list(img.size)}
        front, behind = weapon_strips(img, grip, kind, names, frames, info, held[kind], hands, r)
        save_layer(f"weapon_{name}", front, fw, fh, index, anims, tinted)
        if any(im.getbbox() for im in behind):
            save_layer(f"weapon_{name}_behind", behind, fw, fh, index, anims, tinted)

    # the region mask and the rig
    mask = Image.new("RGBA", strip.size)
    colours = [[1, 1, 1] for _ in REGIONS]
    sums = {k: [] for k in ("skin", "bottom")}
    for i, (px, fi) in enumerate(zip(frames, info)):
        m = np.zeros(px.shape, np.uint8)
        m[..., 0] = fi["region"] * 16
        m[..., 3] = px[..., 3]
        mask.paste(Image.fromarray(m, "RGBA"), (i * fw, 0))
        for k in sums:
            sel = fi["region"] == R[k]
            if sel.any():
                sums[k].append(px[sel][:, :3].mean(0) / 255)
    skin = np.median(sums["skin"], 0).round(3).tolist()
    for k in ("skin", "top", "shoes"):
        colours[R[k]] = skin
    colours[R["bottom"]] = np.median(sums["bottom"], 0).round(3).tolist()
    colours[R["hair"]] = list(DEFAULT_HAIR)
    colours[R["eyes"]] = list(DEFAULT_EYES)
    mask.save(MASK)
    with open(RIG, "w") as f:
        json.dump({"frame_size": [fw, fh], "regions": REGIONS, "frames": rig_frames,
                   "weapons": grips, "region_colors": colours}, f, indent=1)
    print(f"{len(names)} frames of {fw}x{fh}, head radius {r:.0f}: layers in {os.path.relpath(LAYERS, ROOT)}")

    if "--preview" in sys.argv:
        preview(names, fw, fh, rig_frames)


def preview(names, fw, fh, rig_frames):
    """Every frame with each weapon kind in his hand (one row of frames per kind, split in two),
    wearing tousled hair, a face, the cape and, with the sword, a shield."""
    load = lambda n: Image.open(os.path.join(LAYERS, n + ".png"))  # noqa: E731
    have = lambda n: os.path.exists(os.path.join(LAYERS, n + ".png"))  # noqa: E731
    body = Image.open(STRIP)
    tint = lambda im, c: Image.fromarray((np.asarray(im).astype(float) * (list(c) + [1])).astype(np.uint8), "RGBA")  # noqa: E731
    steel, wood = (0.85, 0.87, 0.92), (0.75, 0.55, 0.35)
    colours = {"sword": steel, "wand": wood, "staff": wood, "bow": wood, "gun": wood, "claw": steel, "knuckle": (0.85, 0.7, 0.4)}
    rows = []
    for kind in WEAPON_KINDS:
        hair = "hair_tousled" if have("hair_tousled") else "hair_long"
        stack = [tint(load("cape"), (0.8, 0.25, 0.25))]
        if have(hair + "_back"):
            stack.append(tint(load(hair + "_back"), DEFAULT_HAIR))
        if have(f"weapon_{kind}_behind"):
            stack.append(tint(load(f"weapon_{kind}_behind"), colours[kind]))
        stack += [body, tint(load("cape_back_view"), (0.8, 0.25, 0.25)), load("face_bright"),
                  tint(load("face_bright_eyes"), (0.3, 0.6, 1.0)), tint(load(hair), DEFAULT_HAIR),
                  tint(load(f"weapon_{kind}"), colours[kind])]
        if kind == "sword":
            stack.append(tint(load("shield_round"), (0.8, 0.7, 0.4)))
        out = Image.new("RGBA", body.size, (70, 100, 70, 255))
        for im in stack:
            out.alpha_composite(im)
        rows.append(out)
    half = (len(names) + 1) // 2
    sheet = Image.new("RGBA", (fw * half, fh * 2 * len(rows)))
    for i, out in enumerate(rows):
        sheet.paste(out.crop((0, 0, fw * half, fh)), (0, fh * 2 * i))
        sheet.paste(out.crop((fw * half, 0, fw * len(names), fh)), (0, fh * (2 * i + 1)))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    sheet.save(PREVIEW)
    print(f"preview: {os.path.relpath(PREVIEW, ROOT)} (rows: {', '.join(WEAPON_KINDS)})")


if __name__ == "__main__":
    main()
