"""What every part of the paperdoll build shares: where things are, the sizes and names
everything is measured in (the tuning table), and the helpers that cut sheets, shrink pieces,
place them on a frame and write a layer strip."""
import copy  # noqa: F401  (re-exported for the other parts)
import json  # noqa: F401
import math
import os
import re  # noqa: F401
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps  # noqa: F401

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
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
# Hats of these shapes sit this much lower on his head than on the sheet's head (head radii;
# Cory 2026-10-11: a bandana sits a little lower).
HAT_LOWER = {"bandana": 0.2}
HAT_GROW = {"bandana": 1.1}
# ...and from behind are this wide (head radii), all alike, so they cover the back of his head
# (Gemini paints some bandanas' backs wider than others; Cory 2026-10-11: a bit smaller from behind)
HAT_BACK_WIDTH = {"bandana": 2.45}
HAT_LINE = 0.1         # a bit of a hat cell's frame line: at most this thick against its length
# a closed helm's eye holes go over his eyes (hats.eyes_in_holes): his eyes' middle (x, y) and
# width in head radii from the head centre in a side view, the share of the widest opening's
# width that counts as the eye band, the widest opening that is an open face instead (head
# radii), and how much smaller or bigger than the sheet's size the helm may be drawn
HELM_EYES = (0.18, 0.27, 0.95)
HELM_FIT = 0.8  # ...then drawn this much smaller, to suit his small body (Cory 2026-10-11)
HELM_BAND, HELM_OPEN, HELM_SIZE = 0.75, 1.15, (0.8, 1.15)
HAIR_CUT_SIDE = 0.6    # hats.save_hair_cut: hair is hidden this far past a hat's sides (head radii)
HAIR_CUT_HEAD, HAIR_CUT_REACH = 0.85, 0.5  # ...each column's own edge over his head, nearby edges off it
HAIR_CUT_CREST = 0.6  # ...on a helm, a stretch ending this far above the head's middle is a crest, not the edge
HAIR_CUT_LOW = 0.75    # ...and never below this far under the head's middle (head radii)
HEAD_CUT_DISC, HEAD_CUT_LOW = 1.3, 0.55  # hats.save_head_cut: his head this near its middle, above this low (head radii)
HEAD_CUT_HAIR = 1.6    # ...and his hair this near (its tufts stick out further)
HEAD_CUT_HAND, HEAD_CUT_KEEP = 0.6, 0.95  # ...his hands kept this near their point, outside this near the head's middle
HEAD_CUT_DARK = 0.3    # ...painted lines darker than this bound his head (an arm drawn over it is not head)
HAIR_CUT_ALPHA = 127   # ...against the hat's pixels at least this opaque
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
# A closed helm's dark inside (hats.open_visor): thicker than this many sheet pixels, and at
# least VISOR_MIN pixels after its outline lines are worn away.
VISOR_LINE = 3
VISOR_MIN = 40
SHIELD_SHOWS = 0.33   # share of a shield (its back, behind him) that shows past his body
# Clothes sheets (art/sheets/<place>_<style>_frames.json) for these places; styles whose sheet
# came back unusable are skipped (their items wear the nearest cut, see EquipDef.worn_style).
WORN_PLACES = ("top", "bottom", "shoes")
WORN_BROKEN = ("smock",)
WORN_SHORTS_GREY = 150  # the body's shorts are greys darker than this
WORN_OUTLINE = 90       # and outlines darker than this
EDGE_PEEL = 2           # pixels of a pink or mauve background rim peeled off an item's cut (items.py)
FLOOR_ZONE = 0.12       # a top or bottom has nothing off his body this low (share of his height)
FLOOR_SLACK = 0         # ... past this many pixels of his outline (items.off_floor)
TWIN_BROKEN = ("starlit_cape",)  # _only twins that came back with the body painted over, not erased
TWIN_SLACK = 1          # an item's _only twin is trusted this many pixels past its art (items.py)
WORN_FRINGE = 110       # pale edge pixels at the figure's edge are background fringe
GLOVE_REACH = 0.9     # a glove is put on a hand only if the drawn one is this near it (head radii)
# an item's own gloves are mitten pieces (gloves.glove_pieces): each hand is the skin within
# GLOVE_HAND (head radii) of its point, found within GLOVE_FIND of it; the mitten is GLOVE_SIZE
# wide and covers GLOVE_OVER pixels of his body around that hand
GLOVE_HAND = 0.38
GLOVE_FIND = 0.7
GLOVE_SIZE = 0.6
GLOVE_OVER = 4
SWORD_LENGTH = 1.9    # every weapon is drawn at the scale that makes the sword this long
WEAPON_LENGTH = 20    # rig "tip" is this far from "grip" along the weapon (only its direction matters)
FIST = 0.4            # the fist around a grip reaches this far from the grip point (head radii)
FOREARM = 1.1         # forearm_angles: skin this close to the fist (head radii) counts as his forearm
GUN_FRONT, GUN_BACK = 0.4, 0.4  # weapons.grip_point: a gun's barrel is its front share, its grip in its back share
BARREL_FRONT = 0.55   # weapons.barrel_tilt: the front share of a gun that is its barrel
CLAW_CUFF = 0.25      # how far along a claw (0 its back end, 1 its tips) the middle of its cuff is

# Weapons worn on the fist are drawn smaller than the template sheet has them, so they fit
# his hand rather than swallowing it (the rest keep the sheet's size against the sword).
WORN_SIZE = {"claw": 0.9, "knuckle": 0.75, "bow": 1.35, "staff": 1.3}
# Long weapons whose sheets may draw them at a slant (a sword up and to the right): their own
# axis is measured and turned out, so a rig angle means the same however the art was drawn.
# The others are drawn the way the rig expects (a gun pointing right, a bow upright).
AXIAL = ("sword", "wand", "staff", "claw")
# Weapons the rig holds upright (see stood_up), and how far off upright (degrees) one may be
# drawn before it is stood up.
UPRIGHT = ("bow",)
UPRIGHT_SLACK = 8
# Weapons held in the fist: his fingers draw over the grip. The others are worn on the fist.
GRIPPED = ("sword", "wand", "staff", "bow", "gun")
# Weapons carried on his back while he climbs or sits, and at what angle; the rest are put away.
ON_BACK = {"sword": 125, "staff": -70, "bow": 60, "wand": 125, "gun": 110}
SHEATHED = BACK_VIEW + ("sit",)
# Weapons are held as their own icon (Cory 2026-10-11: gear looks the same worn as in the
# bag): the weapon cells of these item icon sheets, cut at the sheet's full size.
ICON_SHEETS = "items_"
ITEMS = os.path.join(ROOT, "data", "items")

# Where the weapon hand and shield are, and how the head is tilted, per frame: placed by hand,
# since the hands are hard to tell apart from the rest of the body.
HAND_RIG = os.path.join(ss.SHEETS, "paperdoll_rig.json")


# ---------- shapes ----------

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


class Drawn:
    """A piece made here rather than cut from a sheet (same fields as Piece)."""
    def __init__(self, img, x, y):
        self.img, self.x, self.y = img, x, y


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
