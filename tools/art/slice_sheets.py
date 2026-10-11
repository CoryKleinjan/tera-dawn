#!/usr/bin/env python3
"""Cut sprites out of the generated art sheets in art/source/.

Every sheet has a manifest in art/sheets/<name>.json that says where its cells
are, what each cell is called, how much to shrink it and where the result goes.
Adding a new sheet means dropping the PNG in art/source/ and writing a manifest;
no code changes. See art/sheets/README.md for the manifest format.

    python3 tools/art/slice_sheets.py            # every manifest
    python3 tools/art/slice_sheets.py dewling ui # only these
    python3 tools/art/slice_sheets.py --grid ui  # print the detected grid, write nothing

Steps for each cell:
1. Find the cells: thin divider lines are detected automatically (or given in the manifest).
2. Remove the background: magenta sheets get a soft chroma key with the magenta
   unmixed from the edge colours, then a defringe pass for the dark outline pixels the key
   kept that are still part magenta; dark sheets are flood-filled from the cell border.
3. Drop the white label in the cell's top-left corner and any specks.
4. Shrink to the game's scale (premultiplied box filter) at twice the detail the game sizes
   it in, keep the smooth anti-aliased edge, and trim to the visible pixels.

Animation sets (the "sets" block of a manifest) lay frames out on one strip with
the feet on a shared baseline and write a Godot SpriteFrames resource next to it.
An animation lists its "frames", "fps", "loop" and optionally "durations": how long each
frame shows, counted in frames at that fps (so 2 holds a wind-up twice as long).
"""
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import climb_pieces  # noqa: E402
import platform_pieces  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SHEETS = os.path.join(ROOT, "art", "sheets")

DEFAULTS = {
    "background": "magenta",  # "magenta", "dark" or [r, g, b]
    "scale": 0.25,            # sheet pixels to art pixels (the unit the game sizes art in)
    "detail": 2,              # texels cut per art pixel (TDStage.ART_DENSITY must match for the folder)
    "alpha": "smooth",        # "smooth" keeps the anti-aliased edge; "soft" also keeps glow around it; "hard" is on/off
    "label_band": 0.16,       # top part of each cell (fraction of its height) that can hold the label
    "min_area": 6,            # specks smaller than this (in output pixels) are dropped
    "keep": "all",            # "all", "largest" or "split" (one sprite per piece, name_1, name_2...)
    "shadow": False,          # dark sheets: remove the soft drop shadow under the sprite
    "inset": 3,               # pixels trimmed off each cell edge (divider anti-aliasing)
    "save": True,             # False: only used by animation sets, not written on its own
    "key": [0.35, 0.8],       # magenta sheets: magenta-ness at which pixels start / stop being background
    "light": False,           # magenta sheets: the art is light with no outline, keyed out exactly (key_light); [r, g, b] also sets its colour
    "trim": True,             # False keeps the whole cell (or crop), so separate animation frames line up
    "defringe": True,         # magenta sheets: take the magenta out of the outline pixels at the cut edge
    "dark_key": True,         # magenta sheets: dark magenta is background (floor shadows); False keeps plum line art
    "strip_labels": False,    # paint over white label letters in the label band before cutting
    "fix": None,              # a clean-up from FIXES for every cell (e.g. "glow_backdrop" for icon sheets)
    "recolor": None,          # a palette change from RECOLORS for every cell (e.g. "leather")
    "art_px": None,           # sheet pixels per art pixel (Gemini draws each sheet at its own pixel size); sets scale
    "density": 2,             # with art_px: sprite texels per art pixel
    "grow": 1.0,              # with art_px: draw this piece a little bigger or smaller (0.8 to 1.25)
    "flat_bottom": False,     # stands on the ground: True squares off a rounded bottom (flat_bottom_rows), a number cuts that many rows
}


# ---------- small image helpers ----------

N4 = [(-1, 0), (1, 0), (0, -1), (0, 1)]
N8 = N4 + [(-1, -1), (-1, 1), (1, -1), (1, 1)]


def label(mask):
    """Connected components (8-neighbour). Returns (labels, count)."""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    for y, x in zip(*np.nonzero(mask)):
        if lab[y, x]:
            continue
        n += 1
        lab[y, x] = n
        q = deque([(y, x)])
        while q:
            cy, cx = q.popleft()
            for dy, dx in N8:
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = n
                    q.append((ny, nx))
    return lab, n


def flood(mask, seeds):
    """Pixels of `mask` 4-connected to any seed."""
    h, w = mask.shape
    out = np.zeros_like(mask)
    q = deque()
    for s in seeds:
        if mask[s] and not out[s]:
            out[s] = True
            q.append(s)
    while q:
        y, x = q.popleft()
        for dy, dx in N4:
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not out[ny, nx]:
                out[ny, nx] = True
                q.append((ny, nx))
    return out


def dilate(m, r, outside=False):
    """Grows a mask by r pixels (a square), without wrapping round the edges. `outside`: whether
    the area past the edges counts as in the mask (True for "near the clear background", since a
    cell's art can run to its edge)."""
    h, w = m.shape
    pad = np.pad(m, r, constant_values=outside)
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= pad[r + dy:r + dy + h, r + dx:r + dx + w]
    return out


def background_color(rgb):
    """The sheet's most common colour."""
    q = (rgb[::3, ::3] // 4).reshape(-1, 3)
    vals, counts = np.unique(q, axis=0, return_counts=True)
    return vals[counts.argmax()] * 4 + 2


# ---------- grid detection ----------

def _runs(idx):
    runs = []
    for i in idx:
        if runs and i - runs[-1][1] <= 1:
            runs[-1][1] = i
        else:
            runs.append([i, i])
    return runs


def _divider_lines(rgb, bg, axis, threshold):
    """Indices along `axis` (0 rows, 1 columns) that are thin, uniform lines unlike the background."""
    lines = rgb if axis == 0 else rgb.transpose(1, 0, 2)
    out = []
    for i, line in enumerate(lines):
        med = np.median(line, 0)
        if np.abs(med - bg).sum() < 40:
            continue
        near = np.abs(line - med).sum(1) < 45
        if near.mean() > threshold:
            out.append(i)
    # dividers are thin: drop long runs (those are opaque art, e.g. a texture or strip)
    keep = []
    for a, b in _runs(out):
        if b - a <= 5:
            keep.append((a + b) // 2)
    return keep


def detect_grid(rgb, bg, threshold=0.8):
    """Returns a list of bands: (y0, y1, [(x0, x1), ...])."""
    h, w, _ = rgb.shape
    ys = [0] + _divider_lines(rgb, bg, 0, threshold) + [h]
    bands = []
    for y0, y1 in zip(ys, ys[1:]):
        if y1 - y0 < 24:
            continue
        xs = [0] + _divider_lines(rgb[y0 + 4:y1 - 4], bg, 1, threshold) + [w]
        cols = [(x0, x1) for x0, x1 in zip(xs, xs[1:]) if x1 - x0 >= 24]
        bands.append((y0, y1, cols))
    return bands


def grid_from_manifest(spec, shape):
    """An explicit grid: {"rows": [y0, y1, ...], "cols": [x0, ...] or [[x0, ...], ...] per row}."""
    h, w = shape[:2]
    ys = spec["rows"]
    bands = []
    for i, (y0, y1) in enumerate(zip(ys, ys[1:])):
        cols = spec["cols"][i] if isinstance(spec["cols"][0], list) else spec["cols"]
        bands.append((y0, y1, list(zip(cols, cols[1:]))))
    return bands


# ---------- cutting one cell ----------

def key_magenta(cell, bg, lo=0.35, hi=0.8, dark_key=True):
    """Soft alpha from how magenta each pixel is, with the magenta unmixed from edge colours.
    Pixels at or below `lo` magenta-ness are opaque, at or above `hi` fully background.
    `dark_key` False: dark magenta (plum line art, on a sheet with no floor shadows) is art."""
    c = cell / 255.0
    peak = np.maximum(c.max(2), 1e-3)
    spread = np.minimum(c[..., 0], c[..., 2]) - c[..., 1]
    k = spread.copy()
    # the floor shadows are darker magenta with no green at all: judge those relative to their
    # brightness. Near-black outlines pick up a magenta tint too, so fade that back out.
    pure = (c[..., 1] / peak < 0.12) & dark_key
    k[pure] = np.maximum(k[pure], (spread / peak * np.clip(peak / 0.3, 0.0, 1.0))[pure])
    alpha = np.clip((hi - k) / (hi - lo), 0.0, 1.0)
    alpha[np.abs(c[..., 0] - c[..., 2]) > 0.35] = 1.0  # strongly red or blue: never background
    a = np.maximum(alpha, 1e-3)[..., None]
    rgb = np.clip((c - (1.0 - alpha[..., None]) * (bg / 255.0)) / a, 0, 1)
    # despill: see-through edge pixels keep a magenta cast the unmixing can't remove
    spill = np.clip(np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1], 0, None) * (alpha < 0.98)
    rgb[..., 0] -= spill * 0.85
    rgb[..., 2] -= spill * 0.85
    return np.clip(rgb, 0, 1), alpha


def key_light(cell, bg, floor=0.04, hue=None):
    """Light painted on magenta (a glow, a beam): every pixel is read as the light laid over
    pure magenta at some opacity, and the magenta is taken out exactly (colour to alpha), so
    soft halos fade out with no pink fringe. Only for art with no outline. `floor`: opacity
    below this is the background's own noise. `hue` [r, g, b]: the light's own colour."""
    c = cell / 255.0
    # magenta can only be lightened by green and darkened in red and blue: how far each pixel
    # moved from it is its light's opacity
    alpha = np.max(np.stack([1.0 - c[..., 0], c[..., 1], 1.0 - c[..., 2]]), axis=0)
    alpha = np.clip((alpha - floor) / (1.0 - floor), 0.0, 1.0)
    m = np.array([1.0, 0.0, 1.0])
    a = np.maximum(alpha, 1e-3)[..., None]
    rgb = np.clip((c - (1.0 - a) * m) / a, 0, 1)
    if hue is not None:
        # light seen over magenta reads bluer than it is: what is left is greener (teal for a
        # blue glow). Give every tinted pixel the hue meant, keeping its whiteness and strength.
        h = np.asarray(hue, float) / 255.0
        lo = rgb.min(2, keepdims=True)
        chroma = (rgb - lo).max(2, keepdims=True)
        rgb = np.clip(lo + chroma * (h - h.min()) / max(np.ptp(h), 1e-3), 0, 1)
    return rgb, alpha


def _shifted(x, dy, dx):
    """`x` moved by (dy, dx), with zeros (not wrap-around) coming in at the edges."""
    out = np.zeros_like(x)
    h, w = x.shape[:2]
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = \
        x[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


def defringe(rgb, alpha, bg, band=3, lean=0.04, fit=0.22):
    """Takes the background out of the rim of solid pixels the key left around the art.
    Gemini blends the dark outline into the magenta, and a dark blend (plum, about RGB
    96, 16, 80) isn't magenta enough for the key, so it stays solid and shows as a thin
    magenta line in the game. Each solid pixel within `band` pixels of the cut edge (or of
    the cell edge, for art cut off by it) that leans magenta is compared with the clean art just inside it: when it is a mix of that
    art and the background, it gets the art's colour and loses the background's share of
    its alpha (so mostly-background pixels drop out). Real purple or pink art matches the
    art beside it, so it stays as drawn. Clearly magenta slivers with no art near them go."""
    bg = np.asarray(bg, float) / 255.0
    solid = alpha > 0.5
    near_cut = ~solid
    near_cut[[0, -1], :] = near_cut[:, [0, -1]] = True  # art cut off by the cell edge or a crop
    for _ in range(band):
        near_cut = near_cut | _shifted(near_cut, 1, 0) | _shifted(near_cut, -1, 0) | \
            _shifted(near_cut, 0, 1) | _shifted(near_cut, 0, -1)
    leans = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
    # the background's own hue: red and blue about even (pink or rose art leans one way)
    suspect = solid & near_cut & (leans > lean) & (np.abs(rgb[..., 0] - rgb[..., 2]) < 0.2)
    if not suspect.any():
        return rgb, alpha
    # the art each suspect pixel sits on: the mean of the nearest clean pixels, spread inward ring by ring
    art = np.where((solid & ~suspect)[..., None], rgb, 0.0)
    known = solid & ~suspect
    for _ in range(band * 3):
        todo = suspect & ~known
        if not todo.any():
            break
        total, count = np.zeros_like(art), np.zeros(alpha.shape)
        for dy, dx in N8:
            total += _shifted(art, dy, dx)
            count += _shifted(known.astype(float), dy, dx)
        new = todo & (count > 0)
        art[new] = total[new] / count[new][:, None]
        known |= new
    # how much background is in each pixel, along the line from its art to the background
    d = bg - art
    t = np.clip(((rgb - art) * d).sum(2) / np.maximum((d * d).sum(2), 1e-6), 0, 1)
    off_line = np.linalg.norm(rgb - (art + t[..., None] * d), axis=2)
    fringe = suspect & known & (off_line < fit) & (t > 0.03)
    rgb, alpha = rgb.copy(), alpha.copy()
    rgb[fringe] = art[fringe]
    alpha[fringe] = np.minimum(alpha[fringe], 1 - t[fringe])
    # clearly magenta specks and slivers with no art anywhere near (a divider line a crop caught)
    alpha[suspect & ~known & (leans > 0.15)] = 0.0
    return rgb, alpha


def key_dark(cell, bg, shadow):
    """Flood the background in from the cell border (the outlines are nearly the background colour)."""
    h, w, _ = cell.shape
    border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] + \
             [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    bgm = flood(np.abs(cell - bg).sum(2) < 28, border)
    fg = ~bgm
    fg = ~flood(~fg, border)  # fill holes enclosed by the sprite
    if shadow:
        dark = cell.max(2) < 50
        fg &= ~(dark & ~dilate(fg & ~dark, 3))
    return cell / 255.0, fg.astype(float)


def fix_hero_attack_arc(rgb, alpha, source=None):
    """hero_main Attack 2: keep the sword blade, drop the blue slash arc around it (the game draws its own)."""
    cell = (rgb * 255).astype(int)
    m = alpha > 0.5
    h, w = m.shape
    yy, xx = np.mgrid[0:h, 0:w]
    x0, y0, x1, y1 = 230.0, 141.0, 330.0, 184.0  # the blade, hilt to tip
    dx, dy = x1 - x0, y1 - y0
    proj = ((xx - x0) * dx + (yy - y0) * dy) / (dx * dx + dy * dy)
    t = proj.clip(0, 1)
    dist = np.hypot(xx - (x0 + t * dx), yy - (y0 + t * dy))
    blue = (cell[..., 2] - cell[..., 0] > 45) & (cell[..., 2] > 110)
    bluish = cell[..., 2] > cell[..., 0] + 8
    m = m & ~((xx > 246) & ((dist > 10) | blue))
    m = m & ~((xx > 214) & (xx <= 246) & (yy > 150) & (dist > 10) & bluish)
    m = m & ~((proj > 0.985) & (xx > 300))
    hole = ~m & (xx > 236) & (t < 0.97) & (dist <= 7.5)  # where the arc covered the blade
    cell[hole] = (196, 200, 214)
    edge = ~m & (xx > 236) & (t < 0.93) & (dist > 7.5) & (dist <= 9.2) & (dx * (yy - y0) - dy * (xx - x0) < 0)
    cell[edge] = (14, 16, 26)
    return cell / 255.0, (m | hole | edge).astype(float)


def fix_glow_backdrop(rgb, alpha, source=None):
    """Icon sheets with a soft warm glow painted behind each item: everything reachable from the
    cell border through magenta, pink or cream (never orange or gold) is background, so the
    glow and loose sparkles go and the item's outline stops the fill."""
    h, w = alpha.shape
    r, g, b = source[..., 0], source[..., 1], source[..., 2]  # the sheet's own colours, 0..1
    glow = (r > 0.85) & (b > g * 0.52)  # magenta through pink to cream; orange and gold are art
    passable = (alpha < 0.5) | glow
    border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] + \
             [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    outside = flood(passable, border)
    return rgb, np.where(outside, 0.0, alpha)


def fix_glow_backdrop_holes(rgb, alpha, source=None):
    """glow_backdrop, and the glow seen through holes in the item (a ring, a pendant's cord,
    knuckle dusters) goes too: any enclosed patch of glow colours bigger than a highlight."""
    rgb, alpha = fix_glow_backdrop(rgb, alpha, source)
    r, g, b = source[..., 0], source[..., 1], source[..., 2]
    glow = (alpha > 0) & (r > 0.85) & (b > g * 0.52)
    lab, n = label(glow)
    for i in range(1, n + 1):
        m = lab == i
        if m.sum() > 300:
            alpha = np.where(m, 0.0, alpha)
    return rgb, alpha


def fix_card_backdrop(rgb, alpha, source=None, pale=0.5):
    """Icon sheets that draw each item on a framed card (a pastel card, a pale disc behind the
    item, a dark frame with a dark label tab on its top edge): the frame and tab (dark, grey or
    white pixels near the cell edge or in the top band) and every pastel or magenta pixel reachable from the
    cell border are background, so the item's own outline stops the fill."""
    h, w = alpha.shape
    r, g, b = source[..., 0], source[..., 1], source[..., 2]
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum(np.minimum(yy, h - 1 - yy), np.minimum(xx, w - 1 - xx))
    ring = (edge < max(6, 0.06 * min(h, w))) | (yy < 0.16 * h)
    border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] + \
             [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    neutral = (source.max(2) < 0.6) | (source.max(2) - source.min(2) < 0.1)  # dark frame, grey and white tab
    frame = flood((neutral & ring) | (alpha < 0.5), border)
    pastel = (r > 0.78) & (source.min(2) > pale) & (r >= g) & (b > g * 0.52)
    outside = flood(frame | pastel, border)
    return rgb, np.where(outside, 0.0, alpha)


def fix_card_flat(rgb, alpha, source=None):
    """card_backdrop for an item that runs out of the cell (a blade under the label tab, cut
    off with `crop`), where a fill from the border would run into it: the card and its disc
    are the cell's two commonest colours, so a fill from the border through only those colours
    (and the blend between them) stops at the item's own lighter shades."""
    h, w = alpha.shape
    px = (source * 255.0)[alpha > 0.5].reshape(-1, 3)
    vals, counts = np.unique((px // 6).astype(int), axis=0, return_counts=True)
    a, b = (vals[np.argsort(counts)[-2:]] * 6 + 3).astype(float)
    c = source * 255.0
    d = b - a
    t = np.clip(((c - a) * d).sum(2) / max((d * d).sum(), 1.0), 0, 1)
    off = np.linalg.norm(c - (a + t[..., None] * d), axis=2)  # distance from the card-to-disc blend
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum(np.minimum(yy, h - 1 - yy), np.minimum(xx, w - 1 - xx))
    border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] + \
             [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    frame = ((source.max(2) < 0.6) & (edge < max(6, 0.06 * min(h, w)))) | (alpha < 0.5)
    return rgb, np.where(flood(frame | (off < 16), border), 0.0, alpha)


def fix_painted_sky(rgb, alpha, source=None):
    """Backdrop strips painted over their own sky (the area sheets): the sky is the smooth
    gradient reachable from the top of the cell in small colour steps (starting under a magenta
    label bar if there is one), plus closed-off pockets of the same colours between rigging or
    branches. All of it becomes background."""
    h, w = alpha.shape
    raw = source * 255.0
    sky = np.zeros((h, w), bool)
    clear = alpha < 0.5
    q = deque()
    for x in range(w):
        y = 0
        while y < h - 1 and clear[y, x]:
            sky[y, x] = True
            y += 1
        sky[y, x] = True
        q.append((y, x))
    while q:
        y, x = q.popleft()
        c = raw[y, x]
        for dy, dx in N4:
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not sky[ny, nx] and np.abs(raw[ny, nx] - c).sum() < 22.0:
                sky[ny, nx] = True
                q.append((ny, nx))
    like = np.zeros((h, w), bool)  # pockets: patches in their row's sky colour
    for y in range(h):
        if sky[y].sum() >= w * 0.1:
            like[y] = np.abs(raw[y] - np.median(raw[y][sky[y]], 0)).sum(1) < 30.0
    lab, n = label(like & ~sky)
    if n:
        big = np.bincount(lab.ravel()) >= 30
        big[0] = False
        sky |= big[lab]
    return rgb, np.where(sky, 0.0, alpha)


def fix_sky_body(rgb, alpha, source=None):
    """A sun or moon painted on its own sky: crop the cell to the disc (its width is the
    diameter, its top the disc's top; a sun on the horizon can be cut off below). Keeps that
    circle with a soft rim; the painted glow ring goes and the game blooms the disc instead."""
    h, w = alpha.shape
    r = w / 2.0
    yy, xx = np.mgrid[0:h, 0:w]
    a = np.clip((r - np.hypot(yy + 0.5 - r, xx + 0.5 - r)) / 2.0, 0.0, 1.0)
    return source.copy(), a


# Per-cell clean-ups a manifest can ask for with "fix": "<name>".
FIXES = {"hero_attack_arc": fix_hero_attack_arc, "glow_backdrop": fix_glow_backdrop,
         "glow_backdrop_holes": fix_glow_backdrop_holes,
         "painted_sky": fix_painted_sky, "sky_body": fix_sky_body}
def fix_round_top(rgb, alpha, source=None, band=28):
    """A round button whose rim runs under the cell's label box (blanked with `blank`): the
    pixels the label hid are rebuilt. The circle is measured from the rim below the label, and
    each hidden pixel is filled from the nearest uncovered spots on its own ring, one each way
    round, blended by how far away they are, so the rim carries on without a seam."""
    h, w = alpha.shape
    solid = alpha > 0.5
    low = solid.copy()
    low[:band] = False  # the label never reaches this far down
    if not low.any():
        return rgb, alpha
    rows = np.nonzero(low.any(1))[0]
    cols = np.nonzero(low.any(0))[0]
    bottom = rows.max()
    left, right = cols.min(), cols.max()
    cx, rx = (left + right) / 2.0, (right - left) / 2.0 + 0.5
    # the middle, from columns whose rim the label didn't touch (top and bottom both there)
    mids = []
    for x in range(left, right + 1):
        ys = np.nonzero(solid[:, x])[0]
        if len(ys) and ys.min() >= band:
            mids.append((ys.min() + ys.max()) / 2.0)
    cy = float(np.median(mids)) if mids else bottom + 0.5 - rx
    ry = bottom - cy + 0.5
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.hypot((xx - cx) / rx, (yy - cy) / ry)
    top = yy < min(band, int(cy))
    rim = 1 + 2.0 / rx  # the soft edge just outside the circle
    hole = top & (d <= 1) & (alpha < 0.02)
    rgb, alpha = rgb.copy(), alpha.copy()
    alpha[top & (d > rim)] = 0  # label leftovers beside the button
    if not hole.any():
        return rgb, alpha
    ys, xs = np.nonzero(hole)
    hx0, hx1, hy1 = 0, xs.max(), ys.max()  # the label's box, in the cell's top-left corner

    def hidden(y, x):
        return y <= hy1 and hx0 <= x <= hx1

    def nearest_shown(rho, theta, step):
        """The first uncovered spot on this ring going round from theta: (angle moved, y, x)."""
        moved = 0.0
        while moved < np.pi:
            moved += abs(step)
            t = theta + step * moved / abs(step)
            y, x = cy + rho * ry * np.sin(t), cx + rho * rx * np.cos(t)
            y0, x0 = int(np.floor(y)), int(np.floor(x))
            if 0 <= y0 and y0 + 1 < h and 0 <= x0 and x0 + 1 < w \
                    and not any(hidden(y0 + i, x0 + j) for i in (0, 1) for j in (0, 1)):
                return moved, y, x
        return None

    premul = rgb * alpha[..., None]

    def sample(y, x):
        """Colour (premultiplied) and alpha between pixels, so soft edges stay soft."""
        y0, x0 = int(np.floor(y)), int(np.floor(x))
        fy, fx = y - y0, x - x0
        c, a = np.zeros(3), 0.0
        for i, j, k in ((0, 0, (1 - fy) * (1 - fx)), (0, 1, (1 - fy) * fx), (1, 0, fy * (1 - fx)), (1, 1, fy * fx)):
            c += premul[y0 + i, x0 + j] * k
            a += alpha[y0 + i, x0 + j] * k
        return c, a

    filled = []
    step = 0.5 / max(rx, ry)  # about half a pixel along the rim
    for y in range(0, hy1 + 1):
        for x in range(hx0, hx1 + 1):
            if not top[y, x] or d[y, x] > rim:
                continue
            rho = d[y, x]
            theta = np.arctan2((y - cy) / ry, (x - cx) / rx)
            found = [f for f in (nearest_shown(rho, theta, step), nearest_shown(rho, theta, -step)) if f]
            if not found:
                continue
            total = sum(f[0] for f in found)
            c, a = np.zeros(3), 0.0
            for moved, sy, sx in found:
                k = 1.0 if len(found) == 1 else 1 - moved / total  # the nearer side counts for more
                sc, sa = sample(sy, sx)
                c, a = c + sc * k, a + sa * k
            filled.append((y, x, c / a if a > 1e-6 else rgb[y, x], a))
    for y, x, c, a in filled:
        rgb[y, x], alpha[y, x] = c, a
    return rgb, alpha


def fix_medal_symbol(rgb, alpha, source=None, outline=(0.2, 0.125, 0.11), ring=3):
    """A symbol painted on a cream medal (the quest "!", "?" and "..."): only the symbol is kept,
    with its own painted outline, and the disc and its strap go. The symbol is whatever the
    cream face encloses; a dark `ring`-pixel outline goes round it so it reads on any backdrop."""
    h, w = alpha.shape
    solid = alpha > 0.5
    mx, mn = rgb.max(2), rgb.min(2)
    cream = solid & (mx > 0.7) & ((mx - mn) / np.maximum(mx, 1e-6) < 0.4)
    border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] + \
             [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    outside = flood(~cream, border)
    enclosed = ~cream & ~outside & solid
    lab, n = label(enclosed)
    sizes = [(lab == i).sum() for i in range(1, n + 1)]
    if not sizes:
        return rgb, np.zeros_like(alpha)
    symbol = np.zeros_like(solid)
    for i, s in enumerate(sizes):
        if s >= max(sizes) * 0.15:  # the symbol's pieces, not specks in the cream
            symbol |= lab == i + 1
    edge = dilate(symbol, ring) & ~symbol
    rgb = rgb.copy()
    rgb[edge] = outline
    return rgb, (symbol | edge).astype(float)


def fix_magenta_rim(rgb, alpha, source=None, band=6, radius=6):
    """A painted outline Gemini blended into the magenta, kept by a high `key` (one that protects
    purple art): the magenta-leaning pixels along the cut edge take the hue of the art just inside
    them, keeping their own darkness, so the outline stays a dark line in the art's colours."""
    solid = alpha > 0.5
    edge = dilate(~solid, band, outside=True) & (alpha > 0.02)  # the see-through fade outside counts too (smooth edges keep it)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    lean = (alpha > 0.02) & (np.minimum(r, b) - g > 0.12) & (np.abs(r - b) < 0.32)
    rim = edge & lean
    for _ in range(4 * band):  # the whole outline: magenta-leaning pixels joined to the edge
        grown = dilate(rim, 1) & lean
        if (grown == rim).all():
            break
        rim = grown
    good = solid & ~rim
    pad = lambda a: np.pad(a, ((radius, radius), (radius, radius)) + ((0, 0),) * (a.ndim - 2), mode="edge")
    w = sum(_shifted(pad(good.astype(float)), dy, dx) for dy in range(-radius, radius + 1) for dx in range(-radius, radius + 1))
    v = sum(_shifted(pad(rgb * good[..., None]), dy, dx) for dy in range(-radius, radius + 1) for dx in range(-radius, radius + 1))
    w, v = w[radius:-radius, radius:-radius], v[radius:-radius, radius:-radius]
    fill = rim & (w > 0)
    inside = v[fill] / w[fill][:, None]
    dark = np.clip(rgb[fill].mean(1) / np.maximum(inside.mean(1), 1e-3), 0, 1)[:, None]
    rgb = rgb.copy()
    rgb[fill] = inside * dark
    return rgb, alpha


FIXES["magenta_rim"] = fix_magenta_rim
FIXES["round_top"] = fix_round_top
FIXES["medal_symbol"] = fix_medal_symbol
FIXES["card_backdrop"] = fix_card_backdrop
FIXES["card_flat"] = fix_card_flat
# card_backdrop that also clears a pink glow painted round the item (deeper pinks pass too)
FIXES["card_glow"] = lambda rgb, alpha, source=None: fix_card_backdrop(rgb, alpha, source, pale=0.2)


# ---------- palette changes ----------

def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rm = nz & (mx == r)
    gm = nz & (mx == g) & ~rm
    bm = nz & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    h /= 6.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return np.stack([h, s, mx], -1)


def hsv_to_rgb(hsv):
    h, s, v = hsv[..., 0] * 6.0, hsv[..., 1], hsv[..., 2]
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    out = np.zeros(hsv.shape)
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k
        out[m] = np.stack([a[m], b[m], c[m]], -1)
    return out


def recolor_leather(rgb):
    """Stand-in for the leather-and-parchment UI until its sheets are drawn (part 7): the
    purple and violet of the old UI turns to oiled brown leather and its bright gold to a
    softer brass. Reds, blues and greens (HP, MP, icons) are left alone."""
    hsv = rgb_to_hsv(rgb)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    # Purple has more red than green; pure and royal blue (hue 0.64 to 0.67, like the MP bar
    # and the cooldown sweep) share the hue range but not that, so they stay blue.
    purple = (h > 0.62) & (h < 0.97) & (s > 0.12) & (rgb[..., 0] > rgb[..., 1] + 0.02)
    w = np.clip((s - 0.12) / 0.15, 0, 1) * purple
    nh = np.where(purple, 0.075, h)
    ns = np.where(purple, np.clip(s * 0.8 + 0.08, 0, 0.75), s)
    nv = np.where(purple, np.clip(v * 0.95 + 0.02, 0, 1), v)
    gold = (h > 0.09) & (h < 0.18) & (s > 0.35)
    nh = np.where(gold, h - (h - 0.1) * 0.35, nh)
    ns = np.where(gold, s * 0.78, ns)
    nv = np.where(gold, v * 0.93, nv)
    out = hsv_to_rgb(np.stack([nh, ns, nv], -1))
    blend = np.where(purple, w, 1.0)[..., None]
    return np.clip(rgb * (1 - blend) + out * blend, 0, 1)


def recolor_dark_parchment(rgb):
    """The leather sheets (part 7) fill their panels with pale parchment, but the game writes
    light text inside its panels: the big pale areas (not stitching or rivets) become dark oiled
    leather, keeping the parchment's mottling."""
    lo, hi = rgb.min(-1), rgb.max(-1)
    cream = (lo > 0.45) & (rgb[..., 0] >= rgb[..., 2]) & (hi - lo < 0.45)
    lab, n = label(cream)
    big = np.zeros_like(cream)
    for i in range(1, n + 1):
        m = lab == i
        if m.sum() > cream.size * 0.03:
            big |= m
    if not big.any():
        return rgb
    v = rgb.mean(-1)
    shade = np.clip(v / np.median(v[big]), 0.7, 1.3)[..., None]
    dark = np.array([0.30, 0.225, 0.16]) * shade
    out = rgb.copy()
    out[big] = dark[big]
    return np.clip(out, 0, 1)


def recolor_despill(rgb):
    """Pale art the background tinted (sparkles that came back pinkish white): green comes
    up to just under red and blue, so they read white or cream, not pink."""
    out = rgb.copy()
    out[..., 1] = np.maximum(rgb[..., 1], np.minimum(rgb[..., 0], rgb[..., 2]) - 0.06)
    return out


RECOLORS = {"leather": recolor_leather, "dark_parchment": recolor_dark_parchment, "despill": recolor_despill}


# How far "grow" may move a piece's art pixels from the shared size, either way.
GROW_RANGE = (0.8, 1.25)


def art_scale(opts):
    """The shrink that puts `density` texels on every art pixel of a sheet drawn at `art_px`
    sheet pixels per art pixel (times `grow`). Land art is all cut this way, so the game
    draws every piece of it at about one on-screen pixel size (TDStage.art_density)."""
    lo, hi = GROW_RANGE
    if not lo <= opts["grow"] <= hi:
        sys.exit(f"grow {opts['grow']} is outside {lo}..{hi}: the piece would stand out from the land around it")
    return opts["density"] / opts["art_px"] * opts["grow"]


def feather(alpha, radius):
    """Softens a hard cut edge inward: pixels within `radius` of the clear background fade, so
    the shrunk sprite gets an anti-aliased edge. Nothing outside gains alpha."""
    img = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(radius))
    return np.minimum(alpha, np.asarray(img) / 255.0)


def shrink(rgb, alpha, scale):
    h, w = alpha.shape
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    planes = [rgb[..., k] * alpha for k in range(3)] + [alpha]
    small = [np.asarray(Image.fromarray((p * 255).astype(np.uint8)).resize((nw, nh), Image.BOX)) / 255.0
             for p in planes]
    a = small[3]
    out = np.zeros((nh, nw, 3))
    nz = a > 1e-3
    for k in range(3):
        out[..., k][nz] = small[k][nz] / a[nz]
    return np.clip(out, 0, 1), a


def make_seamless(img, blend=0.2):
    """Cross-fades the edges with a half-offset copy so the texture tiles."""
    a = np.asarray(img).astype(float)
    h, w = a.shape[:2]
    shifted = np.roll(np.roll(a, h // 2, 0), w // 2, 1)
    yy, xx = np.mgrid[0:h, 0:w]
    dx = np.minimum(xx, w - 1 - xx) / (w * blend)
    dy = np.minimum(yy, h - 1 - yy) / (h * blend)
    t = np.clip(np.minimum(dx, dy), 0, 1)[..., None]
    out = a * t + shifted * (1 - t)
    # the seam of the shifted copy now sits in the middle; blend that with the original
    return Image.fromarray(out.clip(0, 255).astype(np.uint8))


def seamless_middle(img, cap, blend=0.25):
    """A bar whose middle is tiled between two end caps (`cap` px each): cross-fades the middle's
    ends with a half-offset copy of itself, so painted texture doesn't seam where it repeats."""
    a = np.asarray(img).astype(float)
    mid = a[:, cap:a.shape[1] - cap]
    m = mid.shape[1]
    shifted = np.roll(mid, m // 2, 1)
    xx = np.arange(m)
    t = np.clip(np.minimum(xx, m - 1 - xx) / (m * blend), 0, 1)[None, :, None]
    a[:, cap:a.shape[1] - cap] = mid * t + shifted * (1 - t)
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), img.mode)


def strip_labels(cell, bg, band):
    """Paints the white letters of a cell label over with background. A letter is a small
    patch of near-white pixels in the label band with background all around it, so white
    art (an eye sparkle, a gull) that has its outline around it is left alone."""
    top = cell[:band]
    white = top.min(2) > 185
    lab, n = label(white)
    is_bg = np.abs(top - bg).sum(2) < 120
    for i in range(1, n + 1):
        m = lab == i
        ys, xs = np.nonzero(m)
        if ys.max() - ys.min() > 24 or m.sum() > 400:
            continue
        ring = dilate(m, 2) & ~m
        letter = top[m].min() > 225 and 6 <= ys.max() - ys.min() <= 16  # crisp white, letter-sized
        if is_bg[ring].mean() > (0.15 if letter else 0.4):
            top[dilate(m, 2)] = bg


def cut_cell(rgb_full, bg, box, opts):
    x0, y0, x1, y1 = box
    ins = opts["inset"]
    cell = rgb_full[y0 + ins:y1 - ins, x0 + ins:x1 - ins].astype(float)
    if opts.get("blank_top"):  # a label that touches the art: paint its rows over with background
        cell[:opts["blank_top"]] = bg
    if opts.get("strip_labels"):
        strip_labels(cell, bg, int(opts["label_band"] * cell.shape[0]) if opts["label_band"] < 1 else int(opts["label_band"]))
    if opts.get("blank_label"):  # a label drawn over the art: paint the box around its white letters
        rows = cell[:opts["blank_label"]]
        ys, xs = np.nonzero(rows.min(2) > 200)
        if len(ys):
            cell[:ys.max() + 2, max(0, xs.min() - 1):xs.max() + 2] = bg
    for px0, py0, px1, py1, dx in opts.get("patch", []):  # paint a rect with a copy from dx pixels across (an ornament that would stretch)
        cell[py0:py1, px0:px1] = cell[py0:py1, px0 + dx:px1 + dx].copy()
    for ry0, ry1, dy in opts.get("patch_rows", []):  # paint rows with a copy from dy rows away (a divider line drawn through the art)
        cell[ry0:ry1] = cell[ry0 + dy:ry1 + dy].copy()
    for bx0, by0, bx1, by1 in opts.get("blank", []):  # paint rects over with background (a label beside the art)
        cell[by0:by1, bx0:bx1] = bg
    if "crop" in opts:  # [x0, y0, x1, y1] inside the cell, in source pixels
        cx0, cy0, cx1, cy1 = opts["crop"]
        cell = cell[cy0:cy1, cx0:cx1]
        label_px = 0
    else:
        label_px = opts["label_band"] * cell.shape[0] if opts["label_band"] < 1 else opts["label_band"]
    if opts["background"] == "dark":
        rgb, alpha = key_dark(cell, bg, opts["shadow"])
    elif opts.get("light"):
        rgb, alpha = key_light(cell, bg, hue=opts["light"] if isinstance(opts["light"], list) else None)
    else:
        rgb, alpha = key_magenta(cell, bg, *opts["key"], dark_key=opts["dark_key"])
        if opts["defringe"]:
            rgb, alpha = defringe(rgb, alpha, bg)
    if opts.get("fix"):
        rgb, alpha = FIXES[opts["fix"]](rgb, alpha, source=cell / 255.0)
        if opts["alpha"] == "smooth":  # a clean-up cuts its outline on/off: fade it over about a sprite pixel
            alpha = feather(alpha, 0.5 / opts["scale"])
    rgb, alpha = shrink(rgb, alpha, opts["scale"])
    if opts.get("recolor"):
        rgb = RECOLORS[opts["recolor"]](rgb)
    solid = alpha > (0.04 if opts["alpha"] == "soft" else 0.5)
    lab, n = label(solid)
    band = label_px * opts["scale"]
    left = alpha.shape[1] * 0.6
    keep = np.zeros_like(solid)
    pieces = []
    for i in range(1, n + 1):
        m = lab == i
        ys, xs = np.nonzero(m)
        if m.sum() < opts["min_area"]:
            continue
        z = opts.get("zoom", 1)
        if min(np.ptp(ys), np.ptp(xs)) <= 2 * z and max(np.ptp(ys), np.ptp(xs)) >= 12 * z:  # a stray bit of cell divider
            continue
        if ys.max() < band and (xs.min() < left or ys.max() - ys.min() < band * 0.6):  # the label text
            continue
        if opts.get("strip_labels") and ys.max() < band * 1.5 and m.sum() < m.size * 0.01 \
                and (rgb[m].min(1) > 0.6).mean() > 0.5:  # small pale label leftovers
            continue
        pieces.append(m)
    if not pieces:
        return []
    if opts["keep"] == "largest":
        pieces = [max(pieces, key=lambda m: m.sum())]
    groups = pieces if opts["keep"] == "split" else [np.any(pieces, axis=0)]
    if opts["keep"] == "split":
        biggest = max(m.sum() for m in groups)
        groups = [m for m in groups if m.sum() >= biggest * 0.15]  # crumbs, not pieces
        groups.sort(key=lambda m: np.nonzero(m)[0 if opts.get("split_by") == "y" else 1].min())  # left to right, or top to bottom
    out = []
    for g in groups:
        reach = dilate(g, 2 if opts["alpha"] == "soft" else 1)  # the edge's fade (and a glow's reach)
        a = alpha * (g if opts["alpha"] == "hard" else reach)
        if opts["alpha"] == "hard":
            a = (a > 0.5).astype(float)
        ys, xs = np.nonzero(a > 0)
        by0, by1, bx0, bx1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        if not opts.get("trim", True):  # animation frames: keep the whole cell, so they line up
            by0, by1, bx0, bx1 = 0, a.shape[0], 0, a.shape[1]
        px = np.zeros((by1 - by0, bx1 - bx0, 4), np.uint8)
        px[..., :3] = (rgb[by0:by1, bx0:bx1] * 255).round().astype(np.uint8)
        px[..., 3] = (a[by0:by1, bx0:bx1] * 255).round().astype(np.uint8)
        px[px[..., 3] == 0, :3] = 0
        out.append({"image": Image.fromarray(px, "RGBA"), "x": int(bx0), "y": int(by0),
                    "cell_w": alpha.shape[1], "cell_h": alpha.shape[0], "detail": opts["detail"]})
    return out


def extend_bottom(img, n):
    """Continues a parallax strip n rows further down in its own colours, so a layer
    never shows sky under it. The colour is the strip's bottom edge, blurred sideways."""
    a = np.asarray(img).astype(float)
    h, w, _ = a.shape
    edge = a[h - 8:h - 2].mean(0)  # skip the last rows (anti-aliasing against the divider)
    k = 41
    pad = np.concatenate([edge[:k], edge, edge[-k:]])
    kernel = np.ones(k) / k
    soft = np.stack([np.convolve(pad[:, c], kernel, "same")[k:-k] for c in range(4)], 1)
    flat = soft.mean(0)
    out = np.zeros((h + n, w, 4))
    out[:h] = a
    for i in range(n):
        t = min(1.0, i / max(1, n * 0.5))
        out[h + i] = soft * (1 - t) + flat * t
    out[h - 2:h + 4] = (out[h - 2:h + 4] + soft) / 2  # soften the join
    out[..., 3] = np.where(np.arange(h + n)[:, None] >= h - 2, 255, out[..., 3])
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGBA")


FLAT_MAX = 0.22     # flat_bottom cuts at most this share of a sprite's height
FLAT_WIDEN = 0.04   # a bottom row still curving: the row above is this much (of the body's width) wider
FLAT_SOLID = 128    # alpha that counts as part of the sprite's silhouette


def flat_bottom_rows(alpha):
    """How many rows to cut off the bottom of a sprite so it stands on a flat edge: the rows where
    its outline still curves in (each row up is clearly wider than the one below, as under a
    rock, barrel or bush). Straight sides (legs, posts, walls) widen nothing, so they keep every row."""
    solid = alpha >= FLAT_SOLID
    rows = np.nonzero(solid.any(1))[0]
    if len(rows) < 8:
        return 0
    bottom, height = rows[-1], rows[-1] - rows[0] + 1
    width = solid.sum(1).astype(float)
    body = width[max(rows[0], bottom - int(height * 0.35)):bottom + 1].max()
    widens = lambda y: width[y - 1] - width[y] > FLAT_WIDEN * body
    cut = 0
    for c in range(int(height * FLAT_MAX)):
        y = bottom - c
        if not widens(y) and not any(widens(y - k) for k in range(1, 4)):
            break
        cut = c + 1
    return cut


def flatten_bottom(img, rows=True):
    """Squares off the bottom of a sprite that stands on the ground, so it sits flush on the land:
    cuts flat_bottom_rows (rows=True) or `rows` rows off its bottom, below its lowest opaque row."""
    a = np.asarray(img.convert("RGBA"))
    solid = np.nonzero((a[..., 3] >= FLAT_SOLID).any(1))[0]
    if not len(solid):
        return img
    bottom = solid[-1]
    cut = flat_bottom_rows(a[..., 3]) if rows is True else int(rows)
    return img.crop((0, 0, img.width, bottom + 1 - cut))


GROUND_BLEND = 12  # rows over which a strip's own bottom fades into its painted ground


def paint_ground(img, ground, strip_h):
    """Swaps an extend_bottom pad for painted ground: `ground` is a picture of the whole padded
    strip whose lower part was painted on as ground (a Gemini edit of it), so the backdrop runs
    on down to the floor instead of ending in a blur. The strip's own rows above strip_h stay
    exactly as cut; below, the ground picture takes over, fading in over GROUND_BLEND rows."""
    a = np.asarray(img.convert("RGBA")).astype(float)
    g = np.asarray(ground.convert("RGBA").resize(img.size, Image.LANCZOS)).astype(float)
    g[..., 3] = 255.0  # the ground is solid wherever it is used (below the strip's skyline)
    t = np.clip((np.arange(a.shape[0]) - (strip_h - GROUND_BLEND)) / GROUND_BLEND, 0.0, 1.0)[:, None, None]
    out = a * (1.0 - t) + g * t
    return Image.fromarray(out.round().clip(0, 255).astype(np.uint8), "RGBA")


# ---------- animation sets ----------

def head_x(im):
    """Centre of the head: coloured (not pale steel) pixels in the upper part of the figure."""
    a = np.asarray(im).astype(int)
    top = a[int(im.height * 0.12):int(im.height * 0.45)]
    m = (top[..., 3] > 0) & (top[..., :3].min(2) < 170)
    return float(np.nonzero(m)[1].mean()) if m.any() else im.width / 2


def mass_x(im):
    a = np.asarray(im)[..., 3] > 0
    return float(np.nonzero(a)[1].mean())


def build_set(name, spec, sprites, out_root):
    """Lays the frames of one animation set on a strip, feet on a shared baseline."""
    frames = []
    detail = sprites[next(iter(spec["frames"].values()))]["detail"]  # nudges and padding are in art pixels
    nudge = {k: [v * detail for v in n] for k, n in spec.get("nudge", {}).items()}
    for key in spec["frames"]:
        sheet_frame = spec["frames"][key]
        s = sprites[sheet_frame]
        im = s["image"]
        if spec.get("anchor", "mass") == "head":
            ax = head_x(im)
        elif spec.get("anchor") == "cell":
            ax = s["cell_w"] / 2 - s["x"]
        else:
            ax = mass_x(im)
        ax += nudge.get(key, [0, 0])[0]
        if spec.get("baseline", "bottom") == "cell":
            bottom = s["cell_h"] - (s["y"] + im.height)  # empty rows under the sprite inside its cell
        else:
            bottom = 0
        bottom -= nudge.get(key, [0, 0])[1]
        frames.append((key, im, ax, bottom))
    if spec.get("baseline") == "cell":
        lowest = min(b for _, _, _, b in frames)
        frames = [(k, im, ax, b - lowest) for k, im, ax, b in frames]
    half = max(max(ax, im.width - ax) for _, im, ax, _ in frames)
    fw = int(np.ceil(half)) * 2 + 2
    fh = max(im.height + b for _, im, _, b in frames) + 1 + spec.get("pad_top", 0) * detail
    strip = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
    index = {}
    for i, (key, im, ax, b) in enumerate(frames):
        strip.alpha_composite(im, (i * fw + round(fw / 2 - ax), fh - 1 - b - im.height))
        index[key] = i
    png = os.path.join(out_root, spec["out"])
    os.makedirs(os.path.dirname(png), exist_ok=True)
    strip.save(png)
    tres = os.path.join(ROOT, spec["sprite_frames"])
    os.makedirs(os.path.dirname(tres), exist_ok=True)
    write_sprite_frames(tres, "res://" + os.path.relpath(png, ROOT), fw, fh, index, spec["animations"])
    print(f"  set {name}: {len(frames)} frames of {fw}x{fh} -> {spec['out']}, {spec['sprite_frames']}")


def write_sprite_frames(path, texture, fw, fh, index, anims):
    """A Godot SpriteFrames resource whose frames are regions of one strip texture."""
    used = sorted({index[f] for a in anims.values() for f in a["frames"]})
    lines = [f'[gd_resource type="SpriteFrames" load_steps={len(used) + 2} format=3]', "",
             f'[ext_resource type="Texture2D" path="{texture}" id="1_strip"]', ""]
    for i in used:
        lines += [f'[sub_resource type="AtlasTexture" id="f{i}"]', 'atlas = ExtResource("1_strip")',
                  f"region = Rect2({i * fw}, 0, {fw}, {fh})", ""]
    entries = []
    for name, a in anims.items():
        # "durations": how long each frame shows, in frames at "fps" (a wind-up held longer, a fast impact)
        durations = a.get("durations", [1.0] * len(a["frames"]))
        if len(durations) != len(a["frames"]):
            sys.exit(f"{path}: animation {name} has {len(a['frames'])} frames but {len(durations)} durations")
        frames = ", ".join('{"duration": %s, "texture": SubResource("f%d")}' % (float(d), index[f])
                           for f, d in zip(a["frames"], durations))
        entries.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}'
                       % (frames, "true" if a.get("loop", True) else "false", name, float(a.get("fps", 8))))
    lines += ["[resource]", "animations = [" + ", ".join(entries) + "]", ""]
    with open(path, "w") as f:
        f.write("\n".join(lines))


# ---------- driver ----------

def process(manifest_path, grid_only=False, sprites=None):
    with open(manifest_path) as f:
        man = json.load(f)
    sheet_id = os.path.splitext(os.path.basename(manifest_path))[0]
    src = os.path.join(ROOT, man["source"])
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(int)
    if "region" in man:  # [x0, y0, x1, y1]: only this part of the sheet (one monster of a group sheet)
        x0, y0, x1, y1 = man["region"]
        rgb = rgb[y0:y1, x0:x1]
    base = {**DEFAULTS, **{k: v for k, v in man.items() if k in DEFAULTS}}
    bg = np.array(base["background"]) if isinstance(base["background"], list) else background_color(rgb)
    bands = grid_from_manifest(man["grid"], rgb.shape) if "grid" in man else detect_grid(rgb, bg, man.get("grid_threshold", 0.8))
    print(f"{sheet_id}: {len(bands)} rows, cells per row {[len(c) for _, _, c in bands]}")
    if grid_only:
        for y0, y1, cols in bands:
            print(f"  y {y0}-{y1}: x {[c for c in cols]}")
        return
    names = man["cells"]
    if len(names) != len(bands) or any(len(n) != len(b[2]) for n, b in zip(names, bands)):
        sys.exit(f"{sheet_id}: the manifest names {[len(n) for n in names]} cells per row, "
                 f"the sheet has {[len(b[2]) for b in bands]}")
    out_dir = os.path.join(ROOT, man["out_dir"])
    os.makedirs(out_dir, exist_ok=True)
    count = 0
    for (y0, y1, cols), row in zip(bands, names):
        for (x0, x1), name in zip(cols, row):
            if not name:
                continue
            opts = {**base, **man.get("overrides", {}).get(name, {})}
            if opts["art_px"]:
                opts["scale"] = art_scale(opts)
                opts["detail"] = opts["density"]
            else:  # sizes given in the cut sprite's pixels stay in art pixels
                opts["scale"] *= opts["detail"]
                opts["min_area"] *= opts["detail"] ** 2
                opts["zoom"] = opts["detail"]
            pieces = cut_cell(rgb, bg, (x0, y0, x1, y1), opts)
            if not pieces:
                print(f"  {name}: nothing found")
                continue
            for i, p in enumerate(pieces):
                pname = f"{name}_{i + 1}" if opts["keep"] == "split" else name
                im = p["image"]
                if opts.get("flip"):  # drawn facing the other way (a slash arc that should open toward the hero)
                    im = im.transpose(Image.FLIP_LEFT_RIGHT)
                    p["x"] = p["cell_w"] - p["x"] - im.width
                if opts.get("seamless"):
                    side = opts.get("size", min(im.size))
                    im = make_seamless(im.convert("RGB").crop((0, 0, min(im.size), min(im.size)))
                                       .resize((side, side), Image.BOX)).convert("RGBA")
                if opts.get("seamless_middle"):
                    im = seamless_middle(im, opts["seamless_middle"])
                if opts.get("flat_bottom"):
                    im = flatten_bottom(im, opts["flat_bottom"])
                if opts.get("extend_bottom"):
                    strip_h = im.height
                    im = extend_bottom(im, opts["extend_bottom"])
                    if opts.get("ground"):
                        im = paint_ground(im, Image.open(os.path.join(ROOT, opts["ground"])), strip_h)
                p["image"] = im
                if sprites is not None:
                    sprites[f"{sheet_id}:{pname}"] = p
                if opts.get("save", True):
                    dest = os.path.join(ROOT, opts["out_dir"]) if "out_dir" in opts else out_dir
                    os.makedirs(dest, exist_ok=True)
                    im.save(os.path.join(dest, pname + ".png"))
                count += 1
    print(f"  {count} sprites -> {man['out_dir']}")
    return man


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    grid_only = "--grid" in sys.argv
    # touch-up sheets replace pieces of other sheets, so they go last
    paths = sorted((os.path.join(SHEETS, f) for f in os.listdir(SHEETS) if f.endswith(".json")),
                   key=lambda p: (os.path.basename(p).startswith("touchups"), p))
    if args:
        paths = [p for p in paths if os.path.splitext(os.path.basename(p))[0] in args]
    # a manifest can land before its sheet does (art still being made)
    ready = []
    for p in paths:
        with open(p) as f:
            source = json.load(f).get("source")
        if source is None:  # not a sheet (paperdoll_rig.json is read by paperdoll_layers.py)
            continue
        if os.path.exists(os.path.join(ROOT, source)):
            ready.append(p)
        else:
            print(f"{os.path.basename(p)}: skipped, {source} isn't there yet")
    sprites = {}
    manifests = [process(p, grid_only, sprites) for p in ready]
    if grid_only:
        return
    # animation sets can pull frames from any sheet processed in this run
    for man in manifests:
        for name, spec in man.get("sets", {}).items():
            missing = [f for f in spec["frames"].values() if f not in sprites]
            if missing:
                print(f"  set {name}: skipped, run its sheets too ({missing[:3]}...)")
                continue
            build_set(name, spec, sprites, ROOT)
    # platform pieces get lined up and thinned for the game once they're cut
    for p in ready:
        name = os.path.splitext(os.path.basename(p))[0]
        if name.startswith("platform_pieces_"):
            platform_pieces.prepare(name[len("platform_pieces_"):])
    # rope and ladder pieces get lined up on their rope or rails (their pieces may come from
    # several sheets, so any climb style with a piece cut in this run)
    climb_pieces.prepare_for({key.split(":", 1)[1] for key in sprites})


if __name__ == "__main__":
    main()
