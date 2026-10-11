"""Hats: each shape's picture (from the side, or from behind) put on his head, sized against
the hat sheet's bald head."""
import glob

from .common import *  # noqa: F401,F403
from .pieces import pose, save_piece


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
                    views = {v: (open_visor(img), at, ref_r) for v, (img, at, ref_r) in views.items()}
                put_hat(hero, f"hat_item_{item}", views, tinted=False, shape=shapes.get(item))


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


def put_hat(hero, name, views, tinted, shape=None):
    """Saves a hat as a piece (pieces.py): its two views, put on his head in every frame, as
    big as his head against the sheet's head (from behind at least HAT_BACK_WIDTH wide) and
    turned with it. The pictures are cut at his typical head size; each frame scales them by
    its own head."""
    r_mid = float(np.median([fi["r"] for fi in hero.info]))
    pictures, frames = {}, []
    for view, (img, at, ref_r) in views.items():
        k = r_mid / ref_r * HAT_SIZE
        if view == "behind" and shape in HAT_BACK_WIDTH:
            k = max(k, HAT_BACK_WIDTH[shape] * r_mid / crown_width(img))
        pictures[view] = (scaled(img, k), np.asarray(at) * k)
    for n, fi in zip(hero.names, hero.info):
        view = "behind" if n in BACK_VIEW else "side"
        frames.append(pose(view, fi["head"], fi["tilt"], fi["r"] / r_mid))
    save_piece(name, pictures, frames, tinted)
