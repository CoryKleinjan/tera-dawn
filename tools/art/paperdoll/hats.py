"""Hats: each shape's picture (from the side, or from behind) put on his head, sized against
the hat sheet's bald head."""
from .common import *  # noqa: F401,F403


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
    piece much smaller than the hat goes."""
    arr = np.asarray(img).copy()
    lab, n = ss.label(arr[..., 3] > 0)
    sizes = np.bincount(lab.ravel())[1:]
    if n:
        arr[(lab > 0) & (sizes[lab - 1] < sizes.max() * HAT_SPECK), 3] = 0
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
    """Writes hat_<shape> for every shape in HAT_SHAPES."""
    names, info, index, anims = hero.names, hero.info, hero.index, hero.anims
    fw, fh, blank = hero.fw, hero.fh, hero.blank
    # hats: each shape's picture (from the side, or from behind in back views) put on his head,
    # as big as his head against the sheet's head and turned with it (EquipDef.look_shape picks
    # the shape). paperdoll_hats draws each hat on a bald head; paperdoll_hats_only is the same
    # sheet with the heads painted out, so its hats lift off clean and the heads place them
    hat_sheet, hats_only = cut("paperdoll_hats"), cut("paperdoll_hats_only")
    ref_at, ref_r = bald_head(hat_sheet["bald_side"])
    ref_from = ref_at - hat_head(hat_sheet["bald_side"])  # head centre from the shoulders
    for shape in HAT_SHAPES:
        views = {}
        for view in ("side", "behind"):
            p, hat = hat_sheet[f"{shape}_{view}"], hats_only[f"{shape}_{view}"]
            centre = hat_head(p) + ref_from  # this cell's head centre (cell pixels)
            views[view] = (hat_alone(hat.img), centre - (hat.x, hat.y))
        out = []
        for n, fi in zip(names, info):
            canvas = blank()
            img, at = views["behind" if n in BACK_VIEW else "side"]
            k = fi["r"] / ref_r * HAT_SIZE
            place(canvas, scaled(img, k), at * k, fi["head"], fi["tilt"])
            out.append(canvas)
        save_layer(f"hat_{shape}", out, fw, fh, index, anims)
