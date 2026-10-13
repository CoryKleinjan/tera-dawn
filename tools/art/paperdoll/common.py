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
# The hero body's outline colour (its edge pixels, measured on hero.png). Gear sheets come back
# with a lighter plum outline and a pink cast on their soft edge pixels; match_outline() turns
# both to this, so gear and body read as one drawing.
HERO_OUTLINE = (29, 2, 10)
OUTLINE_BAND = 2      # match_outline(): pixels this close to the clear background are outline
OUTLINE_LIGHT = 120   # of these, ones darker than this (mean of r, g, b)

# Frames seen from behind: no face, the hair's "from behind" piece, the cape in front.
BACK_VIEW = ("rope1", "rope2", "ladder1", "ladder2", "climb_idle")
# The face's expression per frame (anything not listed: normal).
EXPRESSIONS = {"blink": "blink", "hit": "ouch", "hurt": "ouch", "faint1": "dizzy", "faint2": "dizzy"}
HAIRSTYLES = ["tousled", "long", "ponytail", "twin_tails", "bun", "crest"]
FACES = ["bright", "determined", "rosy", "freckled", "cheeky"]
WEAPON_KINDS = ["sword", "bow", "wand", "staff", "star", "knuckle", "gun"]

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
HAT_GROW = {"bandana": 1.02}  # (Cory 2026-10-12: bandanas a bit smaller, to fit better)
# ...and from behind are this wide (head radii), all alike, so they cover the back of his head
# (Gemini paints some bandanas' backs wider than others; Cory 2026-10-11: a bit smaller from behind)
HAT_BACK_WIDTH = {"bandana": 2.3}
HAT_LINE = 0.1         # a bit of a hat cell's frame line: at most this thick against its length
HAT_FRAME_FILL, HAT_FRAME_THICK = 0.85, 6  # hats.hat_alone: edge rows this full, at most this many, are a cell frame line
# a closed helm's eye holes go over his eyes (hats.eyes_in_holes): his eyes' middle (x, y) and
# width in head radii from the head centre in a side view, the share of the widest opening's
# width that counts as the eye band, the widest opening that is an open face instead (head
# radii), and how much smaller or bigger than the sheet's size the helm may be drawn
HELM_EYES = (0.18, 0.27, 0.95)
FACE_LINE_DARK, FACE_LINE_LEAN = 140, 30  # faces: line work darker than this leans at most this far to magenta
SHORTS_BELOW = 0.45  # body.shorts_mask: the shorts are only looked for this far down the body (its height)
SOLID_EYES = 60  # hats.eyes_out: the face layer's irises, where at least this opaque
HELM_HUG, HELM_NUDGE = 1.06, 0.5  # hats.hugging: a helm's shell this times his head's width; moved this far to its eyes
HELM_BAND, HELM_OPEN, HELM_SIZE = 0.75, 1.15, (0.8, 1.15)
HAIR_CUT_HEAD, HAIR_CUT_REACH = 0.85, 0.5  # hats.save_hair_cut: each column's own edge over his head, nearby edges off it
HAIR_CUT_CREST = 0.6  # ...on a helm, a stretch ending this far above the head's middle is a crest, not the edge
HAIR_CUT_SPECK, HAIR_CUT_CRUMB = 0.15, 0.03  # ...and a patch smaller than this (head radii squared) off by itself, or this anywhere
HAIR_CUT_TOUCH, HAIR_CUT_HELD = 4, 0.7  # ...a patch the cut chopped less than this share of it at the hat (within that) is loose
HAIR_CUT_BODY = 2     # ...or one the cut reached not touching his head within this (frame pixels)
HAIR_HEAD_ONLY = ("long", "ponytail", "twin_tails")  # ...hairstyles showing only the hair on his head under a hat (no tails or hanging locks)
HAIR_HEAD_ONLY_OVAL = (1.1, 0.9, 0.55)  # ...inside this oval (half width, half height, raised: head radii), above his mouth
HAIR_HEAD_ONLY_BACK = (1.15, 1.05, 0.0)  # ...or from behind, this one (his whole head, down to his neck)
HAIR_FACE_FRONT = 0.0  # under a hat no hair sticks out past the front of his face: none off his head forward of this (head radii from its middle)
HAIR_HAT_POSE = "sit"  # ...and every pose wears this pose's hair under a hat (for those styles)
HAIR_CUT_SOFT = 1.5   # ...its edge blurred this much (frame pixels), so the hair fades out under the hat
HAIR_CUT_TUCK = 2      # ...and stops this many pixels inside the hat, so hair and head run on under its soft edge
HAIR_CUT_LOW = 0.75    # ...and never below this far under the head's middle (head radii)
HEAD_CUT_DISC, HEAD_CUT_LOW = 1.3, 0.55  # hats.save_head_cut: his head this near its middle, above this low (head radii)
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
STAR_GRIP = 0.4       # how far across a throwing star (0 its back, 1 its front) his fist holds it, so its front sticks out
STAR_ACROSS = 0.85    # a throwing star is this wide in his hand (head radii), so his fist hides its middle and back
STAFF_GRIP = 0.35     # how far up a staff (0 its foot, 1 its head) his fist holds it: low on the handle

# Weapons worn on the fist are drawn smaller than the template sheet has them, so they fit
# his hand rather than swallowing it (the rest keep the sheet's size against the sword).
WORN_SIZE = {"knuckle": 0.75, "bow": 1.35, "staff": 1.3}
# Long weapons whose sheets may draw them at a slant (a sword up and to the right): their own
# axis is measured and turned out, so a rig angle means the same however the art was drawn.
# The others are drawn the way the rig expects (a gun pointing right, a bow upright).
AXIAL = ("sword", "wand", "staff")
# Weapons the rig holds upright (see stood_up), and how far off upright (degrees) one may be
# drawn before it is stood up.
UPRIGHT = ("bow",)
UPRIGHT_SLACK = 8
# Weapons held in the fist: his fingers draw over the grip. The others are worn on the fist.
GRIPPED = ("sword", "wand", "staff", "bow", "gun", "star")
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

def feathered(arr, mask):
    """The pixels of an RGBA array inside `mask`, with the edge the mask cuts through the art
    faded over a pixel (each pixel's alpha times the share of its 3x3 neighbours that are kept
    or clear), so a piece lifted off a sheet has a soft edge there too, never on/off pixels.
    Its own edge against the background stays as it is."""
    keep = (mask | (arr[..., 3] == 0)).astype(float)
    pad = np.pad(keep, 1, mode="edge")
    share = sum(pad[dy:dy + keep.shape[0], dx:dx + keep.shape[1]] for dy in range(3) for dx in range(3)) / 9.0
    out = arr.copy()
    out[~mask] = 0
    out[..., 3] = (out[..., 3] * share).round().astype(np.uint8)
    return out


def scaled(piece_img, s):
    """A piece (PIL RGBA, sheet pixels) shrunk to game pixels."""
    arr = np.asarray(piece_img).astype(float) / 255
    rgb, alpha = ss.shrink(arr[..., :3], arr[..., 3], s)
    out = np.zeros(alpha.shape + (4,), np.uint8)
    out[..., :3] = (rgb * 255).round()
    out[..., 3] = (alpha * 255).round()  # (the soft, anti-aliased edge stays: never on/off pixels)
    out[out[..., 3] < 4] = 0  # (but not the dust of nearly clear pixels round it)
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


def match_outline(img, outside=None):
    """Gives full-colour gear the hero's outline: the dark pixels along its edge take
    HERO_OUTLINE's colour, keeping their own shading, and pink-tinted soft edge pixels the
    sheet's magenta left are coloured as outline too. Only recolours, so the outline stays as
    thick as drawn. `outside`: where the picture's clear background is (default: wherever it
    is see-through), e.g. leaving out where a worn piece only stops at his body."""
    arr = np.asarray(img).astype(float)
    alpha, rgb = arr[..., 3], arr[..., :3]
    clear = alpha < 40 if outside is None else outside
    band = (alpha >= 15) & ss.dilate(clear, OUTLINE_BAND, outside=True)
    light = rgb.mean(2)
    dark = band & (light < OUTLINE_LIGHT)
    if dark.sum() < 10:
        return img
    solid = dark & (alpha > 230)
    ref = max(float(np.median(light[solid if solid.any() else dark])), 1.0)
    # fully outline at the outline's own darkness, fading out by 1.7x as light
    weight = np.clip((1.7 * ref - light) / (0.7 * ref), 0, 1) * band
    pink = (rgb[..., 0] - rgb[..., 1] > 30) & (rgb[..., 2] - rgb[..., 1] > 20)
    weight[band & (alpha < 230) & pink] = 1
    shade = np.clip(light / ref, 0.5, 1.6)[..., None]
    arr[..., :3] = rgb * (1 - weight[..., None]) + np.array(HERO_OUTLINE, float) * shade * weight[..., None]
    return Image.fromarray(arr.round().clip(0, 255).astype(np.uint8), "RGBA")


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
