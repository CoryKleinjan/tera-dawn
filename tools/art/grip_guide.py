#!/usr/bin/env python3
"""Make the base image for the grip-hands edit, and put the edit's hands on the body sheet.

The body sheet draws his weapon hand as an empty fist with the thumb on the outside, so a
sword pushed through it (paperdoll_layers.weapon_strips) comes out with the thumb on the
pommel end. To fix the hands, Gemini edits the body sheet with a guide rod through each
weapon fist: the rod lies the way paperdoll_rig.json points the sword, long on the blade
side and short on the pommel side, and Gemini redraws the hand gripping it with the thumb
wrapped next to the long end.

    python3 tools/art/grip_guide.py guide OUT.png
        the body sheet with a rod drawn through each weapon fist (the edit's base)
    python3 tools/art/grip_guide.py hands EDIT.png [--cells run1,run2,...] [--rods RODS.png]
        put the edit's hands on the body sheet; --cells first copies those whole cells
        from the edit (cells the edit redrew, like the run cycle) and prints the rig's
        weapon for them, along the edit's rod; --rods reads the rods from another sheet
        (the edit before its rods were taken out)

    python3 tools/art/grip_guide.py closeups DIR GUIDE.png
        close-ups of the guide's weapon hands, a few per image (Gemini redraws a hand
        when it is big in the picture; see GROUPS)
    python3 tools/art/grip_guide.py closeup-hands EDIT_1.png EDIT_2.png ... [--only jump,fall]
        put the hands from the edited close-ups on the body sheet (only those cells')

`hands` takes only the hand around each rod from the edit (the rod taken out and painted
over) and pastes it into art/source/paperdoll_body.png, so nothing else on the sheet moves.
Then re-cut the body and rebuild the layers (slice_sheets.py paperdoll_body, then
paperdoll_layers.py).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paperdoll_layers as pl  # noqa: E402
import slice_sheets as ss  # noqa: E402

BODY = os.path.join(pl.ROOT, "art", "source", "paperdoll_body.png")
MAGENTA = (255, 0, 255)
GREEN = (0, 255, 0)
BLADE = 1.4      # the rod reaches this far past the grip on the blade side (head radii)
POMMEL = 0.45    # and this far on the pommel side
THICK = 0.13     # rod thickness (head radii)
ROD_EDGE = 3     # pixels around the rod that are its outline, painted over with it
BG_NEAR = 60     # colour distance (summed RGB) that counts as background, reached from the border
BG_EXACT = 30    # and anywhere
HAND = 0.55      # the hand taken from the edit reaches this far from the grip (head radii)
# Gemini's tan shadowed leg is turned this far toward his skin's hue (0-1), keeps this much of
# its saturation and is lightened by this much: a soft shade of his skin.
SHADE_HUE, SHADE_SAT, SHADE_VALUE = 0.07, 0.75, 1.08
# Cells the guide leaves alone: the run cells get their rods in their own edit (they were
# redrawn, see gemini_pass.json paperdoll_body_run_2), and FAINT 1's sword falls out of
# his cell.
SKIP = ("run1", "run2", "run3", "run4", "faint1")


def layout():
    """The body sheet's grid: {cell name: (x0, y0, x1, y1)}."""
    with open(os.path.join(ss.SHEETS, "paperdoll_body.json")) as f:
        man = json.load(f)
    rows, cols = man["grid"]["rows"], man["grid"]["cols"]
    return {c: (cols[j], rows[i], cols[j + 1], rows[i + 1])
            for i, line in enumerate(man["cells"]) for j, c in enumerate(line)}


def rig():
    """(frame names, frame -> body cell, frame -> (dx, dy) from cell to strip, the rig's hands,
    strip pixels per rig pixel, head radius in strip pixels)."""
    names, spec = pl.frame_names()
    strip = Image.open(pl.STRIP)
    fw, fh = strip.width // len(names), strip.height
    hands, _ = pl.hand_rig(fw)
    cells = {n: spec["frames"][n].split(":", 1)[1] for n in names}
    offsets = pl.body_offsets(names, cells, fw, fh)
    with open(pl.HAND_RIG) as f:
        k = fw / json.load(f).get("frame_size", [fw])[0]
    r = pl.analyse(np.asarray(strip.crop((0, 0, fw, fh))))["r"]
    return names, cells, offsets, hands, k, r


def grips():
    """Per body cell that holds a weapon (except SKIP): (the grip in body sheet pixels, the
    sword's angle), and the head radius."""
    names, cells, offsets, hands, _, r = rig()
    boxes = layout()
    out = {}
    for n in names:
        c = cells[n]
        if "weapon" not in hands[n] or c in out or c in SKIP:
            continue
        x, y, angle = hands[n]["weapon"]
        dx, dy = offsets[n]
        out[c] = ((boxes[c][0] + x - dx, boxes[c][1] + y - dy), angle)
    return out, r


def guide(path):
    sheet = Image.open(BODY).convert("RGB")
    draw = ImageDraw.Draw(sheet)
    found, r = grips()
    for (x, y), angle in found.values():
        c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
        a = (x - c * r * POMMEL, y - s * r * POMMEL)
        b = (x + c * r * BLADE, y + s * r * BLADE)
        draw.line([a, b], fill=GREEN, width=max(3, round(r * THICK)))
    sheet.save(path)
    print(f"guide: {path} ({len(found)} rods)")


def rod_mask(arr):
    """The guide rod's pixels: anything clearly green, dark shading included (nothing else on
    the hero is green)."""
    rgb = arr[..., :3].astype(int)
    return (rgb[..., 1] > rgb[..., 0] + 30) & (rgb[..., 1] > rgb[..., 2] + 30)


def softened(rgb):
    """Gemini paints the leg and arm he has in shadow tan-brown rather than shaded skin: those
    pixels (skin more saturated and darker than his lit skin) are brought back toward peach."""
    hsv = _hsv(rgb)
    skin = (hsv[..., 0] < 0.12) & (hsv[..., 1] > 0.15) & (hsv[..., 2] > 0.6)
    lit = skin & (hsv[..., 2] > 0.93)
    if not lit.any():
        return rgb
    tan = skin & (hsv[..., 1] > np.median(hsv[lit][:, 1]) + 0.15) & (hsv[..., 2] < 0.93)
    hsv[tan, 0] = (hsv[tan, 0] + SHADE_HUE) / 2
    hsv[tan, 1] *= SHADE_SAT
    hsv[tan, 2] = np.minimum(1.0, hsv[tan, 2] * SHADE_VALUE)
    out = rgb.copy()
    out[tan] = _rgb(hsv[tan])
    return out


def _hsv(rgb):
    a = rgb.astype(float) / 255
    mx, mn = a.max(-1), a.min(-1)
    d = mx - mn
    safe = np.where(d > 1e-6, d, 1)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    h = np.where(mx == r, ((g - b) / safe) % 6, np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4)) / 6
    return np.stack([np.where(d > 1e-6, h, 0), np.where(mx > 0, d / np.maximum(mx, 1e-6), 0), mx], -1)


def _rgb(hsv):
    h, s, v = hsv[..., 0] * 6, hsv[..., 1], hsv[..., 2]
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    rgb = np.stack([np.choose(i, [v, q, p, p, t, v]), np.choose(i, [t, v, v, q, p, p]), np.choose(i, [p, p, t, v, v, q])], -1)
    return (rgb * 255).round().clip(0, 255).astype(np.uint8)


def solid(arr, box):
    """The cell `box` of an RGB sheet as RGBA, its background clear. Gemini doesn't always keep
    the magenta (some edits come back pink-grey, near his skin), so the background is whatever
    colour the cell's border has, reaching in from the border; gaps it can't reach (between an
    arm and his body) only where they match it closely."""
    x0, y0, x1, y1 = box
    cell = arr[y0:y1, x0:x1, :3].astype(int)
    border = np.concatenate([cell[2], cell[-3], cell[:, 2], cell[:, -3]])
    dist = np.abs(cell - np.median(border, 0)).sum(2)
    lab, _ = ss.label(dist < BG_NEAR)
    edge = np.unique(np.concatenate([lab[:3].ravel(), lab[-3:].ravel(), lab[:, :3].ravel(), lab[:, -3:].ravel()]))
    bg = np.isin(lab, edge[edge > 0]) | (dist < BG_EXACT)
    out = np.zeros(cell.shape[:2] + (4,), np.uint8)
    out[..., :3] = cell
    out[..., 3] = np.where(bg, 0, 255)
    return out


def measure(rod):
    """A rod's grip (the middle of the gap the fist makes in it) and the way its long end
    points (degrees clockwise from pointing right), from its pixels; None if it has no gap."""
    ys, xs = np.nonzero(rod)
    if len(xs) < 20:
        return None
    pts = np.stack([xs, ys], 1).astype(float)
    centre = pts.mean(0)
    _, _, vt = np.linalg.svd(pts - centre, full_matrices=False)
    axis = vt[0]
    t = np.sort((pts - centre) @ axis)
    gaps = np.diff(t)
    i = int(np.argmax(gaps))
    if gaps[i] < 3:
        return None
    mid = (t[i] + t[i + 1]) / 2
    grip = centre + axis * mid
    if t[-1] - mid < mid - t[0]:  # the long end is the blade's
        axis = -axis
    return (float(grip[0]), float(grip[1])), math.degrees(math.atan2(axis[1], axis[0]))


def _sheet(path, size):
    img = Image.open(path).convert("RGB")
    if img.size != size:
        img = img.resize(size, Image.LANCZOS)
    return np.asarray(img).copy()


def hands(path, whole=(), rods_path=None):
    boxes = layout()
    body = np.asarray(Image.open(BODY).convert("RGB")).copy()
    size = (body.shape[1], body.shape[0])
    edit = _sheet(path, size)
    rods = rod_mask(_sheet(rods_path, size) if rods_path else edit)
    painted = np.dstack([edit, np.full(edit.shape[:2], 255, np.uint8)])
    pl.inpaint(painted, ss.dilate(rod_mask(edit), ROD_EDGE))  # in place: the edit's own rods
    painted = painted[..., :3]

    # cells the edit redrew whole: copied over, rod painted out, background made pure magenta
    for c in whole:
        x0, y0, x1, y1 = boxes[c]
        cell = solid(painted, boxes[c])
        cell[..., :3] = softened(cell[..., :3])
        body[y0:y1, x0:x1] = np.where(cell[..., 3:] > 0, cell[..., :3], MAGENTA)
    Image.fromarray(body).save(BODY)

    names, cells, offsets, hands_rig, k, r = rig()
    taken = []
    measured = {}
    for c, box in boxes.items():
        if whole and c not in whole:  # an edit of whole cells may have stray rods elsewhere
            continue
        x0, y0, x1, y1 = box
        found = measure(rods[y0:y1, x0:x1])
        if found is None:
            continue
        (gx, gy), angle = found
        measured[c] = ((gx, gy), angle)
        new = solid(painted, box)
        old = solid(body, box)
        hand = pl.fist_mask(new, (gx, gy), r * HAND)
        gone = pl.fist_mask(old, (gx, gy), r * HAND) & ~hand
        cell = body[y0:y1, x0:x1]
        cell[hand] = new[hand][:, :3]
        cell[gone] = MAGENTA
        taken.append(c)
    Image.fromarray(body).save(BODY)
    print(f"hands: {len(taken)} cells ({', '.join(taken)}) -> {os.path.relpath(BODY, pl.ROOT)}")

    if whole:
        # the redrawn cells hold the weapon where the edit's rod goes: what to put in the rig
        names, cells, offsets, _, k, _ = rig()
        for n in names:
            if cells[n] in whole and cells[n] in measured:
                (gx, gy), angle = measured[cells[n]]
                dx, dy = offsets[n]
                print(f"{n}: \"weapon\": [{round((gx + dx) / k)}, {round((gy + dy) / k)}, {round(angle / 5) * 5}]"
                      f" (set it in {os.path.relpath(pl.HAND_RIG, pl.ROOT)})")

# Close-ups: Gemini leaves the hands alone when asked to edit the whole 32-pose sheet, but
# redraws a hand round a rod when it is big in the picture. Each close-up shows a few weapon
# hands from the guide, each in its own square panel, ZOOM times bigger.
GROUPS = (("idle1", "idle2", "idle3", "idle4", "walk1"), ("walk2", "walk3", "walk4", "hit", "hurt"),
          ("attack1", "attack2", "slash1", "slash2", "slash3"), ("jump", "fall", "land", "crouch", "levelup"))
PANEL = 1.0      # a panel reaches this far from the grip each way (head radii)
ZOOM = 3
GAP = 24         # magenta between panels (close-up pixels)


def _panel(r):
    return 2 * round(r * PANEL)


def _handlike(arr):
    """Skin and dark outline: what a hand is made of (not his grey shorts or undershirt, which
    a flood from the fist can reach where no outline parts them)."""
    rgb = arr[..., :3].astype(int)
    skin = (rgb[..., 0] > rgb[..., 2] + 30) & (rgb[..., 0] > 120)
    return skin | (rgb.max(2) < 110)


def _pinkish(arr):
    """Edge pixels blended with the magenta background (kept out of a pasted hand)."""
    rgb = arr[..., :3].astype(int)
    return (rgb[..., 2] > rgb[..., 1] + 40) & (rgb[..., 0] > rgb[..., 1] + 40)


def closeups(out_dir, guide_path):
    """Writes closeup_<n>.png from the guide image, one per GROUPS entry."""
    found, r = grips()
    sheet = Image.open(guide_path).convert("RGB")
    p = _panel(r)
    os.makedirs(out_dir, exist_ok=True)
    for n, group in enumerate(GROUPS, 1):
        img = Image.new("RGB", (len(group) * (p * ZOOM + GAP) + GAP, p * ZOOM + 2 * GAP), MAGENTA)
        for i, c in enumerate(group):
            (x, y), _ = found[c]
            crop = sheet.crop((round(x) - p // 2, round(y) - p // 2, round(x) + p // 2, round(y) + p // 2))
            img.paste(crop.resize((p * ZOOM, p * ZOOM), Image.LANCZOS), (GAP + i * (p * ZOOM + GAP), GAP))
        path = os.path.join(out_dir, f"closeup_{n}.png")
        img.save(path)
        print(f"close-up: {path} ({', '.join(group)})")


def closeup_hands(paths, only=None):
    """Puts the hands from edited close-ups (closeup_<n>.png results, in GROUPS order) on the
    body sheet: every cell's, or the cells in `only` (where the edit really redrew the hand)."""
    found, r = grips()
    p = _panel(r)
    body = np.asarray(Image.open(BODY).convert("RGB")).copy()
    taken = []
    for group, path in zip(GROUPS, paths):
        size = (len(group) * (p * ZOOM + GAP) + GAP, p * ZOOM + 2 * GAP)
        edit = _sheet(path, size)
        for i, c in enumerate(group):
            if only and c not in only:
                continue
            x0 = GAP + i * (p * ZOOM + GAP)
            panel = Image.fromarray(edit[GAP:GAP + p * ZOOM, x0:x0 + p * ZOOM]).resize((p, p), Image.LANCZOS)
            arr = np.asarray(panel).copy()
            rod = ss.dilate(rod_mask(arr), 2)
            arr[rod] = 0  # the rod is outline-dark to the flood; the body keeps what is under it
            new = solid(arr, (0, 0, p, p))
            hand = pl.fist_mask(new, (p / 2, p / 2), r * HAND) & _handlike(new) & ~_pinkish(new) & ~rod
            (x, y), _ = found[c]
            bx, by = round(x) - p // 2, round(y) - p // 2
            region = body[by:by + p, bx:bx + p]
            olds = solid(region, (0, 0, p, p))
            old = pl.fist_mask(olds, (p / 2, p / 2), r * HAND) & _handlike(olds)
            # outline pixels the zoom blended with the background: given the old fist's outline colour
            fringe = hand & (new[..., :3].max(2) < 150) & (new[..., 2].astype(int) > new[..., 1].astype(int) + 15)
            ink = old & (olds[..., :3].max(2) < 90)
            if ink.any():
                new[fringe, :3] = np.median(olds[ink][:, :3], 0)
            region[hand] = new[hand][:, :3]
            # the old fist where the edit has background now (the new fist is smaller there)
            outside = old & ~hand & ~rod & (new[..., 3] == 0)
            region[outside] = MAGENTA
            taken.append(c)
    Image.fromarray(body).save(BODY)
    print(f"close-up hands: {len(taken)} cells -> {os.path.relpath(BODY, pl.ROOT)}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) >= 2 and args[0] == "guide":
        guide(args[1])
    elif len(args) >= 2 and args[0] == "hands":
        cells = args[args.index("--cells") + 1].split(",") if "--cells" in args else ()
        hands(args[1], cells, args[args.index("--rods") + 1] if "--rods" in args else None)
    elif len(args) >= 3 and args[0] == "closeups":
        closeups(args[1], args[2])
    elif len(args) >= 2 and args[0] == "closeup-hands":
        only = args[args.index("--only") + 1].split(",") if "--only" in args else None
        closeup_hands([a for i, a in enumerate(args[1:], 1) if a != "--only" and args[i - 1] != "--only"], only)
    else:
        sys.exit(__doc__)
