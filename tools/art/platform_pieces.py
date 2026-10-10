"""Get the platform pieces cut by slice_sheets.py ready for the game.

slice_sheets.py runs this right after it cuts a platform_pieces_<biome> sheet (it works on
the fresh cut, so run the slicer, not this):

    python3 tools/art/slice_sheets.py platform_pieces_meadow

The platform_pieces_<biome> sheets (art prompts part 7) draw one long ledge cut into a left
cap, two middles and a right cap. slice_sheets.py cuts them into
assets/sprites/platforms/<biome>/; this script then, for the four top pieces:

1. Lines their walking surfaces up and gives them one shared height, so the game can set
   them side by side without any vertical offsets.
2. Makes them thin enough for the maps: Gemini drew the ledges two to three heroes thick,
   but platforms sit about 100 game pixels apart. It keeps the top band (surface and the
   start of the rock) and the bottom band (the rounded underside with its outline) and
   drops the rows between, joining the two along the row-by-row path where they differ
   least, so the art keeps its pixel size and outline.

The under_* pieces go to art/build/ (not the game). The game joins pieces the same way across their left and right edges (PlatformSkin).
Options live in the sheet's manifest under "platform":
    "max_depth": texels the pieces may reach below the walking surface (default 80: 50 game
                 pixels; grass and crystals rising above the surface don't count)
    "bottom": "self" (default) or "under": take the underside from the under_* pieces,
              for sheets whose top pieces stop at a cut line (driftcove)
    "top_share": how much of the kept depth is the top band (default 0.55)
"""
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SHEETS = os.path.join(ROOT, "art", "sheets")
TOPS = ["cap_left", "middle_a", "middle_b", "cap_right"]
UNDERS = ["under_left", "under_middle_a", "under_middle_b", "under_right"]
MAX_DEPTH = 80
TOP_SHARE = 0.55  # of the thinned depth below the surface, how much is the top band
OVERLAP = 10      # rows the top and bottom bands overlap, where the join path runs


def surface_row(a):
    """The first row that is at least half opaque: the walking surface (grass tips above it
    don't count)."""
    solid = (a[..., 3] > 127).mean(1)
    rows = np.nonzero(solid >= 0.5)[0]
    return int(rows[0]) if len(rows) else 0


def pad(a, top, height, width=None):
    """`a` moved down `top` rows on a transparent canvas `height` tall (and `width` wide,
    centred)."""
    h, w = a.shape[:2]
    width = width or w
    out = np.zeros((height, width, 4), a.dtype)
    x0 = (width - w) // 2
    sx0, dx0 = max(0, -x0), max(0, x0)
    n = min(w - sx0, width - dx0)
    rows = min(h, height - top)
    out[top:top + rows, dx0:dx0 + n] = a[:rows, sx0:sx0 + n]
    return out


def seam_path(cost):
    """The cheapest left-to-right path through `cost` (rows x cols), moving at most one row
    per column. Returns its row in every column."""
    rows, cols = cost.shape
    acc = cost.astype(float).copy()
    back = np.zeros((rows, cols), int)
    for x in range(1, cols):
        prev = acc[:, x - 1]
        up = np.r_[np.inf, prev[:-1]]
        down = np.r_[prev[1:], np.inf]
        choice = np.stack([up, prev, down])
        k = choice.argmin(0)
        acc[:, x] += choice[k, np.arange(rows)]
        back[:, x] = np.arange(rows) + k - 1
    path = np.zeros(cols, int)
    path[-1] = int(acc[:, -1].argmin())
    for x in range(cols - 1, 0, -1):
        path[x - 1] = back[path[x], x]
    return path


def premultiplied(a):
    f = a.astype(float) / 255.0
    return np.concatenate([f[..., :3] * f[..., 3:], f[..., 3:]], -1)


def join_bands(top, bottom, height, surface=0, top_share=TOP_SHARE):
    """`height` rows: the start of `top` and the end of `bottom`, joined in their overlap
    along the path where they differ least (in the top band's share of the rows below
    `surface`)."""
    keep_top = surface + round((height - surface) * top_share)
    o = OVERLAP // 2
    j0, j1 = keep_top - o, keep_top + o
    b_off = bottom.shape[0] - height  # bottom row j of the result is bottom row j + b_off
    out = np.zeros((height,) + top.shape[1:], top.dtype)
    out[:j0] = top[:j0]
    out[j1:] = bottom[j1 + b_off:]
    t = premultiplied(top[j0:j1])
    b = premultiplied(bottom[j0 + b_off:j1 + b_off])
    path = seam_path(((t - b) ** 2).sum(-1))
    for x, c in enumerate(path):
        out[j0:j0 + c, x] = top[j0:j0 + c, x]
        out[j0 + c:j1, x] = bottom[j0 + c + b_off:j1 + b_off, x]
    return out


def prepare(name):
    with open(os.path.join(SHEETS, "platform_pieces_%s.json" % name)) as f:
        man = json.load(f)
    opts = man.get("platform", {})
    out_dir = os.path.join(ROOT, man["out_dir"])
    build = os.path.join(ROOT, "art", "build", "platform_pieces_" + name)  # the under pieces stay out of the game
    load = lambda d, n: np.asarray(Image.open(os.path.join(d, n + ".png")).convert("RGBA"))
    tops = [load(out_dir, n) for n in TOPS]
    max_depth = opts.get("max_depth", MAX_DEPTH)
    surface = max(surface_row(a) for a in tops)
    if opts.get("bottom") == "under":
        unders = [load(build, n) for n in UNDERS]
        # the under pieces hang straight below the top pieces' lowest opaque row
        stacked = []
        for t, u in zip(tops, unders):
            t = pad(t, surface - surface_row(t), surface - surface_row(t) + t.shape[0])
            u = pad(u, 0, u.shape[0], t.shape[1])
            stacked.append(np.concatenate([t, u]))
        tops = stacked
        surface = max(surface_row(a) for a in tops)
    height = max(surface - surface_row(a) + a.shape[0] for a in tops)
    pieces = [pad(a, surface - surface_row(a), height) for a in tops]
    if height - surface > max_depth:
        share = opts.get("top_share", TOP_SHARE)
        pieces = [join_bands(p, p, surface + max_depth, surface, share) for p in pieces]
    for n, p in zip(TOPS, pieces):
        Image.fromarray(p, "RGBA").save(os.path.join(out_dir, n + ".png"))
    print("%s: %d top pieces, %d texels tall (was %d), surface at row %d"
          % (name, len(pieces), pieces[0].shape[0], height, surface))

