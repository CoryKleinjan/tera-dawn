"""Gloves: lifted off a sheet of the body wearing them in every pose and set on the hero's
hands (the rig's grip and shield points), at the size the drawn body is to his (the tinted
gloves of an item without art of its own); an item's own gloves are pieces (glove_pieces)."""
from .common import *  # noqa: F401,F403
from .common import _paste
from .body import body_fit
from .worn import worn_mask
from .pieces import pose, save_fist, save_piece


# ---------- an item's own gloves: pieces ----------

GLOVE_SHEET = "glove_mittens"


def hand_points(hero, n, entry):
    """Where his hands are in frame `n`: the rig's weapon fist and shield point, or the hand
    rig's own hand points where those aren't his hands (paperdoll_rig.json "hands")."""
    if "hands" in hero.hands.get(n, {}):
        return hero.hands[n]["hands"]
    if n in BACK_VIEW:
        return []
    return [entry[k] for k in ("grip", "shield") if k in entry]


def hand_at(px, point, r):
    """His mitten hand nearest `point` in a frame: (its pixels, its middle, the way his forearm
    points into it in degrees clockwise from pointing right, or None). The hand is the skin
    found within GLOVE_FIND of the point and within GLOVE_HAND of it; the forearm is the skin
    joined to it further out."""
    a = px.astype(int)
    solid = a[..., 3] > 127
    skin = solid & (a[..., 0] > 170) & (a[..., 0] > a[..., 2] + 30)
    yy, xx = np.mgrid[0:px.shape[0], 0:px.shape[1]]
    near = (xx - point[0]) ** 2 + (yy - point[1]) ** 2
    lab, n = ss.label(skin & (near <= (GLOVE_FIND * r) ** 2))
    if not n:
        return None
    limb = lab == 1 + int(np.argmin([near[lab == i].min() for i in range(1, n + 1)]))
    hand = limb & (near <= (GLOVE_HAND * r) ** 2)
    if not hand.any():
        return None
    ys, xs = np.nonzero(hand)
    mid = np.array([xs.mean(), ys.mean()])
    arm = limb & (near > (GLOVE_HAND * r) ** 2)
    angle = None
    if arm.sum() >= 5:
        ay, ax = np.nonzero(arm)
        angle = math.degrees(math.atan2(mid[1] - ay.mean(), mid[0] - ax.mean()))
    return hand, mid, angle


def glove_pieces(hero, rig_frames):
    """Writes glove_item_<id>_1 and _2 for every glove on glove_mittens.json (one painted
    mitten per glove, drawn from its icon: cuff down, fist up): the mitten on each of his
    hands (hand_points), turned so its cuff points back along his forearm, over his body;
    and fist_glove_1/_2.png, which cut each mitten where the rest of his body is in front of
    that hand, so a hand behind him stays behind him (Cory 2026-10-11: all equipment is
    layered; gloves are mittens in the glove's colours)."""
    if not os.path.exists(os.path.join(ss.SHEETS, GLOVE_SHEET + ".json")):
        return
    r = hero.r
    mittens = {item: p.img for item, p in cut(GLOVE_SHEET).items()}
    hands = [[None] * len(hero.names) for _ in range(2)]
    masks = [[None] * len(hero.names) for _ in range(2)]
    for i, (n, px, entry) in enumerate(zip(hero.names, hero.frames, rig_frames)):
        solid = px[..., 3] > 127
        for h, point in enumerate(hand_points(hero, n, entry)[:2]):
            found = hand_at(px, point, r)
            if found is None:
                continue
            hand, mid, angle = found
            # facing right with no forearm in sight, his fist points the way he faces
            hands[h][i] = (mid, 90.0 + (0.0 if angle is None else angle))
            masks[h][i] = solid & ~ss.dilate(hand, GLOVE_OVER)
    for h in range(2):
        save_fist(f"glove_{h + 1}", masks[h], hero.fw, hero.fh)
    for item, img in mittens.items():
        pic = scaled(img, GLOVE_SIZE * r / img.width)
        for h in range(2):
            frames = [None if e is None else pose("hand", e[0], e[1], fist=True) for e in hands[h]]
            save_piece(f"glove_item_{item}_{h + 1}", {"hand": (pic, (pic.width / 2, pic.height / 2))},
                       frames, fist=f"glove_{h + 1}")


# ---------- gloves drawn on the body ----------

def posed_gloves(arr, px, hands, reach, keep_colour=False):
    """The two gloves of one drawn pose, sized to the hero, each centred on a hand of his: the
    glove drawn nearest to it on the fitted body (first within `reach`, then any). Returns
    [(image, top-left)]. With `keep_colour`, `arr` is already only the gloves (an item's own
    coloured sheet, see items.py) and they keep their colours."""
    ys = np.nonzero(arr[..., 3] > 0)[0]
    ours = np.nonzero(px[..., 3] > 127)[0]
    base = (ours.max() - ours.min() + 1) / (ys.max() - ys.min() + 1)
    s, x, y = body_fit(arr, np.zeros(arr.shape[:2], bool), px, [base * k for k in (0.92, 0.96, 1.0, 1.04, 1.08)])
    mask = (arr[..., 3] > 0) if keep_colour else worn_mask(arr)
    lab, n = ss.label(mask)
    if not n:
        return []
    # each hand takes the nearest sizeable piece that sits near it on the fitted body (a
    # piece of shirt or a stray outline elsewhere stays behind)
    sizes = np.bincount(lab.ravel())[1:]
    centres = {}
    for i in np.nonzero(sizes >= max(sizes.max() * 0.15, 8))[0]:
        gy, gx = np.nonzero(lab == i + 1)
        if max(np.ptp(gy), np.ptp(gx)) * s <= reach:  # glove-sized
            centres[i] = np.array([x + gx.mean() * s, y + gy.mean() * s])
    # each hand takes the nearest glove that sits near it; a hand left without one (the sheet's
    # body is posed a little unlike his, so its hands sit elsewhere) then takes the nearest one
    # left anywhere, and failing that a copy of the other hand's
    pick = {}
    for limit in (reach, np.inf):
        for h, hand in enumerate(hands):
            if h in pick:
                continue
            near = sorted((np.hypot(*(c - hand)), i) for i, c in centres.items())
            if near and near[0][0] <= limit:
                pick[h] = near[0][1]
                del centres[near[0][1]]
    for h in range(len(hands)):
        if h not in pick and pick:
            pick[h] = next(iter(pick.values()))
    out = []
    for h, hand in enumerate(hands):
        if h not in pick:
            continue
        i = pick[h]
        gy, gx = np.nonzero(lab == i + 1)
        y0, y1, x0, x1 = gy.min(), gy.max() + 1, gx.min(), gx.max() + 1
        part = lab[y0:y1, x0:x1] == i + 1
        cut = arr[y0:y1, x0:x1].copy()
        cut[~part] = 0
        if not keep_colour:
            grey = cut[..., :3].mean(2, keepdims=True)
            cut[..., :3] = np.repeat(grey, 3, 2).round().astype(np.uint8)
        img = scaled(Image.fromarray(cut, "RGBA"), s)
        out.append((img, (int(round(hand[0] - img.width / 2)), int(round(hand[1] - img.height / 2)))))
    return out


def glove_layers(hero, rig_frames):
    """Writes the gloves layer, if there is a gloves_frames sheet."""
    names, frames, spec, index, anims = hero.names, hero.frames, hero.spec, hero.index, hero.anims
    fw, fh, r, blank = hero.fw, hero.fh, hero.r, hero.blank
    # gloves, on both hands
    if os.path.exists(os.path.join(ss.SHEETS, "gloves_frames.json")):
        drawn = cut("gloves_frames")
        out = []
        for n, px, entry in zip(names, frames, rig_frames):
            canvas = blank()
            cell = drawn.get(spec["frames"][n].split(":", 1)[1])
            points = [entry[k] for k in ("grip", "shield") if k in entry]
            if cell and points and n not in BACK_VIEW:  # climbing: his hands are off the rig's points
                for img, at in posed_gloves(np.asarray(cell.img), px, points, r * GLOVE_REACH):
                    _paste(canvas, img, *at)
            out.append(canvas)
        save_layer("gloves", out, fw, fh, index, anims)
