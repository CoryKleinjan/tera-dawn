"""Get the platform pieces cut by slice_sheets.py ready for the game.

slice_sheets.py runs this right after it cuts a platform_pieces_<biome> sheet (it works on
the fresh cut, so run the slicer, not this):

    python3 tools/art/slice_sheets.py platform_pieces_meadow

The platform_pieces_<biome> sheets (art prompts part 7) draw one long ledge cut into a left
cap, two middles and a right cap. slice_sheets.py cuts them into
assets/sprites/platforms/<biome>/; this script then, for the four top pieces:

1. Lines them up the way they sat in the sheet (one ledge painted across the cells) and gives
   them one shared height, so the game can set them side by side without any vertical
   offsets. The walking surface is the middles' first half-solid row.
2. Makes them thin enough for the maps: Gemini drew the ledges two to three heroes thick,
   but platforms sit about 100 game pixels apart. It keeps the top band (surface and the
   start of the rock) and the bottom band (the rounded underside with its outline) and
   drops the rows between, joining the two along the row-by-row path where they differ
   least, so the art keeps its pixel size and outline.

The under_* pieces go to art/build/ (not the game). A terrace_pieces_<biome> sheet holds the
square ends of a raised terrace's top edge (terrace_left, terrace_right) and the corner-stone
columns down its wall; prepare_terrace() gives the two ends the same height and walking
surface row as that biome's prepared platform pieces, so they join its middles. The game joins pieces the same way across their left and right edges (PlatformSkin).
Options live in the sheet's manifest under "platform":
    "max_depth": texels the pieces may reach below the walking surface (default 80: 50 game
                 pixels; grass and crystals rising above the surface don't count)
    "bottom": "self" (default) or "under": take the underside from the under_* pieces,
              for sheets whose top pieces stop at a cut line (driftcove)
    "top_share": how much of the kept depth is the top band (default 0.55)
    "shift": {piece: texels}: moves a piece down (up if negative) from where the sheet has it,
             for sheets whose caps were painted as pictures of their own (lanternfall)
    "loop_middles": columns at the right end of middle_b faded into the start of middle_a, for
                 sheets whose painted middles don't run on from b back into a (the game
                 repeats a, b, a, b...)
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


def fade_into(a, b, cols):
    """`a` with its last `cols` columns faded (premultiplied) into `b`'s first `cols`, so
    `a` ends the way `b` starts."""
    h = min(a.shape[0], b.shape[0])
    out = a.copy()
    t = np.linspace(0.0, 1.0, cols)[None, :, None]
    pa = premultiplied(a[:h, -cols:])
    pb = premultiplied(b[:h, :cols])
    mix = pa * (1 - t) + pb * t
    alpha = mix[..., 3:]
    rgb = np.where(alpha > 0, mix[..., :3] / np.maximum(alpha, 1e-6), 0)
    out[:h, -cols:] = np.round(np.concatenate([rgb, alpha], -1) * 255).astype(a.dtype)
    return out


def offsets(tops, sheet_y, shift):
    """How far down each top piece starts: where the sheet had it (its cells hold one painted
    ledge, so a piece's rows meet its neighbours' there), plus any manifest shift. A rounded
    cap's own first half-solid row lands lower than the middles', so lining pieces up by
    that put the caps out of step with the middles."""
    if sheet_y and all(n in sheet_y for n in TOPS):
        rows = [round(sheet_y[n]) + shift.get(n, 0) for n in TOPS]
    else:  # cut without the slicer's sheet positions: line the surfaces up
        surface = max(surface_row(a) for a in tops)
        rows = [surface - surface_row(a) + shift.get(n, 0) for n, a in zip(TOPS, tops)]
    return [r - min(rows) for r in rows]


def prepare(name, sheet_y=None):
    """`sheet_y`: each top piece's top row in the sheet, in cut pixels (slice_sheets.py)."""
    with open(os.path.join(SHEETS, "platform_pieces_%s.json" % name)) as f:
        man = json.load(f)
    opts = man.get("platform", {})
    out_dir = os.path.join(ROOT, man["out_dir"])
    build = os.path.join(ROOT, "art", "build", "platform_pieces_" + name)  # the under pieces stay out of the game
    load = lambda d, n: np.asarray(Image.open(os.path.join(d, n + ".png")).convert("RGBA"))
    tops = [load(out_dir, n) for n in TOPS]
    max_depth = opts.get("max_depth", MAX_DEPTH)
    rows = offsets(tops, sheet_y, opts.get("shift", {}))
    if opts.get("bottom") == "under":
        unders = [load(build, n) for n in UNDERS]
        # the under pieces hang straight below the top pieces' lowest opaque row
        stacked = []
        for t, u, r in zip(tops, unders, rows):
            t = pad(t, r, r + t.shape[0])
            u = pad(u, 0, u.shape[0], t.shape[1])
            stacked.append(np.concatenate([t, u]))
        tops, rows = stacked, [0] * len(stacked)
    height = max(r + a.shape[0] for r, a in zip(rows, tops))
    pieces = [pad(a, r, height) for r, a in zip(rows, tops)]
    surface = surface_row(pieces[1])
    if height - surface > max_depth:
        share = opts.get("top_share", TOP_SHARE)
        pieces = [join_bands(p, p, surface + max_depth, surface, share) for p in pieces]
    if opts.get("loop_middles"):
        pieces[2] = fade_into(pieces[2], pieces[1], opts["loop_middles"])
    for n, p in zip(TOPS, pieces):
        Image.fromarray(p, "RGBA").save(os.path.join(out_dir, n + ".png"))
    print("%s: %d top pieces, %d texels tall (was %d), surface at row %d"
          % (name, len(pieces), pieces[0].shape[0], height, surface))



TERRACE_ENDS = ["terrace_left", "terrace_right"]


def best_row(a, ref, cols, rows, reach=16):
    """The row `a` starts at where its columns `cols` best match `ref`'s first `rows` rows
    (the same picture painted again, so its stones meet the platform's)."""
    want = premultiplied(ref[:rows, cols])
    best, cost = 0, np.inf
    for r in range(-reach, reach + 1):
        moved = pad(a, max(0, r), max(0, r) + a.shape[0])[max(0, -r):][:rows]
        if moved.shape[0] < rows:
            moved = np.concatenate([moved, np.zeros((rows - moved.shape[0],) + moved.shape[1:], moved.dtype)])
        c = ((premultiplied(moved[:, cols]) - want) ** 2).mean()
        if c < cost:
            best, cost = r, c
    return best


def prepare_terrace(name):
    """The square terrace ends of biome `name`, lined up and thinned to match its prepared
    platform pieces (run the platform_pieces sheet first): each end is the cap on its side
    painted with a square end, so it goes at the height where its inner part matches that
    cap's."""
    with open(os.path.join(SHEETS, "terrace_pieces_%s.json" % name)) as f:
        out_dir = os.path.join(ROOT, json.load(f)["out_dir"])
    load = lambda n: np.asarray(Image.open(os.path.join(out_dir, n + ".png")).convert("RGBA"))
    middle = load("middle_a")
    surface, height = surface_row(middle), middle.shape[0]
    for n, cap in zip(TERRACE_ENDS, ["cap_left", "cap_right"]):
        a, ref = load(n), load(cap)
        w = min(a.shape[1], ref.shape[1]) // 2  # the inner half, away from the ends that differ
        cols = slice(a.shape[1] - w, a.shape[1]) if n == "terrace_left" else slice(0, w)
        if ref.shape[1] != a.shape[1]:  # compare the same inner columns of both
            ref = pad(ref, 0, ref.shape[0], a.shape[1]) if ref.shape[1] < a.shape[1] else \
                (ref[:, ref.shape[1] - a.shape[1]:] if n == "terrace_left" else ref[:, :a.shape[1]])
        top = best_row(a, ref, cols, min(height, surface + 40))
        if top < 0:  # grass rising higher than the middles': let it go
            a, top = a[-top:], 0
        p = pad(a, top, max(height, top + a.shape[0]))
        if p.shape[0] > height:
            p = join_bands(p, p, height, surface)
        Image.fromarray(p, "RGBA").save(os.path.join(out_dir, n + ".png"))
    print("%s: terrace ends %d texels tall, surface at row %d" % (name, height, surface))
