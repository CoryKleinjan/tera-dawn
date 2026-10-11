#!/usr/bin/env python3
"""Build the hero's layers from the part 2 paperdoll sheets.

The hero is drawn in layers: a bald, faceless body (assets/sprites/characters/hero.png, cut
by the paperdoll_body manifest), with hair, a face and worn gear on top. The hair, face and
shield sheets draw each piece once (or once per pose) in its own cell, not where it sits on
every frame, so this tool finds the head, neck and hands in each body frame and places the
pieces there; clothes, gloves and the cape come from sheets of the body wearing them in every
pose and are lifted off it onto his frame, writing one strip per layer that lines up frame for
frame with the body. The game plays a layer in step with the body (Paperdoll, PaperdollSprite).

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
  back, under a hat) per hairstyle, face and eyes per face, cape (behind, and in front: its
  collar and clasp, or all of it in back views), round and kite shields, gloves.
- layers/weapon_<kind>.png (+ _behind): each weapon kind in his fist in every frame, greyscale,
  with a hole where his fingers wrap the grip so the hand shows over it; on his back while he
  climbs or sits. layers/weapon_item_<id>.png: the same for a weapon with its own held picture
  (art/sheets/held_*.json, cells named by item id), in full colour.

A hairstyle with a sheet drawn in every pose (art/sheets/hair_<style>_frames.json, the body
wearing the hair on the body sheet's grid) uses that instead of its one front piece: the
hair is lifted off each pose and set on the hero's head, so it moves with him. Resting, moving and
climbing each hold one drawing (HELD_HAIR) on every frame of theirs, so the hair keeps its shape. Under every
hairstyle the top and back of his bald head are repainted in hair greys, so no pose shows
scalp where the hair doesn't reach.

Gloves come from a sheet of the body wearing them in every pose (art/sheets/gloves_frames.json):
each pose's two gloves are lifted off and set on the hero's hands (the rig's grip and shield
points), at the size the drawn body is to his.

How each kind is held (a bow upright, a staff planted, a gun pointed) and which frames hold
the weapon behind his body are in art/sheets/paperdoll_rig.json ("holds", "weapon_behind").
Rig angles are the way the weapon points; sword, wand and staff art drawn at a slant on its
sheet is measured and straightened first (AXIAL), so the angles hold whatever the art.

Hair, cape, shields, gloves and weapons are greyscale; the game tints them (hair colour, the worn
item's colour). The irises are split off the faces into their own layer for the eye colour.
"""
import copy
import json
import math
import os
import re
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageOps

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
# Tinted art darker than this is outline: lift() keeps it grey, without the sheets' plum cast.
OUTLINE_DARK = 110

# Frames seen from behind: no face, the hair's "from behind" piece, the cape in front.
BACK_VIEW = ("rope1", "rope2", "ladder1", "ladder2", "climb_idle")
# The face's expression per frame (anything not listed: normal).
EXPRESSIONS = {"blink": "blink", "hit": "ouch", "hurt": "ouch", "faint1": "dizzy", "faint2": "dizzy"}
HAIRSTYLES = ["tousled", "long", "ponytail", "twin_tails", "bun", "crest"]
FACES = ["bright", "determined", "rosy", "freckled", "cheeky"]
WEAPON_KINDS = ["sword", "bow", "wand", "staff", "claw", "knuckle", "gun"]

# Sizes against the head's radius r (measured on the body).
HAIR_WIDTH = 2.5      # a hairstyle's front piece is this wide
HAIR_LIFT = 0.12      # and starts this far above the scalp
SCALP = 0.1           # the scalp under the hair: the head down to a hairline this far over its centre,
SCALP_BACK = 0.45     # and behind this far back of it (any height down to SCALP_NAPE), rounded off
SCALP_NAPE = 0.55     # around the face (FACE_ZONE)
SCALP_COVERED = 0.6   # drawn hair over this much of the scalp: the scalp is only repainted near it
FACE_WIDTH = 1.3      # the face (eyes to mouth) is this wide
FACE_AT = (0.2, 0.3)  # and centred this far forward and down from the head's centre
# The face's bare skin, as an egg around FACE_AT: how far it reaches back (to the ear), forward,
# up (to the hairline) and down (past the chin) from there. A hat's hair leaves it clear.
FACE_ZONE = (FACE_AT[0] + SCALP_BACK, 1.0, FACE_AT[1] + SCALP, 0.7)
BLANK_FACE = 222      # the hair sheet's blank faces are greys at least this pale (of 255)
NECK_SLIVER = 120     # loose bits under the jaw smaller than this (pixels) are left-over neck outline
HAT_SHOULDER_ROWS = 6  # hat sheet cells are lined up by their bottom rows (the shoulders)
HAT_SIZE = 1.0         # hats drawn this much bigger than his head against the sheet's head
HAT_SPECK = 0.05  # hat_alone: pieces under this share of the hat are cell-frame bits
HAT_SHAPES = ("cap", "hood", "bandana", "helm", "wizard", "tricorn")
# Chibi faces: each eye (with its brow) is drawn this much bigger about its own centre. The eyes
# are everything above EYE_LINE (a fraction of the normal face's height), left or right of its middle.
# 1.0 since the painted faces (2026-10-11), drawn at the size Cory wants: smaller, older eyes.
EYE_SCALE = 1.0
EYE_LINE = 0.6
NECK = 0.95           # the neck is this far below the head's centre
SHIELD_HEIGHT = 1.25
# Clothes sheets (art/sheets/<place>_<style>_frames.json) for these places; styles whose sheet
# came back unusable are skipped (their items wear the nearest cut, see EquipDef.worn_style).
WORN_PLACES = ("top", "bottom", "shoes")
WORN_BROKEN = ("smock",)
WORN_SHORTS_GREY = 150  # the body's shorts are greys darker than this
WORN_OUTLINE = 90       # and outlines darker than this
WORN_FRINGE = 110       # pale edge pixels at the figure's edge are background fringe
GLOVE_REACH = 0.9     # a glove is put on a hand only if the drawn one is this near it (head radii)
SWORD_LENGTH = 1.9    # every weapon is drawn at the scale that makes the sword this long
WEAPON_LENGTH = 20    # rig "tip" is this far from "grip" along the weapon (only its direction matters)
FIST = 0.4            # the fist around a grip reaches this far from the grip point (head radii)

# Weapons worn on the fist are drawn smaller than the template sheet has them, so they fit
# his hand rather than swallowing it (the rest keep the sheet's size against the sword).
WORN_SIZE = {"claw": 0.6, "knuckle": 0.75, "bow": 1.35}
# Long weapons whose sheets may draw them at a slant (a sword up and to the right): their own
# axis is measured and turned out, so a rig angle means the same however the art was drawn.
# The others are drawn the way the rig expects (a gun and claws pointing right, a bow upright).
AXIAL = ("sword", "wand", "staff")
# Weapons the rig holds upright (see stood_up), and how far off upright (degrees) one may be
# drawn before it is stood up.
UPRIGHT = ("bow",)
UPRIGHT_SLACK = 8
# Weapons held in the fist: his fingers draw over the grip. The others are worn on the fist.
GRIPPED = ("sword", "wand", "staff", "bow", "gun")
# Weapons carried on his back while he climbs or sits, and at what angle; the rest are put away.
ON_BACK = {"sword": 125, "staff": -70, "bow": 60, "wand": 125, "gun": 110}
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
    arr[shorts_mask(piece, cell, 3), 3] = 0
    return arr


def shorts_mask(piece, cell, grow):
    """Where the body sheet has its grey shorts, on a piece of a sheet drawn on its grid (a
    bool mask the piece's size), grown by `grow` pixels, since a redrawn sheet may sit a pixel
    or two off the body."""
    h, w = piece.img.height, piece.img.width
    out = np.zeros((h, w), bool)
    b = BODY_PIECES.get(cell)
    if b is None:
        return out
    px = np.asarray(b.img).astype(float)
    mx, mn = px[..., :3].max(2), px[..., :3].min(2)
    shorts = ss.dilate((px[..., 3] > 0) & (mx - mn < 0.15 * np.maximum(mx, 1)) & (mx > 40) & (mx < 150), grow)
    ys, xs = np.nonzero(shorts)
    ys, xs = ys + b.y - piece.y, xs + b.x - piece.x
    ok = (ys >= 0) & (ys < h) & (xs >= 0) & (xs < w)
    out[ys[ok], xs[ok]] = True
    return out


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


def head_axes(shape, fi, centre):
    """Per pixel of a frame: how far it is (head radii) ahead of and above `centre`, along the
    head's own forward and up (turned with its tilt)."""
    h, w = shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    dx, dy = xx - centre[0], yy - centre[1]
    up, fwd = turned((0, -1), fi["tilt"]), turned((1, 0), fi["tilt"])
    return (dx * fwd[0] + dy * fwd[1]) / fi["r"], (dx * up[0] + dy * up[1]) / fi["r"]


def face_zone(px, fi):
    """The face on a body frame, forehead to chin and ear to cheek: the part of the head inside
    an egg around the face's centre (FACE_ZONE), as a bool mask. No hair is drawn there under a
    hat, and the scalp's hairline follows its rounded top instead of a straight cut."""
    back, front, top, bottom = FACE_ZONE
    ahead, above = head_axes(px.shape, fi, fi["head"] + turned(FACE_AT, fi["tilt"]) * fi["r"])
    sx = np.where(ahead < 0, back, front)
    sy = np.where(above > 0, top, bottom)
    near = np.hypot(*head_axes(px.shape, fi, fi["head"])) <= 1.1  # the head, not the neck below it
    return ((ahead / sx) ** 2 + (above / sy) ** 2 <= 1) & near & (px[..., 3] > 127)


def bare_face(img, px, fi):
    """A hair-under-a-hat layer with the face cut out of it, so the hero's face shows through:
    the face_zone, and the rest of the blank face the sheet draws inside the hair (its palest
    greys, where they run on from the face zone below the eyes: the cheek and jaw), with its
    outline."""
    arr = np.asarray(img).copy()
    zone = face_zone(px, fi)
    rgb = arr[..., :3].astype(int)
    blank = (arr[..., 3] > 0) & (rgb.min(2) >= BLANK_FACE) & (rgb.max(2) - rgb.min(2) < 12)
    ahead, above = head_axes(px.shape, fi, fi["head"])
    blank &= (np.hypot(ahead, above) <= 1.45) & (above < 0)  # cheek and jaw: not pale streaks in the bangs
    lab, n = ss.label(blank | zone)
    if n:
        clear = np.isin(lab, np.unique(lab[zone]))
        arr[ss.dilate(clear, 1) & (rgb.min(2) >= BLANK_FACE - 40), 3] = 0  # and its soft edge
        # and the blank's own outline where it runs across his cheek and jaw (the drawn blank
        # is a little smaller than his face), so no line is left on his skin
        arr[ss.dilate(clear, 3) & (above < 0) & ((rgb.max(2) < BLANK_FACE - 60) | (rgb.min(2) >= BLANK_FACE - 80)), 3] = 0
        arr[clear, 3] = 0
    return Image.fromarray(no_neck(arr, fi), "RGBA")


def no_neck(arr, fi):
    """A hair-under-a-hat layer without the rest of the sheet's blank head below the face: the
    pale neck and ear left under the hair, with their outline. Tinted with the hair colour they
    showed as a brown wedge on his neck and chest."""
    rgb = arr[..., :3].astype(int)
    solid = arr[..., 3] > 0
    pale = solid & (rgb.min(2) >= BLANK_FACE - 30) & (rgb.max(2) - rgb.min(2) < 12)
    ahead, above = head_axes(arr.shape, fi, fi["head"])
    lab, n = ss.label(pale)
    if not n:
        return arr
    low = np.zeros(n + 1, bool)
    for i in range(1, n + 1):  # a pale piece mostly below the middle of his head: skin, not a shine
        part = lab == i
        low[i] = part.sum() >= 6 and np.median(above[part]) < -0.25
    skin = low[lab]
    out = arr.copy()
    if skin.any():
        # its outline: the dark pixels just around it that aren't hair (no mid grey beside them)
        mid = solid & ~pale & (rgb.min(2) >= 90)
        edge = ss.dilate(skin, 3) & solid & ~mid & ~ss.dilate(mid & ~ss.dilate(skin, 1), 1)
        out[skin | edge, 3] = 0
        # and the slivers of that outline left loose under his jaw
        lab, n = ss.label(out[..., 3] > 0)
        for i in range(1, n + 1):
            part = lab == i
            if part.sum() < NECK_SLIVER and np.median(above[part]) < -0.25:
                out[part, 3] = 0
    return out


def scalp(px, fi, back_view, grey):
    """The top and back of the bald head in one body frame, repainted in hair greys with the
    head's own shading. It goes under the hairstyle, so no pose shows a bald patch where the
    hair piece doesn't reach (the back of the head in a slash, the crown when he looks up).
    Facing us, it stops at a hairline around the face (face_zone)."""
    h, w = px.shape[:2]
    ahead, above = head_axes(px.shape, fi, fi["head"])
    head = (ahead ** 2 + above ** 2 <= 1.45 ** 2) & (px[..., 3] > 127)
    on = head & (above > -SCALP_NAPE)
    if not back_view:
        on &= ~face_zone(px, fi)
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

# Poses that all wear one drawn pose's hair, set on each frame's head (and turned with it):
# the sheets draw the hair afresh in every pose, and differently each time (hanging in one,
# blown sideways in the next, a shade lighter or darker), so playing the poses redrew it on
# every frame and snapped it between shapes whenever an action began. Holding one drawing per
# family, the hair bobs and tilts with his head but keeps its shape: one at rest, one on the
# move (streaming back), one from behind while he climbs. Poses in no family (lying in a
# faint) keep their own. The pose to hold is the cleanest drawing of the family;
# HELD_HAIR_STYLE picks another for a style whose usual one came out badly.
HELD_HAIR = {
    "rest": ("idle1", ("idle1", "idle2", "idle3", "idle4", "walk1", "walk2", "walk3", "walk4",
                       "attack1", "attack2", "hit", "hurt", "land", "crouch", "slash1", "slash2",
                       "slash3", "levelup", "sit", "blink")),
    "moving": ("run2", ("run1", "run2", "run3", "run4", "jump", "fall")),
    "climbing": ("ladder1", ("rope1", "rope2", "ladder1", "ladder2", "climb_idle")),
}
HELD_HAIR_STYLE = {}
# A drawn tail or bun no further than this from the head (head radii) is pulled in to touch
# it; the sheets sometimes leave a gap between a ponytail and the head it hangs from.
HAIR_REACH = 0.4
# A drawn piece of hair this far or nearer from the rest of the hair (head radii) is moved in to
# touch it (a pigtail or tail drawn a little apart from the hair it hangs from); a loose piece
# smaller than HAIR_SPECK pixels is a speck of the sheet (a stray outline) and goes.
HAIR_JOIN = 0.35
HAIR_SPECK = 60
HAIR_STRAY = 0.05     # a far piece smaller than this share of the hair is not hair
# Hair under a hat: a loose piece centred this far below his head's centre (head radii) is a
# strand the sheet drew down his chest, not hair on his head.
HAT_HAIR_LOW = 1.2
HAT_HAIR_JOIN = 0.8   # and a loose piece this near the rest is moved in (joined)
# Styles drawn as a tail alone (no hair on top of the head): their crown comes from the style's
# one-piece hair under a hat, combed back with its strands, instead of a plain grey cap.
CROWN_FROM_HAT = ("ponytail",)


def held_hair_pose(style, n):
    """The drawn pose whose hair frame `n` wears for `style`: its family's held pose, or `n`."""
    for family, (pose, frames) in HELD_HAIR.items():
        if n in frames:
            return HELD_HAIR_STYLE.get(style, {}).get(family, pose)
    return n


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


class Drawn:
    """A piece made here rather than cut from a sheet (same fields as Piece)."""
    def __init__(self, img, x, y):
        self.img, self.x, self.y = img, x, y


def chibi(piece, normal):
    """A face piece with bigger eyes (EYE_SCALE), each grown about its centre on the face's
    normal expression, so every expression's eyes grow in the same place; the nose, mouth and
    cheeks below EYE_LINE stay as drawn, which leaves them small and close under the eyes."""
    if EYE_SCALE == 1:
        return piece
    a = np.asarray(piece.img)
    n = np.asarray(normal.img)[..., 3] > 0
    w, h = normal.img.size
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    left = xx + piece.x - normal.x < w / 2
    eyes = yy + piece.y - normal.y < EYE_LINE * h
    ny, nx = np.nonzero(n)
    pad = int(max(w, h) * (EYE_SCALE - 1))
    out = Image.new("RGBA", (a.shape[1] + 2 * pad, a.shape[0] + 2 * pad))
    rest = a.copy()
    rest[eyes] = 0
    out.alpha_composite(Image.fromarray(rest, "RGBA"), (pad, pad))
    for is_left in (True, False):
        part = a.copy()
        part[~(eyes & (left == is_left))] = 0
        on = (ny < EYE_LINE * h) & ((nx < w / 2) == is_left)
        if not part[..., 3].any() or not on.any():
            continue
        # the eye's centre on the normal face, in this piece's pixels
        cx = (nx[on].min() + nx[on].max()) / 2 + normal.x - piece.x
        cy = (ny[on].min() + ny[on].max()) / 2 + normal.y - piece.y
        img = Image.fromarray(part, "RGBA")
        big = img.resize((round(img.width * EYE_SCALE), round(img.height * EYE_SCALE)), Image.NEAREST)
        out.alpha_composite(big, (int(round(pad + cx - cx * EYE_SCALE)), int(round(pad + cy - cy * EYE_SCALE))))
    box = out.getbbox()
    return Drawn(out.crop(box), piece.x - pad + box[0], piece.y - pad + box[1])


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



def above_fringe(hair):
    """Where the scalp may show on a head seen from the front: in each column, from the top
    of the drawn hair down to its lowest pixel there (the fringe). Below that is his forehead,
    which the scalp painted as a flat band of hair colour between the fringe and the eyes."""
    rows = np.arange(hair.shape[0])[:, None]
    any_ = hair.any(0)
    low = np.where(any_, hair.shape[0] - 1 - np.argmax(hair[::-1], 0), -1)
    return rows <= low[None, :]


def toned(img, grey):
    """A greyscale piece brightened or darkened so its middle grey is `grey` (0..255)."""
    arr = np.asarray(img).astype(float)
    k = grey / max(hair_grey(img), 1.0)
    arr[..., :3] = (arr[..., :3] * k).clip(0, 255)
    return Image.fromarray(arr.round().astype(np.uint8), "RGBA")


def pulled_in(img, fi):
    """Drawn hair with any piece that floats just off his head (a ponytail drawn a little
    behind the head it hangs from) moved straight in until it touches the head."""
    arr = np.asarray(img).copy()
    solid = arr[..., 3] > 0
    lab, n = ss.label(solid)
    if n < 1:
        return img
    yy, xx = np.mgrid[0:solid.shape[0], 0:solid.shape[1]]
    dist = np.hypot(xx - fi["head"][0], yy - fi["head"][1]) / fi["r"] - 1.0  # head radii off the head
    out = np.zeros_like(arr)
    for i in range(1, n + 1):
        part = lab == i
        gap = dist[part].min()
        if gap <= 0 or gap > HAIR_REACH:
            out[part] = arr[part]
            continue
        # the nearest point of the piece, moved in along the line to the head's centre
        k = np.argmin(np.where(part, dist, np.inf))
        py, px_ = divmod(k, solid.shape[1])
        v = np.array(fi["head"]) - (px_, py)
        step = v / np.linalg.norm(v) * gap * fi["r"]
        dx, dy = int(round(step[0])), int(round(step[1]))
        ys, xs = np.nonzero(part)
        ty, tx = ys + dy, xs + dx
        ok = (ty >= 0) & (ty < solid.shape[0]) & (tx >= 0) & (tx < solid.shape[1])
        out[ty[ok], tx[ok]] = arr[ys[ok], xs[ok]]
    return Image.fromarray(out, "RGBA")

def joined(img, fi, reach=HAIR_JOIN, behind=None):
    """Drawn hair in one piece: every loose piece near the main hair (`reach` head radii) moved
    straight in until it touches it, so no tail floats apart; specks (HAIR_SPECK) dropped. A
    moved piece goes behind `behind` (a mask: his face), hidden where it would cover it."""
    arr = np.asarray(img).copy()
    lab, n = ss.label(arr[..., 3] > 0)
    if n < 2:
        return img
    sizes = np.bincount(lab.ravel())[1:]
    biggest = int(sizes.argmax()) + 1
    main = lab == biggest
    out = arr.copy()
    out[(lab > 0) & ~main, 3] = 0
    ys0, xs0 = np.nonzero(main)
    reach = reach * fi["r"]
    for i in range(1, n + 1):
        part = lab == i
        if i == biggest or sizes[i - 1] < HAIR_SPECK:
            continue
        ys, xs = np.nonzero(part)
        # the closest pair of points between the piece and the main hair (sampled for speed)
        step = max(len(ys) // 400, 1)
        py, px_ = ys[::step], xs[::step]
        d = np.hypot(px_[:, None] - xs0[None, ::4], py[:, None] - ys0[None, ::4])
        k = np.unravel_index(d.argmin(), d.shape)
        gap = d[k]
        if gap > reach:
            if sizes[i - 1] >= sizes.max() * HAIR_STRAY:  # big and far: drawn apart on purpose
                out[part] = arr[part]
            continue  # else a bit of the body's outline caught with the hair (an ear, a hand)
        v = np.array([xs0[::4][k[1]] - px_[k[0]], ys0[::4][k[1]] - py[k[0]]], float)
        move = v / max(np.linalg.norm(v), 1e-6) * max(gap - 1.0, 0.0)
        ty, tx = ys + int(round(move[1])), xs + int(round(move[0]))
        ok = (ty >= 0) & (ty < arr.shape[0]) & (tx >= 0) & (tx < arr.shape[1])
        keep = out[ty[ok], tx[ok], 3] == 0  # under the main hair where they overlap
        if behind is not None:
            keep &= ~behind[ty[ok], tx[ok]]
        out[ty[ok][keep], tx[ok][keep]] = arr[ys[ok][keep], xs[ok][keep]]
    return Image.fromarray(out, "RGBA")

def no_low_strands(img, fi):
    """A hair-under-a-hat layer without loose pieces hanging down on his body (HAT_HAIR_LOW);
    the pieces at his head (a pigtail beside his cheek) stay."""
    arr = np.asarray(img).copy()
    lab, n = ss.label(arr[..., 3] > 0)
    if n < 2:
        return img
    sizes = np.bincount(lab.ravel())[1:]
    _, above = head_axes(arr.shape, fi, fi["head"])
    for i in range(1, n + 1):
        part = lab == i
        if i != int(sizes.argmax()) + 1 and np.median(above[part]) < -HAT_HAIR_LOW:
            arr[part, 3] = 0
    return Image.fromarray(arr, "RGBA")

# ---------- hats ----------

def hat_head(piece):
    """Where the bald head of a paperdoll_hats cell is: the cells draw the same head and
    shoulders, cut off at the cell's bottom, so a cell is lined up with another by the middle of
    its shoulders on its bottom row. Returns that point (cell pixels)."""
    arr = np.asarray(piece.img)
    solid = arr[..., 3] > 0
    rows = np.nonzero(solid.any(1))[0]
    low = solid[rows.max() - HAT_SHOULDER_ROWS:rows.max() + 1]
    xs = np.nonzero(low)[1]
    return np.array([piece.x + xs.mean(), piece.y + rows.max() + 1.0])


def hat_alone(img):
    """A hats_only piece without the bits of the sheet's cell frame caught at its edges: every
    piece much smaller than the hat goes."""
    arr = np.asarray(img).copy()
    lab, n = ss.label(arr[..., 3] > 0)
    sizes = np.bincount(lab.ravel())[1:]
    if n:
        arr[(lab > 0) & (sizes[lab - 1] < sizes.max() * HAT_SPECK), 3] = 0
    return Image.fromarray(arr)


def bald_head(piece):
    """The bald head of the hat sheet's hatless cell: (centre, radius) in cell pixels. Its top
    is the topmost pixel; its chin the narrowest row of the neck below the widest row."""
    arr = np.asarray(piece.img)
    solid = arr[..., 3] > 0
    widths = solid.sum(1)
    top = int(np.nonzero(widths)[0].min())
    widest = int(widths.argmax())
    neck = widths[widest:widest + max(int((len(widths) - widest) * 0.7), 1)]
    chin = widest + int(neck.argmin())
    r = (chin - top) / 2.0
    return np.array([piece.x + solid[widest].nonzero()[0].mean(), piece.y + top + r]), r


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
    """The two gloves of one drawn pose, sized to the hero, each centred on a hand of his: the
    glove drawn nearest to it on the fitted body (first within `reach`, then any). Returns
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
    # each hand takes the nearest glove that sits near it; a hand left without one (the sheet's
    # body is posed a little unlike his, so its hands sit elsewhere) then takes the nearest one
    # left anywhere, and failing that a copy of the other hand's
    pick = {}
    for limit in (reach, np.inf):
        for h, hand in enumerate(hands):
            if h in pick:
                continue
            near = sorted((np.hypot(*(c - hand)), i) for i, c in centres.items())
            if near and near[0][0] <= limit:
                pick[h] = near[0][1]
                del centres[near[0][1]]
    for h in range(len(hands)):
        if h not in pick and pick:
            pick[h] = next(iter(pick.values()))
    out = []
    for h, hand in enumerate(hands):
        if h not in pick:
            continue
        i = pick[h]
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


# ---------- clothes drawn on the body ----------

def posed_worn(piece, cell, px, place):
    """The clothes of one drawn pose of a <place>_<style>_frames sheet (the body wearing a top,
    a bottom or shoes), lifted off the body in greys and fitted onto the hero's frame. The
    sheets keep the body's grey shorts: a bottom is drawn over them, so they count as part of
    it; for a top or shoes they're the body, so the shorts' dark greys are left out (a light
    tunic hem over them stays). Returns (image, top-left), or None if nothing was found."""
    arr = np.asarray(piece.img)
    if not (arr[..., 3] > 0).any():
        return None
    ys = np.nonzero(arr[..., 3] > 0)[0]
    ours = np.nonzero(px[..., 3] > 127)[0]
    base = (ours.max() - ours.min() + 1) / (ys.max() - ys.min() + 1)
    s, x, y = body_fit(arr, np.zeros(arr.shape[:2], bool), px, [base * k for k in (0.92, 0.96, 1.0, 1.04, 1.08)])
    mask = worn_mask(arr)
    # the pale fringe some sheets leave around the whole figure isn't the clothes
    mask &= ~(ss.dilate(arr[..., 3] == 0, 2) & (arr[..., :3].max(2) > WORN_FRINGE))
    # nothing is worn on the (bald, skin) head: its outline is the body's
    rgb = arr[..., :3].astype(int)
    skin = arr.copy()
    skin[..., 3] = np.where((rgb[..., 0] > 150) & (rgb[..., 0] > rgb[..., 2] + 40), arr[..., 3], 0)
    c, r = drawn_head(skin)
    yy, xx = np.mgrid[0:arr.shape[0], 0:arr.shape[1]]
    mask &= (xx - c[0]) ** 2 + (yy - c[1]) ** 2 > (r * 1.05) ** 2
    if place != "bottom":
        mask &= ~(shorts_mask(piece, cell, 4) & (arr[..., :3].max(2) < WORN_SHORTS_GREY))
    # drop specks and bits of the body's outline caught off the clothes (pieces mostly of
    # outline darks rather than the clothes' own greys)
    lab, n = ss.label(mask)
    if not n:
        return None
    sizes = np.bincount(lab.ravel())[1:]
    filled = np.bincount(lab.ravel(), weights=(arr[..., :3].max(2) >= WORN_OUTLINE).ravel())[1:]
    keep = (sizes >= max(sizes.max() * 0.05, 6)) & (filled >= sizes * 0.4)
    mask = np.isin(lab, 1 + np.nonzero(keep)[0])
    if not mask.any():
        return None
    cut = arr.copy()
    cut[~mask] = 0
    # the sheets draw a piece paler in some poses than others: each pose's greys are brought
    # to the same middle grey, so the tinted piece doesn't flicker as he moves
    grey = cut[..., :3].astype(float).mean(2, keepdims=True)
    grey *= 128 / max(np.median(grey[mask]), 1)
    cut[..., :3] = np.repeat(grey, 3, 2).clip(0, 255).round().astype(np.uint8)
    return scaled(Image.fromarray(cut, "RGBA"), s), (int(round(x)), int(round(y)))


def worn_sheets():
    """(place, style) of every clothes sheet there is: art/sheets/<place>_<style>_frames.json
    for the places in WORN_PLACES (the body wearing that piece in every pose)."""
    out = []
    for f in sorted(os.listdir(ss.SHEETS)):
        m = re.fullmatch(r"(%s)_(\w+)_frames\.json" % "|".join(WORN_PLACES), f)
        if m and m.group(2) not in WORN_BROKEN:
            out.append((m.group(1), m.group(2)))
    return out


# ---------- weapons ----------

def weapon(piece, s, kind):
    """A weapon shrunk to game pixels, its green grip dots painted out; returns (image, grip,
    axis): axis is the way its business end points in the picture (degrees clockwise from
    pointing right), 0 for kinds not in AXIAL. Where his fist goes (see grip_point) is
    worked out from the weapon's shape for blades, wands, staffs and guns, since the sheets'
    dots are often off (on a crossguard, several for two hands, or none)."""
    arr = np.asarray(piece.img).astype(int)
    green = (arr[..., 1] > 170) & (arr[..., 0] < 120) & (arr[..., 2] < 120) & (arr[..., 3] > 0)
    opaque = arr[..., 3] > 0
    # dots drawn off the weapon (beside it on the background, as some held_* sheets have
    # them) are islands of their own: dropped with their outline, and don't count
    parts, n = ss.label(opaque)
    if n > 1:
        sizes = np.bincount(parts.ravel())[1:]
        main = int(sizes.argmax()) + 1
        for i in range(1, n + 1):
            if i != main and green[parts == i].any():
                arr[parts == i, 3] = 0
        opaque = arr[..., 3] > 0
        green &= opaque
    dots = dot_centres(green)
    axis = drawn_axis(arr) if kind in AXIAL else 0.0
    grip = grip_point(arr, kind, axis, dots)
    if green.any():
        # the dot, its shading and its thick dark outline are filled in from the weapon
        # around them
        rgb = arr[..., :3]
        greenish = (rgb[..., 1] > rgb[..., 0] + 20) & (rgb[..., 1] > rgb[..., 2] + 20)
        dark = rgb.max(2) < 80
        near = ss.dilate(green, 6)
        inpaint(arr, (ss.dilate(green, 2) | (near & (greenish | dark))) & opaque)
    img = scaled(Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA"), s)
    return img, [round(grip[0] * s, 1), round(grip[1] * s, 1)], axis


def dot_centres(green):
    """The middle of each green dot (a cluster of dots drawn together counts as one)."""
    lab, n = ss.label(ss.dilate(green, 6))
    out = []
    for i in range(1, n + 1):
        ys, xs = np.nonzero((lab == i) & green)
        if len(xs):
            out.append((float(xs.mean()), float(ys.mean())))
    return out


def inpaint(arr, hole):
    """Fills the `hole` pixels of an RGBA array with the colours around them, growing in
    from the edge (each pixel takes the mean of its already-filled neighbours)."""
    hole = hole.copy()
    known = (arr[..., 3] > 0) & ~hole
    while hole.any():
        acc = np.zeros(arr.shape[:2] + (3,))
        cnt = np.zeros(arr.shape[:2])
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy or dx:
                    k = np.roll(np.roll(known, dy, 0), dx, 1)
                    acc += np.roll(np.roll(arr[..., :3], dy, 0), dx, 1) * k[..., None]
                    cnt += k
        ready = hole & (cnt > 0)
        if not ready.any():
            break
        arr[ready, :3] = (acc[ready] / cnt[ready, None]).round().astype(int)
        known |= ready
        hole &= ~ready


def _along(arr, axis):
    """Each opaque pixel's (x, y), its distance along `axis` and across it."""
    ys, xs = np.nonzero(arr[..., 3] > 0)
    c, s = math.cos(math.radians(axis)), math.sin(math.radians(axis))
    return xs, ys, xs * c + ys * s, -xs * s + ys * c


def _on_axis(arr, axis, t):
    """The point at distance `t` along `axis`, in the middle of the weapon's width there."""
    xs, ys, a, b = _along(arr, axis)
    near = np.abs(a - t) <= max(1.0, (a.max() - a.min()) * 0.02)
    m = float(b[near].mean()) if near.any() else float(b.mean())
    c, s = math.cos(math.radians(axis)), math.sin(math.radians(axis))
    return (t * c - m * s, t * s + m * c)


def grip_point(arr, kind, axis, dots):
    """Where his fist closes on a weapon picture (its pixels):
    - a blade (sword kind): in the middle of the handle, between the pommel and the crossguard
      (the first place, going up from the pommel, that gets much wider than the handle);
    - a wand or staff: halfway along the shaft;
    - a gun: on the pistol grip (the dot nearest its back, or the part hanging below the
      barrel at the back when it has no dot);
    - anything else (bows, claws, knuckles): its dot, or a guess near its back end."""
    xs, ys, a, b = _along(arr, axis)
    lo, hi = float(a.min()), float(a.max())
    span = hi - lo
    if kind == "sword":
        bins = np.linspace(lo, hi, 41)
        width = np.array([np.ptp(b[(a >= bins[i]) & (a < bins[i + 1])]) if ((a >= bins[i]) & (a < bins[i + 1])).any() else 0
                          for i in range(40)])
        handle = float(np.median(width[2:8]))
        guard = next((i for i in range(4, 30) if width[i] > handle * 1.7), 8)
        return _on_axis(arr, axis, lo + span * (0.04 + guard / 40) / 2)
    if kind in ("wand", "staff"):
        return _on_axis(arr, axis, lo + span / 2)
    c, s = math.cos(math.radians(axis)), math.sin(math.radians(axis))
    if dots:
        return min(dots, key=lambda d: d[0] * c + d[1] * s)  # the back hand
    if kind == "gun":
        back = a < lo + span * 0.35
        below = back & (ys > np.median(ys))
        if below.any():
            return (float(xs[below].mean()), float(np.percentile(ys[below], 30)))
    return (float(arr.shape[1] * 0.15), float(arr.shape[0] / 2))


def grip_share(img, grip, axis):
    """How far along a weapon picture (0 its back end, 1 its tip) the grip is."""
    _, _, a, _ = _along(np.asarray(img), axis)
    g = grip[0] * math.cos(math.radians(axis)) + grip[1] * math.sin(math.radians(axis))
    return round(float((g - a.min()) / max(1.0, a.max() - a.min())), 3)


def dots_left(img):
    """Green dot pixels still showing in a weapon picture (should be none)."""
    arr = np.asarray(img).astype(int)
    return int(((arr[..., 1] > 170) & (arr[..., 0] < 120) & (arr[..., 2] < 120) & (arr[..., 3] > 0)).sum())


def reach(img, grip, axis):
    """How far a weapon picture reaches past its grip along `axis` (its pixels)."""
    ys, xs = np.nonzero(np.asarray(img)[..., 3] > 0)
    c, s = math.cos(math.radians(axis)), math.sin(math.radians(axis))
    return round(float(((xs - grip[0]) * c + (ys - grip[1]) * s).max()), 1)


def length(piece, kind):
    """A weapon picture's length along the way it points (its width when drawn pointing right,
    its height for a bow, which stands upright)."""
    arr = np.asarray(piece.img)
    ys, xs = np.nonzero(arr[..., 3] > 0)
    a = math.radians(drawn_axis(arr) if kind in AXIAL else 90.0 if kind in UPRIGHT else 0.0)
    t = xs * math.cos(a) + ys * math.sin(a)
    return float(t.max() - t.min() + 1)


def stood_up(piece):
    """A bow as the rig holds it: upright, its belly (the bow itself) on the right and its
    string on the left, like the bow template. The held_bows sheet draws its bows at a slant
    with the string on the right, so they are turned upright and mirrored; one already
    standing up is kept as it is."""
    img = piece.img
    axis = drawn_axis(np.asarray(img))
    if abs(axis + 90) > UPRIGHT_SLACK:
        img = img.rotate(axis + 90, resample=Image.BICUBIC, expand=True)
        img = img.crop(img.getbbox())
    xs = np.nonzero(np.asarray(img)[..., 3] > 0)[1]
    if xs.mean() < (xs.min() + xs.max()) / 2:
        img = ImageOps.mirror(img)
    if img is piece.img:
        return piece
    out = copy.copy(piece)
    out.img = img
    return out


def drawn_axis(arr):
    """The direction a long weapon lies along in its picture (degrees clockwise from pointing
    right): its long axis, taken toward the right (the sheets draw the business end to the
    right, flat or slanting up), or toward the top when it stands upright."""
    ys, xs = np.nonzero(arr[..., 3] > 0)
    pts = np.stack([xs - xs.mean(), ys - ys.mean()])
    vals, vecs = np.linalg.eigh(pts @ pts.T)
    dx, dy = vecs[:, np.argmax(vals)]
    if dx < -0.05 or (abs(dx) <= 0.05 and dy > 0):
        dx, dy = -dx, -dy
    return round(math.degrees(math.atan2(dy, dx)), 1)


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


def weapon_strips(img, grip, axis, kind, names, frames, info, hold, hands, r, far_frames=()):
    """A weapon picture in his hand on every frame: (in front of him, behind him). A held weapon
    has a hole where his fist wraps it, so his fingers show over the grip. `far_frames` are
    frames where this kind goes behind him even if the rig's fist is in front (a long staff
    planted beside him would otherwise cover his face)."""
    front, behind = [], []
    for n, px, fi in zip(names, frames, info):
        f, b = Image.new("RGBA", (px.shape[1], px.shape[0])), Image.new("RGBA", (px.shape[1], px.shape[0]))
        if hold[n] is not None:
            x, y, angle = hold[n]
            layer = Image.new("RGBA", f.size)
            draw_turned(layer, img, grip, (x, y), angle - axis)
            far = hands[n].get("weapon_behind", False) or n in far_frames
            if kind in GRIPPED and not far:
                arr = np.asarray(layer).copy()
                arr[fist_mask(px, (x, y), r * FIST), 3] = 0
                layer = Image.fromarray(arr, "RGBA")
            (b if far else f).alpha_composite(layer)
        elif kind in ON_BACK and n in SHEATHED:
            down = -fi["up"]
            at = fi["neck"] + down * fi["r"] * 0.3
            centre = (img.width / 2, img.height / 2)
            (f if n in BACK_VIEW else b).alpha_composite(_turned_on(f.size, img, centre, at, ON_BACK[kind] - axis))
        front.append(f)
        behind.append(b)
    return front, behind


def _turned_on(size, img, anchor, at, angle):
    layer = Image.new("RGBA", size)
    draw_turned(layer, img, anchor, at, angle)
    return layer


def held_pictures():
    """(item id, weapon kind, piece, sheet, size) for every weapon drawn on a held_*.json sheet
    that's there; size is the item's EquipDef.held_size."""
    kinds = {}
    for folder, _, files in os.walk(ITEMS):
        for f in files:
            if not f.endswith(".tres"):
                continue
            with open(os.path.join(folder, f)) as fh:
                text = fh.read()
            item, kind = re.search(r'^id = &"(\w+)"', text, re.M), re.search(r'^weapon_kind = &"(\w+)"', text, re.M)
            size = re.search(r'^held_size = ([\d.]+)', text, re.M)
            if item and kind:
                kinds[item.group(1)] = (kind.group(1), float(size.group(1)) if size else 1.0)
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
            out.append((item, kinds[item][0], piece, f[:-5], kinds[item][1]))
    return out


# ---------- writing ----------

def lift(img):
    """Brightens greyscale art so its middle grey is near white: the game tints it by
    multiplying with a colour (Sprite3D/CanvasItem modulate), which then comes out close to
    that colour, with the art's shading."""
    arr = np.asarray(img).astype(float)
    solid = arr[..., 3] > 0
    # the sheets' dark plum outline would come out of the brightening (and the tint) as a
    # magenta line, so dark pixels leaning magenta go to their own grey first
    rgb = arr[..., :3]
    plum = solid & (rgb.max(2) < OUTLINE_DARK) & (np.minimum(rgb[..., 0], rgb[..., 2]) > rgb[..., 1])
    rgb[plum] = rgb[plum].mean(1, keepdims=True)
    if solid.any():
        mid = max(np.median(arr[solid][:, :3].mean(1)), 1)
        arr[..., :3] = (arr[..., :3] * LIFT_TO / mid).clip(0, 255)
    return Image.fromarray(arr.round().astype(np.uint8), "RGBA")


def save_layer(name, frames, fw, fh, index, anims, tinted=True, grey=False):
    """Writes a layer strip and its SpriteFrames. `grey` drops all colour first, for art
    that is only ever shown tinted (hair: the sheets leave pink in the highlights)."""
    os.makedirs(LAYERS, exist_ok=True)
    os.makedirs(ANIMS, exist_ok=True)
    strip = Image.new("RGBA", (fw * len(frames), fh))
    for i, im in enumerate(frames):
        strip.alpha_composite(im, (i * fw, 0))
    if grey:
        arr = np.asarray(strip).copy()
        arr[..., :3] = arr[..., :3].mean(2, keepdims=True).round().astype(np.uint8)
        strip = Image.fromarray(arr, "RGBA")
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
    old, old_hat = {}, {}
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
                    if layer == "_hat" and not back_view:  # the sheet draws a blank face in it
                        # a pigtail beside his cheek, cut off from the hair by his face: tucked
                        # in behind the cheek
                        canvas = joined(no_low_strands(bare_face(canvas, px, fi), fi), fi,
                                        HAT_HAIR_JOIN, face_zone(px, fi))
                out[layer].append(canvas)
        old[style] = out[""]
        old_hat[style] = out["_hat"]
        for layer, fr in out.items():
            if any(im.getbbox() for im in fr):
                save_layer(f"hair_{style}{layer}", fr, fw, fh, index, anims, grey=True)

    # hairstyles drawn in every pose (hair_<style>_frames sheets) replace the front piece
    for style in HAIRSTYLES:
        manifest = os.path.join(ss.SHEETS, f"hair_{style}_frames.json")
        if os.path.exists(manifest):
            drawn = cut(f"hair_{style}_frames")
            cells = {n: without_shorts(drawn[body_cells[n]], body_cells[n]) for n in names if body_cells[n] in drawn}
            link = head_link(cells, names, info, frames)
            # every pose's hair in the held rest drawing's grey, so it doesn't flicker lighter
            # or darker from one family (or lone pose) to the next
            rest = held_hair_pose(style, HELD_HAIR["rest"][0])
            target = hair_grey(Image.fromarray(cells[rest] * hair_mask(cells[rest])[..., None])) if rest in cells else None
            out = []
            for n, fi, px in zip(names, info, frames):
                canvas = blank()
                drawn_hair = blank()
                drawn_as = held_hair_pose(style, n)
                if drawn_as not in cells:
                    drawn_as = n
                if drawn_as in cells:
                    hair_img, at = posed_hair(cells[drawn_as], fi, link)
                    if target is not None:
                        hair_img = toned(hair_img, target)
                    # a held drawing turns with his head (as far as this frame's head is turned
                    # from the held pose's)
                    turn = fi["tilt"] - info[index[drawn_as]]["tilt"]
                    place(drawn_hair, hair_img, (fi["head"][0] - at[0], fi["head"][1] - at[1]), fi["head"], turn)
                    drawn_hair = joined(pulled_in(drawn_hair, fi), fi)
                # where the drawn hair covers the scalp, the scalp only just around it (it fills
                # slivers where the heads don't quite line up, and doesn't show as a band under a
                # high hairline); where it leaves the crown bald (a ponytail drawn as the tail
                # alone), all of it, so the top of his head is hair, with the strands of the
                # style's one-piece crown on it for CROWN_FROM_HAT; in the drawn hair's own grey,
                # so it doesn't show as a darker cap
                tone = hair_grey(drawn_hair) if drawn_hair.getbbox() else 128.0
                bald = np.asarray(scalp(px, fi, n in BACK_VIEW, tone)).copy()
                near = ss.dilate(np.asarray(drawn_hair)[..., 3] > 0, 3)
                top = bald[..., 3] > 0
                covered = top.any() and (near & top).sum() > top.sum() * SCALP_COVERED
                if covered:
                    bald[~near, 3] = 0
                crown = None
                if style in CROWN_FROM_HAT and not covered and n not in BACK_VIEW:
                    crown = np.asarray(toned(old_hat[style][index[n]], tone)).copy()
                    crown[~top, 3] = 0
                if n not in BACK_VIEW:  # facing us, no scalp shows on his forehead under the fringe
                    hair_now = np.asarray(drawn_hair)[..., 3] > 0
                    if crown is not None:
                        hair_now |= crown[..., 3] > 0
                    under = above_fringe(hair_now)
                    bald[~under, 3] = 0
                    if crown is not None:
                        crown[~under, 3] = 0
                canvas.alpha_composite(Image.fromarray(bald, "RGBA"))
                if crown is not None:
                    canvas.alpha_composite(Image.fromarray(crown, "RGBA"))
                if n in BACK_VIEW or not hides_face(drawn_hair, fi):
                    canvas.alpha_composite(drawn_hair)
                    canvas = joined(canvas, fi)  # and no specks of the crown or scalp left loose
                else:  # drawn in a pose too unlike his (lying face down): the one-piece hair
                    canvas = old[style][index[n]]
                out.append(canvas)
            save_layer(f"hair_{style}", out, fw, fh, index, anims, grey=True)
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
                p = chibi(faces[face + "_" + EXPRESSIONS.get(n, "normal")], normal)
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

    # cape: lifted off the body wearing it (cape_frames), like the clothes. What the drawn body
    # hides is behind him, so the part outside his outline goes behind the body and the part
    # over it (collar and clasp, a fold over the shoulder) in front; seen from behind (climbing)
    # all of it hangs over his back
    capes = cut("cape_frames")
    behind, front = [], []
    for n, px in zip(names, frames):
        back, over = blank(), blank()
        cell = body_cells[n]
        worn = posed_worn(capes[cell], cell, px, "cape") if cell in capes else None
        if worn:
            whole = blank()
            _paste(whole, worn[0], *worn[1])
            if n in BACK_VIEW:
                over = whole
            else:
                arr = np.asarray(whole)
                inside = px[..., 3] > 127
                out_part, in_part = arr.copy(), arr.copy()
                out_part[inside, 3] = 0
                in_part[~inside, 3] = 0
                back, over = Image.fromarray(out_part, "RGBA"), Image.fromarray(in_part, "RGBA")
        behind.append(back)
        front.append(over)
    save_layer("cape", behind, fw, fh, index, anims)
    save_layer("cape_front", front, fw, fh, index, anims)
    for gone in ("cape_back_view",):  # the earlier name of cape_front
        for path in (os.path.join(LAYERS, f"{gone}.png"), os.path.join(ANIMS, f"{gone}.tres")):
            if os.path.exists(path):
                os.remove(path)

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
            p = drawn.get(poses.get(n, poses.get(body_cells[n], "")))  # a frame reusing a cell (blink) uses its pose
            if p and "shield" in entry:
                img = scaled(p.img, s_sh)
                place(canvas, img, (img.width / 2, img.height / 2), entry["shield"])
            out.append(canvas)
        save_layer(f"shield_{style}", out, fw, fh, index, anims)

    # hats: each shape's picture (from the side, or from behind in back views) put on his head,
    # as big as his head against the sheet's head and turned with it (EquipDef.look_shape picks
    # the shape). paperdoll_hats draws each hat on a bald head; paperdoll_hats_only is the same
    # sheet with the heads painted out, so its hats lift off clean and the heads place them
    hat_sheet, hats_only = cut("paperdoll_hats"), cut("paperdoll_hats_only")
    ref_at, ref_r = bald_head(hat_sheet["bald_side"])
    ref_from = ref_at - hat_head(hat_sheet["bald_side"])  # head centre from the shoulders
    for shape in HAT_SHAPES:
        views = {}
        for view in ("side", "behind"):
            p, hat = hat_sheet[f"{shape}_{view}"], hats_only[f"{shape}_{view}"]
            centre = hat_head(p) + ref_from  # this cell's head centre (cell pixels)
            views[view] = (hat_alone(hat.img), centre - (hat.x, hat.y))
        out = []
        for n, fi in zip(names, info):
            canvas = blank()
            img, at = views["behind" if n in BACK_VIEW else "side"]
            k = fi["r"] / ref_r * HAT_SIZE
            place(canvas, scaled(img, k), at * k, fi["head"], fi["tilt"])
            out.append(canvas)
        save_layer(f"hat_{shape}", out, fw, fh, index, anims)

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

    # tops, bottoms and shoes, one layer per cut (EquipDef.worn_style)
    for where, style in worn_sheets():
        drawn = cut(f"{where}_{style}_frames")
        out = []
        for n, px in zip(names, frames):
            canvas = blank()
            cell = body_cells[n]
            if cell in drawn:
                worn = posed_worn(drawn[cell], cell, px, where)
                if worn:
                    _paste(canvas, worn[0], *worn[1])
            out.append(canvas)
        save_layer(f"{where}_{style}", out, fw, fh, index, anims)

    # weapons: every kind (greyscale, tinted per item) and every weapon with its own picture
    s_w = r * SWORD_LENGTH / length(weapons["sword"], "sword")
    grips = {}
    pictures = [(kind, kind, weapons[kind], True, 1.0) for kind in WEAPON_KINDS]
    # (a bow drawn at a slant is stood up first, so it is measured and held as the rig expects)
    drawn_weapons = [(item, kind, stood_up(piece) if kind in UPRIGHT else piece, sheet, size)
                     for item, kind, piece, sheet, size in held_pictures()]
    # a held_* sheet is drawn at its own size: it is shrunk so its weapons are, on the median,
    # as long as the template of their kind (keeping their sizes against each other)
    by_sheet = {}
    # (and then grown or shrunk by the item's own held_size: a claymore longer than a sword)
    for item, kind, piece, sheet, _ in drawn_weapons:
        by_sheet.setdefault(sheet, []).append(length(weapons[kind], kind) / length(piece, kind))
    pictures += [("item_" + item, kind, piece, False, float(np.median(by_sheet[sheet])) * size)
                 for item, kind, piece, sheet, size in drawn_weapons]
    for name, kind, piece, tinted, k in pictures:
        img, grip, axis = weapon(piece, s_w * WORN_SIZE.get(kind, 1.0) * k, kind)
        entry = {"grip": grip, "size": list(img.size), "reach": reach(img, grip, axis),
                 "kind": kind, "grip_share": grip_share(img, grip, axis), "dots_left": dots_left(img)}
        grips[kind if tinted else name] = entry
        far_frames = hold_spec.get(kind, {}).get("behind", ())
        front, behind = weapon_strips(img, grip, axis, kind, names, frames, info, held[kind], hands, r, far_frames)
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
        stack += [body, tint(load("cape_front"), (0.8, 0.25, 0.25)), load("face_bright"),
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
