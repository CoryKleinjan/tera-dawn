"""Hats: each shape's picture (from the side, or from behind) put on his head, sized against
the hat sheet's bald head."""
import glob

from .common import *  # noqa: F401,F403
from .pieces import PIECES, draw_piece, load_piece, pose, save_piece


# ---------- hats ----------

def hat_head(piece):
    """Where the bald head of a paperdoll_hats cell is: the cells draw the same head and
    shoulders, cut off at the cell's bottom, so a cell is lined up with another by the middle of
    its shoulders on its bottom row. Returns that point (cell pixels)."""
    arr = np.asarray(piece.img)
    solid = arr[..., 3] > 0
    rows = np.nonzero(solid.any(1))[0]
    low = solid[rows.max() - HAT_SHOULDER_ROWS:rows.max() + 1]
    xs = np.nonzero(low)[1]
    return np.array([piece.x + xs.mean(), piece.y + rows.max() + 1.0])


def hat_alone(img):
    """A hats_only piece without the bits of the sheet's cell frame caught at its edges: every
    piece much smaller than the hat goes, and every thin straight one (a frame line)."""
    arr = np.asarray(img).copy()
    lab, n = ss.label(arr[..., 3] > 0)
    sizes = np.bincount(lab.ravel())[1:]
    if n:
        arr[(lab > 0) & (sizes[lab - 1] < sizes.max() * HAT_SPECK), 3] = 0
        # and a long thin piece of a cell's frame line, however big
        for i in range(1, n + 1):
            ys, xs = np.nonzero(lab == i)
            w, h = np.ptp(xs) + 1, np.ptp(ys) + 1
            if min(w, h) <= max(w, h) * HAT_LINE and sizes[i - 1] < sizes.max():
                arr[lab == i, 3] = 0
    return Image.fromarray(arr)


def hat_shapes():
    """item id -> look_shape (EquipDef.look_shape) of every hat, from the item data."""
    out = {}
    for folder, _, files in os.walk(ITEMS):
        for f in files:
            if f.endswith(".tres"):
                with open(os.path.join(folder, f)) as fh:
                    text = fh.read()
                item, shape = re.search(r'^id = &"(\w+)"', text, re.M), re.search(r'^look_shape = &"(\w+)"', text, re.M)
                if item and shape:
                    out[item.group(1)] = shape.group(1)
    return out


def fitted(views, shape):
    """A hat's views fitted to his head for its shape: HAT_LOWER (head radii) lower and
    HAT_GROW bigger than on the sheet's head (his hair under a hat is fuller than the bald head)."""
    down, grow = HAT_LOWER.get(shape, 0.0), HAT_GROW.get(shape, 1.0)
    return {v: (img, np.asarray(at, float) - (0.0, down * ref_r), ref_r / grow) for v, (img, at, ref_r) in views.items()}


def open_visor(img):
    """A closed helm with its face opening and eye slits cut out, so his face shows through
    (Cory 2026-10-11: the inside shadow of a closed helm doesn't show when worn). The inside is
    painted as flat dark plum; the outline is the same colour but thin, so only the dark plum
    patches thicker than VISOR_LINE pixels go (with the edge they fade into)."""
    arr = np.asarray(img).copy()
    rgb = arr[..., :3].astype(int)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    plum = (arr[..., 3] > 0) & (g < 32) & (r > g + 25) & (b > g + 25) & (rgb.max(2) < 110)
    thick = ~ss.dilate(~plum, VISOR_LINE)  # what is left of the plum after eroding its lines away
    lab, n = ss.label(thick)
    if n:
        sizes = np.bincount(lab.ravel())[1:]
        keep = np.isin(lab, 1 + np.nonzero(sizes >= VISOR_MIN)[0])
        arr[ss.dilate(keep, VISOR_LINE + 1) & plum, 3] = 0
    return Image.fromarray(arr)


def eye_band(img, at, ref_r):
    """A closed helm's eye opening from the side: (middle x, middle y, width) in picture pixels
    of the rows around its widest opening below the crown, or None for a helm open at the face
    (an opening wider than HELM_OPEN head radii) or with none (under 0.3 head radii)."""
    solid = np.asarray(img)[..., 3] > 0
    best = {}
    for y in range(max(int(at[1] - 0.5 * ref_r), 0), min(int(at[1] + 0.7 * ref_r), solid.shape[0])):  # (brow to cheeks)
        xs = np.nonzero(solid[y])[0]
        if len(xs) < 2:
            continue
        gap = ~solid[y, xs.min():xs.max() + 1]
        run, start, top = 0, 0, (0, 0)
        for i, v in enumerate(gap):
            run = run + 1 if v else 0
            if run > top[0]:
                top = (run, xs.min() + i - run + 1)
        if top[0]:
            best[y] = top
    if not best:
        return None
    widest = max(w for w, _ in best.values())
    if widest > HELM_OPEN * ref_r or widest < 0.3 * ref_r:
        return None
    rows = [y for y, (w, _) in best.items() if w >= widest * HELM_BAND]
    mid = float(np.mean([best[y][1] + best[y][0] / 2.0 for y in rows]))
    return mid, float(np.mean(rows)), float(widest)


def head_width(hero):
    """His head's width in idle1 (ears included), in head radii: the painted area joined to
    the head's middle without crossing a dark line, above his chin."""
    fi, px = hero.info[0], hero.frames[0]
    paint = (px[..., 3] > 127) & (px[..., :3].max(2) >= HEAD_CUT_DARK * 255)
    head = flood(paint, (int(fi["head"][0]), int(fi["head"][1])))
    head[int(fi["head"][1] + fi["r"]):] = False
    xs = np.nonzero(head.any(0))[0]
    return (xs.max() + 1 - xs.min()) / fi["r"]


def hugging(views, head_w):
    """A helm sized to hug his head the way MapleStory's hats do (Cory 2026-10-12): its shell
    HELM_HUG times as wide as his head (`head_w` head radii) across the head's middle, so his
    head stays inside it and nothing pokes out, with no cutting. A closed helm is then moved
    (at most HELM_NUDGE head radii) so its eye holes sit on his eyes (HELM_EYES); the view
    from behind is sized and moved the same."""
    img, at, ref_r = views["side"]
    shell = spanned(np.asarray(img)[..., 3] > 0)
    rows = range(max(int(at[1] - 0.3 * ref_r), 0), min(int(at[1] + 0.3 * ref_r), shell.shape[0]))
    w = max(shell[y].sum() for y in rows)
    r = w / (head_w * HELM_HUG)  # the head radius, in picture pixels, the shell hugs
    new_at = np.asarray(at, float)
    band = eye_band(img, at, ref_r)
    if band is not None:
        x, y, _ = band
        want = np.array([x, y]) - np.array(HELM_EYES[:2]) * r
        new_at = new_at + np.clip(want - new_at, -HELM_NUDGE * r, HELM_NUDGE * r)
    out = {"side": (img, new_at, r)}
    if "behind" in views:
        bimg, bat, bref = views["behind"]
        k = r / ref_r
        lift = (new_at[1] - at[1]) / r
        out["behind"] = (bimg, np.asarray(bat, float) + (0.0, lift * bref * k), bref * k)
    return out


def bald_head(piece):
    """The bald head of the hat sheet's hatless cell: (centre, radius) in cell pixels. Its top
    is the topmost pixel; its chin the narrowest row of the neck below the widest row."""
    arr = np.asarray(piece.img)
    solid = arr[..., 3] > 0
    widths = solid.sum(1)
    top = int(np.nonzero(widths)[0].min())
    widest = int(widths.argmax())
    neck = widths[widest:widest + max(int((len(widths) - widest) * 0.7), 1)]
    chin = widest + int(neck.argmin())
    r = (chin - top) / 2.0
    return np.array([piece.x + solid[widest].nonzero()[0].mean(), piece.y + top + r]), r


def hat_layers(hero):
    """Writes hat_<shape> for every shape in HAT_SHAPES (greyscale, tinted in game), then
    hat_item_<id> for every hat drawn in its own colours (item_hat_layers); all are pieces."""
    # hats: each shape's picture (from the side, or from behind in back views) put on his head,
    # as big as his head against the sheet's head and turned with it (EquipDef.look_shape picks
    # the shape). paperdoll_hats draws each hat on a bald head; paperdoll_hats_only is the same
    # sheet with the heads painted out, so its hats lift off clean and the heads place them
    hat_sheet, hats_only = cut("paperdoll_hats"), cut("paperdoll_hats_only")
    for shape in HAT_SHAPES:
        put_hat(hero, f"hat_{shape}", fitted(hat_views(hat_sheet, hats_only, shape), shape), tinted=True, shape=shape)
    item_hat_layers(hero)


def item_hat_layers(hero):
    """Writes hat_item_<id> for every hat in the item hat sheets (art/sheets/hats_items_*.json,
    each with its _only twin): the same layout as paperdoll_hats, with each cell pair named
    <item>_side and <item>_behind, painted in the hat's own colours from its icon."""
    shapes = hat_shapes()
    head_w = head_width(hero)
    for path in sorted(glob.glob(os.path.join(ss.SHEETS, "hats_items_*.json"))):
        name = os.path.splitext(os.path.basename(path))[0]
        if name.endswith("_only") or not os.path.exists(os.path.join(ss.SHEETS, name + "_only.json")):
            continue  # (a sheet waits for its heads-erased twin)
        sheet, only = cut(name), cut(name + "_only")
        for key in sheet:
            if key.endswith("_side") and key[:-5] + "_behind" in sheet and key != "bald_side":
                item = key[:-5]
                views = fitted(hat_views(sheet, only, item), shapes.get(item))
                if shapes.get(item) == "helm":
                    views = hugging(views, head_w)
                    views = {v: (open_visor(img), at, ref_r) for v, (img, at, ref_r) in views.items()}
                put_hat(hero, f"hat_item_{item}", views, tinted=False, shape=shapes.get(item),
                        head_cut=shapes.get(item) == "helm")


def hat_views(sheet, only, prefix):
    """A hat's two views, {"side"|"behind": (picture, head centre in the picture)}, lifted off
    the heads-erased sheet (`only`) and placed by the heads in `sheet`, sized by the sheet's
    bald_side head (each sheet carries one, as Gemini draws every sheet a little differently)."""
    ref_at, ref_r = bald_head(sheet["bald_side"])
    ref_from = ref_at - hat_head(sheet["bald_side"])  # head centre from the shoulders
    views = {}
    for view in ("side", "behind"):
        p, hat = sheet[f"{prefix}_{view}"], only[f"{prefix}_{view}"]
        img = hat_alone(hat.img)
        at = hat_head(p) + ref_from - (hat.x, hat.y)  # this cell's head centre (picture pixels)
        if view == "behind":
            # from behind his head is straight above his shoulders' middle on the sheet only
            # roughly (the back-view shoulders are turned); a hat seen from behind is drawn
            # centred on the head, so its own middle is the head's
            at[0] = middle(img)
        views[view] = (img, at, ref_r)
    return views


def crown(img):
    """The columns (first, last + 1) of a hat's crown: its top half, without the ties and
    drapes hanging below it."""
    solid = np.asarray(img)[..., 3] > 0
    rows = np.nonzero(solid.any(1))[0]
    cols = np.nonzero(solid[rows.min():rows.min() + max((rows.max() - rows.min()) // 2, 1)].any(0))[0]
    return cols.min(), cols.max() + 1


def middle(img):
    """The middle (x, picture pixels) of a hat's crown."""
    return sum(crown(img)) / 2.0


def crown_width(img):
    a, b = crown(img)
    return float(b - a)


def put_hat(hero, name, views, tinted, shape=None, head_cut=False):
    """Saves a hat as a piece (pieces.py): its two views, put on his head in every frame, as
    big as his head against the sheet's head (from behind HAT_BACK_WIDTH wide) and
    turned with it. The pictures are cut at his typical head size; each frame scales them by
    its own head. A helm drawn smaller than his head (`head_cut`) also cuts his head where it
    would poke out of it (save_head_cut)."""
    r_mid = float(np.median([fi["r"] for fi in hero.info]))
    pictures, frames = {}, []
    for view, (img, at, ref_r) in views.items():
        k = r_mid / ref_r * HAT_SIZE
        if view == "behind" and shape in HAT_BACK_WIDTH:
            k = HAT_BACK_WIDTH[shape] * r_mid / crown_width(img)
        pictures[view] = (scaled(img, k), np.asarray(at) * k)
    for n, fi in zip(hero.names, hero.info):
        view = "behind" if n in BACK_VIEW else "side"
        frames.append(pose(view, fi["head"], fi["tilt"], fi["r"] / r_mid))
    save_piece(name, pictures, frames, tinted)
    save_hair_cut(hero, name, head_cut)
    if head_cut:
        save_head_cut(hero, name)


def save_hair_cut(hero, name, head=False):
    """haircut_<name>.png: per body frame, white where his hair is hidden under the hat (the
    game cuts those pixels out of the hair layer): above the hat's lower edge, across the hat
    and HAIR_CUT_SIDE head radii past its sides, so no hair pokes out of its top or sides; hair
    below its lower edge still shows (Cory 2026-10-11). The lower edge of a column is the bottom
    of the hat's first stretch of pixels going down, so an opening (a helm's face) or a drape
    hanging below a gap doesn't count (on a helm, a stretch ending HAIR_CUT_CREST head radii
    above the head's middle is a crest standing over a gap, and the next one is the edge); off his head (HAIR_CUT_HEAD head radii from its middle)
    it is the deepest edge of the hat within HAIR_CUT_REACH, so a crest sticking out over his
    hair still hides it. Hair hanging below HAIR_CUT_LOW head radii under the head's middle
    always shows (long hair down his back past a bandana's tails). With `head` (a helm that
    cuts his head, save_head_cut) the hair over his head is hidden too, so none is left
    floating where his head was cut away. The piece's JSON names the strip ("hair_cut")."""
    p = load_piece(name)
    fw, fh = hero.fw, hero.fh
    strip = np.zeros((fh, fw * len(p["frames"]), 4), np.uint8)
    for i, fi in enumerate(hero.info):
        canvas = Image.new("RGBA", (fw, fh))
        draw_piece(canvas, p, i, False)
        draw_piece(canvas, p, i, True)
        solid = np.asarray(canvas)[..., 3] > HAIR_CUT_ALPHA
        cols = np.nonzero(solid.any(0))[0]
        if not len(cols):
            continue
        edge = np.full(fw, -1)
        for x in cols:
            ys = np.nonzero(solid[:, x])[0]
            ends = np.append(ys[np.nonzero(np.diff(ys) > 1)[0]], ys[-1])
            high = (ends < fi["head"][1] - HAIR_CUT_CREST * fi["r"]) & head  # (a helm's crest over a gap)
            edge[x] = ends[np.argmin(high)] if not high.all() else ends[-1]
        side, reach = int(round(HAIR_CUT_SIDE * fi["r"])), int(round(HAIR_CUT_REACH * fi["r"]))
        hx = fi["head"][0]
        for x in range(max(cols.min() - side, 0), min(cols.max() + side + 1, fw)):
            if abs(x - hx) <= fi["r"] * HAIR_CUT_HEAD and edge[x] >= 0:
                e = edge[x]
            else:  # off his head (or a gap): the deepest edge of the hat columns nearby, so a crest
                # or brim sticking out past his head doesn't let the hair under it show
                near = cols[np.abs(cols - x) <= reach]
                e = edge[near].max() if len(near) else edge[cols[np.argmin(np.abs(cols - x))]]
            e = min(e, int(fi["head"][1] + HAIR_CUT_LOW * fi["r"]))  # (hair hanging lower always shows)
            strip[:e + 1, i * fw + x] = 255
            if abs(x - hx) > HAIR_CUT_OUT * fi["r"]:  # (and no stubs of spiky hair stick out beside his face)
                strip[:int(fi["head"][1] + HAIR_CUT_OUT_LOW * fi["r"]) + 1, i * fw + x] = 255
        if head:
            strip[:, i * fw:(i + 1) * fw][head_area(fi, fw, fh, HEAD_CUT_HAIR)] = 255
    save_strip(strip, name, "haircut", "hair_cut")


def head_area(fi, fw, fh, reach=HEAD_CUT_DISC):
    """Where his head is in a frame, as far as a helm's cuts go: `reach` head radii from its
    middle, no lower than HEAD_CUT_LOW under it (his neck and shoulders stay)."""
    yy, xx = np.mgrid[0:fh, 0:fw]
    hx, hy = fi["head"]
    return ((xx - hx) ** 2 + (yy - hy) ** 2 <= (reach * fi["r"]) ** 2) & (yy <= hy + HEAD_CUT_LOW * fi["r"])


def save_head_cut(hero, name):
    """headcut_<name>.png, laid out like the body strip: white where his body and face are cut
    away around a helm drawn smaller than his head (Cory 2026-10-11: helms smaller, but nothing
    of his head poking out). That is his head (head_area) under the hair cut, outside the helm's
    outline (spanned across each row, so his face shows through its eye holes or its open
    front). His head is the
    painted area joined to its middle without crossing a dark line, so an arm drawn over it
    stays, as does every hand of the rig (HEAD_CUT_HAND around it, outside HEAD_CUT_KEEP of the
    head's middle). The edges are softened a pixel. The piece's JSON names it ("head_cut")."""
    p = load_piece(name)
    fw, fh = hero.fw, hero.fh
    hair = np.asarray(Image.open(os.path.join(PIECES, f"haircut_{name}.png")))[..., 3] > 0
    strip = np.zeros((fh, fw * len(p["frames"]), 4), np.uint8)
    yy, xx = np.mgrid[0:fh, 0:fw]
    for i, (n, fi) in enumerate(zip(hero.names, hero.info)):
        canvas = Image.new("RGBA", (fw, fh))
        draw_piece(canvas, p, i, False)
        draw_piece(canvas, p, i, True)
        helm = spanned(np.asarray(canvas)[..., 3] > HAIR_CUT_ALPHA)
        body = hero.frames[i]
        paint = (body[..., 3] > 127) & (body[..., :3].max(2) >= HEAD_CUT_DARK * 255)
        hx, hy = fi["head"]
        head = grown(flood(paint, (int(hx), int(hy))), 4)
        spots = [h for k, h in hero.hands[n].items() if isinstance(h, list) and k != "hands"]
        for ax, ay, *_ in spots + hero.hands[n].get("hands", []):
            head &= ~(((xx - ax) ** 2 + (yy - ay) ** 2 < (HEAD_CUT_HAND * fi["r"]) ** 2)
                      & ((xx - hx) ** 2 + (yy - hy) ** 2 > (HEAD_CUT_KEEP * fi["r"]) ** 2))
        cut = head & head_area(fi, fw, fh) & hair[:, i * fw:(i + 1) * fw] & ~helm
        soft = Image.fromarray(cut.astype(np.uint8) * 255).filter(ImageFilter.BoxBlur(1))
        strip[:, i * fw:(i + 1) * fw, 3] = np.asarray(soft)
    strip[..., :3] = 255
    save_strip(strip, name, "headcut", "head_cut")


def spanned(mask):
    """A mask filled between its first and last pixel of every row."""
    out = np.zeros_like(mask)
    for y in np.nonzero(mask.any(1))[0]:
        xs = np.nonzero(mask[y])[0]
        out[y, xs[0]:xs[-1] + 1] = True
    return out


def flood(mask, at):
    """The part of a mask joined to the pixel `at` (x, y); empty if that pixel is off it."""
    im = Image.fromarray(mask.astype(np.uint8) * 255).copy()
    if not mask[at[1], at[0]]:
        return np.zeros_like(mask)
    ImageDraw.floodfill(im, at, 128)
    return np.asarray(im) == 128


def grown(mask, px):
    """A mask grown by `px` pixels each way."""
    return np.asarray(Image.fromarray(mask.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(2 * px + 1))) > 0


def save_strip(strip, name, prefix, key):
    """Saves a cut strip as <prefix>_<name>.png and names it in the piece's JSON under `key`."""
    Image.fromarray(strip, "RGBA").save(os.path.join(PIECES, f"{prefix}_{name}.png"))
    path = os.path.join(PIECES, name + ".json")
    with open(path) as f:
        data = json.load(f)
    data[key] = "res://" + os.path.relpath(os.path.join(PIECES, f"{prefix}_{name}.png"), ROOT)
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"))
