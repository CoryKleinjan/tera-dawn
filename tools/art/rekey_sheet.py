#!/usr/bin/env python3
"""Puts the magenta background back on a Gemini edit that came back on another colour (cream,
grey, pink, a purple wash), using the sheet it was edited from. An edit keeps the layout, so
wherever the original was magenta, well away from any art, the edit is background too; next to
the art, an edited pixel is background only when it matches the edit's own background colour
nearby and touches the sure background. The art's dark outline stops the fill, so art that
happens to share the background colour (parchment on a cream background) stays.

    python3 tools/art/rekey_sheet.py ORIGINAL.png EDITED.png OUT.png [--band 6]

ORIGINAL and EDITED must be the same size. The original's cell dividers are copied back, and
divider lines Gemini redrew a few pixels off are cleared, so the slicer finds the same cells.
Labels are not magenta in the original, so they stay and the slicer removes them as usual.
"""
import argparse

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import slice_sheets as ss  # noqa: E402

MAGENTA = np.array([255, 0, 255], np.uint8)


def magenta_mask(rgb):
    c = rgb.astype(int)
    return (np.minimum(c[..., 0], c[..., 2]) - c[..., 1] > 100) & (np.abs(c[..., 0] - c[..., 2]) < 90)


def shift_or(mask, steps):
    """Grows a mask by `steps` pixels (4-connected)."""
    m = mask.copy()
    for _ in range(steps):
        g = m.copy()
        g[1:] |= m[:-1]
        g[:-1] |= m[1:]
        g[:, 1:] |= m[:, :-1]
        g[:, :-1] |= m[:, 1:]
        m = g
    return m


def box_mean(values, weights, r):
    """Mean of `values` over the weighted pixels in a (2r+1)^2 box around each pixel."""
    def box(a):
        p = np.pad(a, ((r + 1, r), (r + 1, r)) + ((0, 0),) * (a.ndim - 2))
        s = p.cumsum(0).cumsum(1)
        return s[2 * r + 1:, 2 * r + 1:] - s[:-2 * r - 1, 2 * r + 1:] - s[2 * r + 1:, :-2 * r - 1] + s[:-2 * r - 1, :-2 * r - 1]
    w = box(weights.astype(np.float64))
    v = box(values.astype(np.float64) * weights[..., None])
    return v / np.maximum(w, 1e-6)[..., None], w > 0


def copy_line(src, out, box, axis):
    """Copies the original's divider pixels in `box` (rows for axis 0, columns for axis 1),
    not the art or background a divider runs past."""
    part = src[box].astype(int)
    if axis == 1:
        part = part.transpose(1, 0, 2)
    for i, line in enumerate(part):
        colour = np.median(line, 0)
        if magenta_mask(colour[None, None].astype(np.uint8))[0, 0]:
            continue                                 # a background line beside the divider
        keep = np.abs(line - colour).sum(1) < 45
        if keep.mean() < 0.5:
            continue
        idx = np.nonzero(keep)[0]
        if axis == 0:
            rows = range(box[0].start, box[0].stop)
            out[rows[i], idx] = src[rows[i], idx]
        else:
            cols = range(box[1].start, box[1].stop)
            out[box[0].start + idx, cols[i]] = src[box[0].start + idx, cols[i]]


def restore_dividers(src, out, bg, band, threshold):
    """Copies the original's cell dividers back and clears any line Gemini redrew beside them."""
    grid = ss.detect_grid(src.astype(int), ss.background_color(src).astype(int), threshold)
    h, w = bg.shape
    for n, (y0, y1, cols) in enumerate(grid):
        rows = [y0] if n else []
        for y in rows:
            lo, hi = max(0, y - band), min(h, y + band + 1)
            out[lo:hi][bg[lo:hi]] = MAGENTA
            copy_line(src, out, (slice(max(0, y - 3), min(h, y + 4)), slice(None)), 0)
        for x0, _ in cols[1:]:
            lo, hi = max(0, x0 - band), min(w, x0 + band + 1)
            strip = out[y0:y1, lo:hi]
            strip[bg[y0:y1, lo:hi]] = MAGENTA
            copy_line(src, out, (slice(y0, y1), slice(max(0, x0 - 3), min(w, x0 + 4))), 1)


def unmix_edge(out, fill, local, width=3):
    """Gemini blends the art's edge into its own background colour; swap that colour for magenta
    in the edge pixels, so the slicer's key and defringe see the usual magenta blend."""
    edge = shift_or(fill, width) & ~fill
    deep = ~shift_or(fill, width + 1)
    fg, has_fg = box_mean(out, deep, width + 2)
    edge &= has_fg
    p = out[edge].astype(float)
    f = fg[edge]
    l = local[edge]
    d = l - f
    a = np.clip(((p - f) * d).sum(1) / np.maximum((d * d).sum(1), 1.0), 0.0, 1.0)
    a[np.sqrt((d * d).sum(1)) < 60] = 0.0         # art too close to the background colour to tell apart
    out[edge] = np.clip(p + a[:, None] * (MAGENTA - l), 0, 255).astype(np.uint8)


def rekey(original, edited, band=6, tolerance=70, threshold=0.7):
    src = np.asarray(original.convert("RGB"))
    out = np.asarray(edited.convert("RGB")).copy()
    bg = magenta_mask(src)
    art = ~bg
    near_art = shift_or(art, band)
    sure = bg & ~near_art                        # background, well away from any art
    local, known = box_mean(out, sure, 4 * band)
    close = known & (np.abs(out.astype(int) - local).sum(2) < tolerance)
    allowed = sure | (shift_or(bg, band) & near_art & close)
    fill = sure.copy()
    while True:                                   # flood from the sure background
        grown = shift_or(fill, 1) & allowed
        if grown.sum() == fill.sum():
            break
        fill = grown
    unmix_edge(out, fill, local)
    out[fill] = MAGENTA
    restore_dividers(src, out, bg, band, threshold)
    return Image.fromarray(out), fill.mean()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("original")
    ap.add_argument("edited")
    ap.add_argument("out")
    ap.add_argument("--band", type=int, default=6, help="pixels next to the art that are checked by colour")
    ap.add_argument("--threshold", type=float, default=0.7, help="divider detection, as the manifest's grid_threshold")
    a = ap.parse_args()
    o, e = Image.open(a.original), Image.open(a.edited)
    if o.size != e.size:
        raise SystemExit("sizes differ: %s vs %s" % (o.size, e.size))
    img, share = rekey(o, e, a.band, threshold=a.threshold)
    img.save(a.out)
    print("%s: %.1f%% background" % (a.out, share * 100))


if __name__ == "__main__":
    main()
