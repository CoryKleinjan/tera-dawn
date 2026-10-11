"""Gloves: lifted off a sheet of the body wearing them in every pose and set on the hero's
hands (the rig's grip and shield points), at the size the drawn body is to his."""
from .common import *  # noqa: F401,F403
from .common import _paste
from .body import body_fit
from .worn import worn_mask


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
