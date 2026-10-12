"""Weapons: each weapon kind (and each weapon with its own held picture) measured, cleaned
of its grip dots and put in his fist on every frame, or on his back while he climbs or sits."""
from collections import deque

from .common import *  # noqa: F401,F403
from .pieces import pose, save_fist, save_piece

BOW_TIP = 0.08  # bow_parts: the share of a bow's height at each end that counts as its tip


# ---------- weapons ----------

def weapon(piece, s, kind):
    """A weapon shrunk to game pixels, its green grip dots painted out; returns (image, grip,
    axis): axis is the way its business end points in the picture (degrees clockwise from
    pointing right), 0 for kinds not in AXIAL. Where his fist goes (see grip_point) is
    worked out from the weapon's shape for blades, wands, staffs and guns, since the sheets'
    dots are often off (on a crossguard, several for two hands, or none). A gun painted with
    its barrel slanting is turned level first, like the gun template."""
    img = piece.img
    if kind == "gun":
        img = img.rotate(barrel_tilt(np.asarray(img)), resample=Image.BICUBIC, expand=True)
        img = img.crop(img.getbbox())
    arr = np.asarray(img).astype(int)
    green = (arr[..., 1] > 170) & (arr[..., 0] < 120) & (arr[..., 2] < 120) & (arr[..., 3] > 0)
    opaque = arr[..., 3] > 0
    # dots drawn off the weapon (beside it on the background, as some held_* sheets have
    # them) are islands of their own: dropped with their outline and soft edge, and don't
    # count (the islands are found on the solid art, as the soft edge can join them up)
    parts, n = ss.label(arr[..., 3] > 127)
    if n > 1:
        sizes = np.bincount(parts.ravel())[1:]
        main = int(sizes.argmax()) + 1
        for i in range(1, n + 1):
            if i != main and green[parts == i].any():
                arr[ss.dilate(parts == i, 2) & (parts != main), 3] = 0
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


def barrel_tilt(arr):
    """The slant of a gun's barrel (degrees clockwise from pointing right): the line along the
    top of its front part (BARREL_FRONT of its width, toward the muzzle on the right)."""
    solid = arr[..., 3] > 0
    cols = np.nonzero(solid.any(0))[0]
    xs = np.arange(int(cols.min() + (cols.max() - cols.min()) * (1 - BARREL_FRONT)), cols.max())
    tops = np.array([np.nonzero(solid[:, x])[0].min() for x in xs])
    return round(math.degrees(math.atan(np.polyfit(xs, tops, 1)[0])), 1)


def grip_point(arr, kind, axis, dots):
    """Where his fist closes on a weapon picture (its pixels):
    - a blade (sword kind): in the middle of the handle, between the pommel and the crossguard
      (the first place, going up from the pommel, that gets much wider than the handle);
    - a wand: halfway along the shaft; a staff: low on its handle (STAFF_GRIP along it);
    - a gun: in the middle of the pistol grip (the part hanging below the barrel at the back);
    - a claw: in the middle of its cuff (CLAW_CUFF along it), so the cuff covers his fist;
    - a bow: on its riser, halfway up (bow_parts), so it is held by the middle;
    - anything else (knuckles): its dot, or a guess near its back end."""
    if kind == "bow":
        return bow_parts(arr)[0]
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
    if kind == "wand":
        return _on_axis(arr, axis, lo + span / 2)
    if kind == "staff":
        return _on_axis(arr, axis, lo + span * STAFF_GRIP)
    if kind == "claw":
        # the middle of the cuff, so the cuff covers his fist and the blades reach past it
        return _on_axis(arr, axis, lo + span * CLAW_CUFF)
    if kind == "gun":
        # the middle of the pistol grip: what hangs below the barrel's underside (the lowest
        # row of its front part) at the back, so his whole fist wraps the grip
        solid = arr[..., 3] > 0
        cols = np.nonzero(solid.any(0))[0]
        front = cols[cols > cols.min() + (cols.max() - cols.min()) * (1 - GUN_FRONT)]
        under = np.median([np.nonzero(solid[:, x])[0].max() for x in front])
        grip = (ys > under) & (xs < cols.min() + (cols.max() - cols.min()) * GUN_BACK)
        if grip.any():
            return (float(xs[grip].mean()), float(ys[grip].mean()))
    c, s = math.cos(math.radians(axis)), math.sin(math.radians(axis))
    if dots:
        return min(dots, key=lambda d: d[0] * c + d[1] * s)  # the back hand
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
    string on the left, like the bow template, so its belly faces where he shoots. A bow drawn
    at a slant is turned upright, and one with its string on the right (its tips curving that
    way, see bow_parts) is mirrored; one already standing up that way is kept as it is."""
    img = piece.img
    axis = drawn_axis(np.asarray(img))
    if abs(axis + 90) > UPRIGHT_SLACK:
        img = img.rotate(axis + 90, resample=Image.BICUBIC, expand=True)
        img = img.crop(img.getbbox())
    riser, tips_x = bow_parts(np.asarray(img))
    if tips_x > riser[0]:
        img = ImageOps.mirror(img)
    if img is piece.img:
        return piece
    out = copy.copy(piece)
    out.img = img
    return out


def bow_parts(arr):
    """An upright bow picture's riser, where his fist closes on it: (x, y) in the middle of its
    height, on the widest run of pixels across that row (the bow itself, not its string); and
    the mean x of its two tips, which curve toward the string's side."""
    solid = arr[..., 3] > 127
    rows = np.nonzero(solid.any(1))[0]
    top, bottom = int(rows.min()), int(rows.max())
    mid, end = (top + bottom) // 2, max(1, round((bottom - top) * BOW_TIP))
    band = np.concatenate([[False], solid[max(0, mid - 3):mid + 4].any(0), [False]])
    edges = np.flatnonzero(np.diff(band.astype(int)))
    runs = list(zip(edges[::2], edges[1::2]))
    start, stop = max(runs, key=lambda r: r[1] - r[0])
    tips = [np.nonzero(solid[top:top + end])[1].mean(), np.nonzero(solid[bottom - end + 1:bottom + 1])[1].mean()]
    return ((start + stop - 1) / 2, float(mid)), float(np.mean(tips))


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


# Frames where he holds no weapon, in his hand or on his back.
EMPTY_HANDED = ("levelup",)


def holds(hands, spec, names, forearms=None):
    """Per weapon kind, per frame: [x, y, angle] of the fist and the weapon in it (the sword's
    are the hand-placed "weapon" points; a kind's own [x, y, angle] puts it in his hand on any
    frame), or None when the weapon isn't in his hand (on his back: ON_BACK). A kind
    with "along": "forearm" points the way his forearm does (`forearms`, from forearm_angles)."""
    out = {"sword": {n: hands[n].get("weapon") for n in names}}
    # a "sword" entry turns the hand-placed blade (held at one tilt while he stands, walks and
    # runs, swaying a little), keeping where the fist is; [x, y, angle] moves the fist too
    # (placing it even on a frame with no "weapon" point, such as sit)
    for n, v in spec.get("sword", {}).get("frames", {}).items():
        if isinstance(v, list):
            out["sword"][n] = [round(float(c), 1) for c in v]
        elif out["sword"].get(n) is not None:
            out["sword"][n] = [out["sword"][n][0], out["sword"][n][1], v]

    def resolve(kind):
        if kind not in out:
            h = spec.get(kind, {"like": "sword"})
            base = resolve(h["like"]) if "like" in h else out["sword"]
            frames = {}
            for n in names:
                v = h.get("frames", {}).get(n, h.get("angle"))
                if isinstance(v, list):  # [x, y, angle]: in his fist there, even where the sword has none
                    frames[n] = [round(float(c), 1) for c in v]
                    continue
                if h.get("along") == "forearm" and forearms and forearms.get(n) is not None:
                    v = forearms[n]
                if base[n] is None:
                    frames[n] = None
                else:
                    frames[n] = [base[n][0], base[n][1], base[n][2] if v is None else v]
            out[kind] = frames
        return out[kind]

    for kind in WEAPON_KINDS:
        resolve(kind)
    for kind in out:  # no weapon at all while he levels up (Cory 2026-10-12), whatever a kind's line says
        for n in EMPTY_HANDED:
            if n in out[kind]:
                out[kind][n] = None
    return out


def forearm_angles(hero):
    """The way his forearm points on each frame with a weapon fist (degrees clockwise from
    pointing right, from the elbow out through the fist): the skin joined to the fist, within
    about a head radius of it, and the fist itself left out; None where too little shows."""
    out = {}
    for n, px, fi in zip(hero.names, hero.frames, hero.info):
        hold = hero.hands[n].get("weapon")
        if hold is None:
            out[n] = None
            continue
        gx, gy = hold[0], hold[1]
        h, w = px.shape[:2]
        yy, xx = np.mgrid[0:h, 0:w]
        dist = np.hypot(xx - gx, yy - gy)
        ok = (fi["region"] == R["skin"]) & (px[..., 3] > 127) & (dist <= hero.r * FOREARM)
        if not ok.any():
            out[n] = None
            continue
        sy, sx = np.unravel_index(np.argmin(np.where(ok, dist, np.inf)), ok.shape)
        seen = np.zeros(ok.shape, bool)
        seen[sy, sx] = True
        todo = deque([(sy, sx)])
        while todo:
            y, x = todo.popleft()
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and ok[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    todo.append((ny, nx))
        ys, xs = np.nonzero(seen & (dist > hero.r * FIST))
        out[n] = round(math.degrees(math.atan2(gy - ys.mean(), gx - xs.mean())), 1) if len(xs) >= 5 else None
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


def weapon_poses(img, axis, kind, names, info, hold, hands, far_frames=(), palm_frames=()):
    """Where a weapon picture goes on every frame (pieces.pose(), or None): in his fist turned
    the way the rig holds it, behind him in his far hand (or in `far_frames`: a long staff
    planted beside him would otherwise cover his face), or on his back while he climbs or sits.
    His fingers show over the grip of a GRIPPED kind held in front (fist_<kind>.png), except on
    `palm_frames`, where we see the inside of his hand and the weapon lies over it."""
    out = []
    for n, fi in zip(names, info):
        if hold[n] is not None:
            x, y, angle = hold[n]
            far = hands[n].get("weapon_behind", False) or n in far_frames
            out.append(pose("held", (x, y), angle - axis, behind=far, fist=kind in GRIPPED and not far and n not in palm_frames))
        elif kind in ON_BACK and n in SHEATHED:
            at = fi["neck"] - fi["up"] * fi["r"] * 0.3
            out.append(pose("back", at, ON_BACK[kind] - axis, behind=n not in BACK_VIEW))
        else:
            out.append(None)
    return out


def fist_masks(hero, held):
    """Writes fist_<kind>.png for every GRIPPED kind: his fingers around its grip, on the
    frames where it is in his near hand."""
    names, frames, hands, r = hero.names, hero.frames, hero.hands, hero.r
    for kind in GRIPPED:
        far_frames = hero.hold_spec.get(kind, {}).get("behind", ())
        palm_frames = hero.hold_spec.get(kind, {}).get("palm", ())
        # a kind gripped at the middle of his fist can keep its mask to the fist alone ("fist", in
        # head radii), so it doesn't spill onto his chest and cut the weapon out where his shirt is
        reach = r * hero.hold_spec.get(kind, {}).get("fist", FIST)
        masks = []
        for n, px in zip(names, frames):
            h = held[kind][n]
            far = hands[n].get("weapon_behind", False) or n in far_frames or n in palm_frames
            masks.append(None if h is None or far else fist_mask(px, h[:2], reach))
        save_fist(kind, masks, hero.fw, hero.fh)


def held_pictures():
    """(item id, weapon kind, piece, sheet, size) for every weapon item: its icon, cut at full
    size from its items_*.json sheet; size is the item's EquipDef.held_size."""
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
        if not (f.startswith(ICON_SHEETS) and f.endswith(".json")):
            continue
        for item, piece in icon_cut(f[:-5], set(kinds)).items():
            out.append((item, kinds[item][0], piece, f[:-5], kinds[item][1]))
    missing = set(kinds) - {o[0] for o in out}
    if missing:
        sys.exit(f"no icon cell for weapon(s) {sorted(missing)}")
    return out


def icon_cut(sheet, wanted):
    """The `wanted` cells of an item icon sheet, cut at the sheet's full size (the manifest's
    scale is for the bag icons) and not saved; {} when the sheet has none of them."""
    with open(os.path.join(ss.SHEETS, sheet + ".json")) as fh:
        man = json.load(fh)
    cells = [[c if c in wanted else "" for c in row] for row in man["cells"]]
    if not any(any(row) for row in cells) or not os.path.exists(os.path.join(ROOT, man["source"])):
        return {}
    # full size, with the soft edge like the other hero layers
    man.update(cells=cells, scale=1.0, detail=1, save=False,
               out_dir=os.path.join("art", "build", "paperdoll", sheet))
    tmp = os.path.join(ROOT, "art", "build", "paperdoll", f"held_{sheet}.json")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    with open(tmp, "w") as fh:
        json.dump(man, fh)
    sprites = {}
    ss.process(tmp, sprites=sprites)
    return {k.split(":", 1)[1]: Piece(v) for k, v in sprites.items()}


# ---------- building the weapon layers ----------

def weapon_layers(hero, weapons, held):
    """Writes the piece weapon_<kind> (greyscale, tinted) for every kind and weapon_item_<id> for
    every weapon, from its icon (pieces.py), and the fist masks. Returns each one's grip entry for the rig (by kind, or by
    item_<id>)."""
    names, info, r, hands, hold_spec = hero.names, hero.info, hero.r, hero.hands, hero.hold_spec
    # weapons: every kind (greyscale, tinted per item) and every weapon with its own picture
    s_w = r * SWORD_LENGTH / length(weapons["sword"], "sword")
    grips = {}
    pictures = [(kind, kind, weapons[kind], True, 1.0) for kind in WEAPON_KINDS]
    # (a bow drawn at a slant is stood up first, so it is measured and held as the rig expects)
    drawn_weapons = [(item, kind, stood_up(piece) if kind in UPRIGHT else piece, sheet, size)
                     for item, kind, piece, sheet, size in held_pictures()]
    # an icon sheet is drawn at its own size: it is shrunk so each kind of weapon on it is, on
    # the median, as long as the template of its kind (keeping their sizes against each other;
    # a sheet draws its wands and staffs at the same icon size, but a staff is far longer)
    by_sheet = {}
    # (and then grown or shrunk by the item's own held_size: a claymore longer than a sword)
    for item, kind, piece, sheet, _ in drawn_weapons:
        by_sheet.setdefault((sheet, kind), []).append(length(weapons[kind], kind) / length(piece, kind))
    pictures += [("item_" + item, kind, piece, False, float(np.median(by_sheet[sheet, kind])) * size)
                 for item, kind, piece, sheet, size in drawn_weapons]
    for name, kind, piece, tinted, k in pictures:
        img, grip, axis = weapon(piece, s_w * WORN_SIZE.get(kind, 1.0) * k, kind)
        entry = {"grip": grip, "size": list(img.size), "reach": reach(img, grip, axis),
                 "kind": kind, "grip_share": grip_share(img, grip, axis), "dots_left": dots_left(img)}
        grips[kind if tinted else name] = entry
        far_frames = hold_spec.get(kind, {}).get("behind", ())
        palm_frames = hold_spec.get(kind, {}).get("palm", ())
        poses = weapon_poses(img, axis, kind, names, info, held[kind], hands, far_frames, palm_frames)
        middle = (img.width / 2, img.height / 2)
        save_piece(f"weapon_{name}", {"held": (img, grip), "back": (img, middle)}, poses, tinted,
                   kind if kind in GRIPPED else None)
    fist_masks(hero, held)
    return grips
