"""Line up the rope, vine and ladder pieces cut by slice_sheets.py so they join in the game.

slice_sheets.py runs this right after it cuts a sheet whose manifest has a "climb" section
(it works on the fresh cut, so run the slicer, not this):

    python3 tools/art/slice_sheets.py ropes_props_b

The game stacks a climbable's pieces centred on one line: the top piece, a whole number of
middles, the bottom piece, each touching the next (ClimbStyleDef.pieces). Gemini draws each
piece centred on its picture, not on its rope or rails, so a knot, curl or leaf sticking out
to one side pulls the rope off the line, and a ladder's end pieces put their rungs wherever
they like. So for each style this script:

1. Trims fully clear rows off the top and bottom of every piece, so pieces really touch.
2. Makes the middle piece join itself: when its rope or rails leave the bottom edge at a
   different place than they enter the top (a vine that leans), it leans the rows back so
   they meet, a fraction of a pixel per row. Then pads it so the rope or rails are centred.
3. Finds where the bottom piece carries on from a middle piece: the sideways shift and the
   number of its top rows to drop so it starts like the next middle would (a ladder's
   rungs keep their spacing into it). The top piece likewise ends like a middle ends.
   Each end piece is cut there and padded so the joint lands on the centre line.

Manifest section, one entry per climb style (any of "top"/"bottom" may be left out):
    "climb": {"ladder": {"top": "ladder_top", "middle": "ladder_middle", "bottom": "ladder_bottom"}}
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SOLID = 127
WINDOW = 16       # rows compared where a middle piece joins itself (fewer when it is short)
CROP_COST = 0.004  # mismatch an extra dropped row must save to be worth dropping
MAX_CROP = 0.6    # share of an end piece's height that may be dropped


def solid(a):
    return (a[..., 3] > SOLID).astype(float)


def trim_rows(a):
    """`a` without the fully clear rows above and below the art."""
    rows = np.nonzero(solid(a).any(1))[0]
    return a[rows[0]:rows[-1] + 1] if len(rows) else a


def mismatch(ref, piece, d):
    """How differently two equal-height masks are solid (0 same, 1 nothing shared) when
    `piece` is moved so its column x lies on `ref` column x + d."""
    h, wr = ref.shape
    wp = piece.shape[1]
    left = min(0, d)
    right = max(wr, d + wp)
    a = np.zeros((h, right - left))
    b = np.zeros_like(a)
    a[:, -left:-left + wr] = ref
    b[:, d - left:d - left + wp] = piece
    return np.abs(a - b).sum() / max(1.0, a.sum() + b.sum())


def best_join(ref, piece, crops, piece_rows):
    """(shift, crop) that best fits a window of `piece` to `ref` (masks of equal height):
    `piece_rows(crop)` slices the piece's window for each crop tried, and the shift d puts
    the piece's column x at ref column x + d, tried up to half the wider one's width either
    side of "centres together". Small crops and small shifts win ties."""
    centred = (ref.shape[1] - piece.shape[1]) // 2
    reach = max(2, max(ref.shape[1], piece.shape[1]) // 2)
    best, best_err = (centred, 0), None
    for k in crops:
        win = piece_rows(k)
        for d in range(centred - reach, centred + reach + 1):
            err = mismatch(ref, win, d) + CROP_COST * k + 0.0001 * abs(d - centred)
            if best_err is None or err < best_err:
                best, best_err = (d, k), err
    return best


def lean(a, d):
    """`a` with each row moved sideways so the bottom row ends up `d` pixels right of where it
    was, rows between moved in proportion (the top row stays)."""
    h, w = a.shape[:2]
    if d == 0:
        return a
    out = np.zeros((h, w + abs(d), 4), a.dtype)
    base = -d if d < 0 else 0
    for y in range(h):
        x = base + round(d * y / max(1, h - 1))
        out[y, x:x + w] = a[y]
    return out


def centre_on(a, c):
    """`a` padded with clear columns so column `c` (may be fractional) is its centre."""
    h, w = a.shape[:2]
    gap = round(2 * c - w)  # right minus left padding
    left, right = max(0, -gap), max(0, gap)
    out = np.zeros((h, w + left + right, 4), a.dtype)
    out[:, left:left + w] = a
    return out


def centroid(a):
    cols = solid(a).sum(0)
    return (cols * (np.arange(len(cols)) + 0.5)).sum() / max(1.0, cols.sum())


def line_up(top, middle, bottom):
    """The three pieces (RGBA arrays; top and bottom may be None) lined up as described above."""
    middle = trim_rows(middle)
    m = solid(middle)
    win = max(2, min(WINDOW, len(m) // 3))
    # where the middle's bottom rows sit in the next middle's top rows; a lean changes what
    # the rows look like, so look again until they meet
    total = 0
    for _ in range(4):
        m = solid(lean(middle, total))
        d, _ = best_join(m[:win], m, [0], lambda k: m[-win:])
        if d == 0:
            break
        total += d
    middle = lean(middle, total)
    middle = centre_on(middle, centroid(middle))
    m = solid(middle)
    mid_c = middle.shape[1] / 2
    if bottom is not None:
        bottom = trim_rows(bottom)
        b = solid(bottom)
        n = min(len(m), len(b) // 2)
        crops = range(0, max(1, min(len(m), int(len(b) * MAX_CROP), len(b) - n)))
        d, k = best_join(m[:n], b, crops, lambda k: b[k:k + n])
        bottom = centre_on(bottom[k:], mid_c - d)
    if top is not None:
        top = trim_rows(top)
        t = solid(top)
        n = min(len(m), len(t) // 2)
        crops = range(0, max(1, min(len(m), int(len(t) * MAX_CROP), len(t) - n)))
        d, k = best_join(m[-n:], t, crops, lambda k: t[len(t) - k - n:len(t) - k])
        top = centre_on(top[:len(top) - k], mid_c - d)
    return top, middle, bottom


def prepare(manifest):
    """Line up every climb style listed in a cut sheet's manifest, in its out_dir."""
    out_dir = os.path.join(ROOT, manifest["out_dir"])
    for style, parts in manifest.get("climb", {}).items():
        paths = {k: os.path.join(out_dir, parts[k] + ".png") for k in ("top", "middle", "bottom") if k in parts}
        missing = [p for p in paths.values() if not os.path.exists(p)]
        if missing:
            print(f"  climb {style}: skipped, {os.path.basename(missing[0])} isn't cut")
            continue
        pics = {k: np.array(Image.open(p).convert("RGBA")) for k, p in paths.items()}
        lined = line_up(pics.get("top"), pics["middle"], pics.get("bottom"))
        for k, a in zip(("top", "middle", "bottom"), lined):
            if a is not None:
                Image.fromarray(a).save(paths[k])
        print(f"  climb {style}: pieces lined up")
