"""Weapons: each weapon kind (and each weapon with its own held picture) measured, cleaned
of its grip dots and put in his fist on every frame, or on his back while he climbs or sits."""
from collections import deque

from .common import *  # noqa: F401,F403


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


# ---------- building the weapon layers ----------

def weapon_layers(hero, weapons, held):
    """Writes weapon_<kind> (+ _behind) for every kind, and weapon_item_<id> for every weapon
    with its own held picture. Returns each one's grip entry for the rig (by kind, or by
    item_<id>)."""
    names, info, frames, index, anims = hero.names, hero.info, hero.frames, hero.index, hero.anims
    fw, fh, r, hands, hold_spec = hero.fw, hero.fh, hero.r, hero.hands, hero.hold_spec
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
    return grips
