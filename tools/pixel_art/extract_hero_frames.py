#!/usr/bin/env python3
"""Cut the hero's animation frames out of Cory's sprite sheet.

art/reference/hero_spritesheet.png is a 4x4 grid on a dark background:
Idle 1-4, Walk 1-4, Run 1-4, Attack 1, Attack 2, Hit, Hurt. For each frame we
remove the background and the drop shadow, keep the character's outline, take
the slash arc off Attack 2 (the game draws its own slash), and shrink every
frame by the same factor to the game's scale (idle is about 85 pixels tall).
The results go to tools/pixel_art/hero_frames/, which build_hero.py lays out.

Run from anywhere: python3 tools/pixel_art/extract_hero_frames.py
"""
import os
from collections import deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "art", "reference", "hero_spritesheet.png")
OUT = os.path.join(HERE, "hero_frames")
NAMES = ["idle1", "idle2", "idle3", "idle4", "walk1", "walk2", "walk3", "walk4",
         "run1", "run2", "run3", "run4", "attack1", "attack2", "hit", "hurt"]
BG = np.array([24, 27, 34])  # the sheet's background colour
XS, YS = [0, 385, 769, 1153, 1536], [0, 256, 507, 753, 1024]  # cell edges
SCALE = 0.36
N8 = [(dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]


def flood(mask, seeds, nb):
    h, w = mask.shape
    out = np.zeros_like(mask)
    q = deque()
    for s in seeds:
        if mask[s] and not out[s]:
            out[s] = True
            q.append(s)
    while q:
        y, x = q.popleft()
        for dy, dx in nb:
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not out[ny, nx]:
                out[ny, nx] = True
                q.append((ny, nx))
    return out


def largest_blob(mask):
    seen = np.zeros_like(mask)
    best = None
    for y, x in zip(*np.nonzero(mask)):
        if not seen[y, x]:
            blob = flood(mask, [(y, x)], N8)
            seen |= blob
            if best is None or blob.sum() > best.sum():
                best = blob
    return best


def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


def cut(cell):
    h, w, _ = cell.shape
    border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] + \
             [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    bg = flood(np.abs(cell - BG).sum(2) < 28, border, N8[1::2])
    m = largest_blob(~bg)  # drops the frame label and stray marks
    m = ~flood(~m, border, N8[1::2])  # fill enclosed holes
    # the soft drop shadow: dark pixels more than 3px from any coloured pixel
    dark = cell.max(2) < 50
    m &= ~(dark & ~dilate(m & ~dark, 3))
    return largest_blob(m)


def remove_arc(cell, m):
    """Attack 2: keep the sword blade, drop the blue slash arc around it."""
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
    cell = cell.copy()
    hole = ~m & (xx > 236) & (t < 0.97) & (dist <= 7.5)  # where the arc covered the blade
    cell[hole] = (196, 200, 214)
    edge = ~m & (xx > 236) & (t < 0.93) & (dist > 7.5) & (dist <= 9.2) & (dx * (yy - y0) - dy * (xx - x0) < 0)
    cell[edge] = (14, 16, 26)
    return cell, largest_blob(m | hole | edge)


def shrink(cell, m):
    ys, xs = np.nonzero(m)
    cell, m = cell[ys.min():ys.max() + 1, xs.min():xs.max() + 1], m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    w, h = round(m.shape[1] * SCALE), round(m.shape[0] * SCALE)
    al = m.astype(float)
    planes = [cell[..., k] / 255.0 * al for k in range(3)] + [al]
    small = [np.asarray(Image.fromarray((p * 255).astype(np.uint8)).resize((w, h), Image.BOX)) / 255.0 for p in planes]
    a = small[3]
    keep = a > 0.45
    out = np.zeros((h, w, 4), np.uint8)
    for k in range(3):
        out[..., k][keep] = (small[k][keep] / a[keep] * 255).clip(0, 255).astype(np.uint8)
    out[..., 3] = keep * 255
    return Image.fromarray(out)


def main():
    sheet = np.asarray(Image.open(SRC).convert("RGB")).astype(int)
    os.makedirs(OUT, exist_ok=True)
    for i, name in enumerate(NAMES):
        r, c = divmod(i, 4)
        cell = sheet[YS[r] + 2:YS[r + 1] - 2, XS[c] + 2:XS[c + 1] - 2]
        m = cut(cell)
        if name == "attack2":
            cell, m = remove_arc(cell, m)
        im = shrink(cell, m)
        im.save(os.path.join(OUT, name + ".png"))
        print(name, im.size)


if __name__ == "__main__":
    main()
