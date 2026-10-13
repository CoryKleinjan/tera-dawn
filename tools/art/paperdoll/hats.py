"""Hats: each shape's picture (from the side, or from behind) put on his head, sized against
the hat sheet's bald head."""
import glob
import math
import json

from .common import *  # noqa: F401,F403
from .hair import head_axes
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
    piece much smaller than the hat goes, every thin straight one (a frame line), and any line
    filling an edge row or column (HAT_FRAME_FILL), even joined to the hat."""
    arr = np.asarray(img).copy()
    a = arr[..., 3]
    for side in range(4):  # (a frame line along an edge, even where it touches the hat)
        lines = np.rot90(a, side)
        fill = (lines > 40).mean(1)
        k = int(np.argmin(fill >= HAT_FRAME_FILL))  # full rows from the edge
        if 0 < k <= HAT_FRAME_THICK and fill[k] < HAT_FRAME_FILL / 2:  # (thin, then clear: not a flat brim)
            lines[:k] = 0
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
        with open(path) as f:
            spec = json.load(f)
        shoulders, lower = spec.get("shoulders", {}), spec.get("lower", {})
        for key in sheet:
            if key.endswith("_side") and key[:-5] + "_behind" in sheet and key != "bald_side":
                item = key[:-5]
                views = fitted(hat_views(sheet, only, item, shoulders), shapes.get(item))
                closed = False
                if shapes.get(item) == "helm":
                    closed = eye_band(*views["side"]) is not None
                    views = hugging(views, head_w)
                    views = {v: (open_visor(img), at, ref_r) for v, (img, at, ref_r) in views.items()}
                put_hat(hero, f"hat_item_{item}", views, tinted=False, shape=shapes.get(item),
                        head_cut=shapes.get(item) == "helm")
                if closed:  # then moved so his eyes look out of its eye holes, and saved again
                    views = eyes_out(hero, f"hat_item_{item}", views)
                    if item in lower:  # (and a little lower where Cory asked: "lower", head radii)
                        views = {v: (img, np.asarray(at, float) - (0.0, lower[item] * ref_r), ref_r)
                                 for v, (img, at, ref_r) in views.items()}
                    put_hat(hero, f"hat_item_{item}", views, tinted=False, shape="helm", head_cut=True)


def enclosed(solid):
    """The holes in a picture's solid part: the gaps it closes in all round (none of them
    reaching the picture's edge)."""
    lab, n = ss.label(~solid)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    return (lab > 0) & ~np.isin(lab, edge)


def eyes_out(hero, name, views):
    """A closed helm's views moved so his eyes show through its eye holes: the shift (at most
    HELM_NUDGE head radii) that leaves the most of his eye pixels (the face layer's irises)
    in its holes (the eye slits a visor closes in all round, or for an open helm anywhere inside
    its outline: not under it, nor out past it, which would leave his face poking out),
    the median over the frames that show his face, applied to both views. The sheets' eye holes aren't all where
    HELM_EYES expects, so it is measured on the saved piece."""
    eyes = np.asarray(Image.open(os.path.join(LAYERS, f"face_{FACES[0]}_eyes.png")))[..., 3] > SOLID_EYES
    p = load_piece(name)
    reach = int(HELM_NUDGE * float(np.median([fi["r"] for fi in hero.info])))
    shifts = []
    for i in range(len(hero.info)):
        e = eyes[:, i * hero.fw:(i + 1) * hero.fw]
        if not e.any():
            continue
        canvas = Image.new("RGBA", (hero.fw, hero.fh))
        draw_piece(canvas, p, i, False)
        draw_piece(canvas, p, i, True)
        helm = np.asarray(canvas)[..., 3] > HAIR_CUT_ALPHA
        hole = enclosed(helm)  # (its eye holes: closed in all round, not the open face below a visor)
        if not hole.any():
            hole = spanned(helm) & ~helm  # (an open helm: inside its outline, not under it)
        ey, ex = np.nonzero(e)
        best = min(((dx, dy) for dx in range(-reach, reach + 1) for dy in range(-reach, reach + 1)),
                   key=lambda d: (int((~hole[np.clip(ey - d[1], 0, hero.fh - 1), np.clip(ex - d[0], 0, hero.fw - 1)]).sum()),
                                  abs(d[0]) + abs(d[1])))
        shifts.append(best)
    if not shifts:
        return views
    dx, dy = np.median(np.array(shifts, float), axis=0)
    r_mid = float(np.median([fi["r"] for fi in hero.info]))
    out = {}
    for view, (img, at, ref_r) in views.items():
        k = r_mid / ref_r * HAT_SIZE  # (picture pixels to frame pixels, as put_hat draws it)
        out[view] = (img, np.asarray(at, float) - (dx / k if view == "side" else 0.0, dy / k), ref_r)
    return out


def hat_views(sheet, only, prefix, shoulders=None):
    """A hat's two views, {"side"|"behind": (picture, head centre in the picture)}, lifted off
    the heads-erased sheet (`only`) and placed by the heads in `sheet`, sized by the sheet's
    bald_side head (each sheet carries one, as Gemini draws every sheet a little differently).
    A cell with nothing down to its bottom (a hood repainted without its cape, Cory 2026-10-12:
    nothing on a hat covers the shoulders) names where its shoulders were in the manifest's
    "shoulders" (cell pixels), as hat_head would have found them."""
    ref_at, ref_r = bald_head(sheet["bald_side"])
    ref_from = ref_at - hat_head(sheet["bald_side"])  # head centre from the shoulders
    views = {}
    for view in ("side", "behind"):
        p, hat = sheet[f"{prefix}_{view}"], only[f"{prefix}_{view}"]
        img = hat_alone(hat.img)
        low = (shoulders or {}).get(f"{prefix}_{view}")
        at = (np.asarray(low, float) if low else hat_head(p)) + ref_from - (hat.x, hat.y)  # this cell's head centre (picture pixels)
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
    game cuts those pixels out of his own hair layer, so his hair looks the same under a hat, only
    trimmed: Cory 2026-10-12): above the hat's lower edge, across the whole frame, so no hair
    pokes out of its top or sides; hair below its lower edge still shows. The lower edge of a
    column is the bottom of the hat's first stretch of pixels going down, so an opening (a helm's
    face) or a drape hanging below a gap doesn't count (on a helm, a stretch ending
    HAIR_CUT_CREST head radii above the head's middle is a crest standing over a gap, and the next
    one is the edge); off his head (HAIR_CUT_HEAD head radii from its middle) it is the deepest
    edge of the hat within HAIR_CUT_REACH, so a crest or brim sticking out over his hair still
    hides it, and past the hat's sides that of its nearest column. Hair hanging below HAIR_CUT_LOW
    head radii under the head's middle always shows (long hair down his back past a bandana's
    tails). Beside a helm (`head`) the cut runs down to the bottom of its cheek and neck guards,
    and inside its outline (its eye holes) no hair shows. Each hairstyle also gets its own strip
    (haircut_<name>_<style>.png, no_loose_hair). The piece's JSON names them ("hair_cut",
    "hair_cuts")."""
    p = load_piece(name)
    fw, fh = hero.fw, hero.fh
    strip = np.zeros((fh, fw * len(p["frames"]), 4), np.uint8)
    solids = []
    for i, fi in enumerate(hero.info):
        canvas = Image.new("RGBA", (fw, fh))
        draw_piece(canvas, p, i, False)
        draw_piece(canvas, p, i, True)
        solid = np.asarray(canvas)[..., 3] > HAIR_CUT_ALPHA
        solids.append(solid)
        cols = np.nonzero(solid.any(0))[0]
        if not len(cols):
            continue
        edge, bottom = np.full(fw, -1), np.full(fw, -1)
        for x in cols:
            ys = np.nonzero(solid[:, x])[0]
            ends = np.append(ys[np.nonzero(np.diff(ys) > 1)[0]], ys[-1])
            high = (ends < fi["head"][1] - HAIR_CUT_CREST * fi["r"]) & head  # (a helm's crest over a gap)
            edge[x] = ends[np.argmin(high)] if not high.all() else ends[-1]
            bottom[x] = ends[-1]
        reach = int(round(HAIR_CUT_REACH * fi["r"]))
        hx = fi["head"][0]
        for x in range(fw):  # (beside the hat too, any hair above its lower edge: none sticks out its sides)
            if abs(x - hx) <= fi["r"] * HAIR_CUT_HEAD and edge[x] >= 0:
                e = edge[x]
            else:  # off his head (or a gap): the deepest edge of the hat columns nearby, so a crest
                # or brim sticking out past his head doesn't let the hair under it show
                # (beside a helm, the bottom of its cheek and neck guards: none sticks out its sides)
                low = bottom if head else edge
                near = cols[np.abs(cols - x) <= reach]
                e = low[near].max() if len(near) else low[cols[np.argmin(np.abs(cols - x))]]
            if not (head and (x < cols.min() or x > cols.max())):  # (beside a helm: down to its edge)
                e = min(e, int(fi["head"][1] + HAIR_CUT_LOW * fi["r"]))  # (hair hanging lower always shows)
            e -= HAIR_CUT_TUCK  # (the hair runs on under the hat's soft lower edge: no seam between them)
            strip[:e + 1, i * fw + x] = 255
        if head:  # (nor any through its eye holes: inside a helm's outline his hair never shows)
            strip[:, i * fw:(i + 1) * fw][~ss.dilate(~spanned(solid), HAIR_CUT_TUCK)] = 255
    save_strip(softened(strip), name, "haircut", "hair_cut")
    for style in HAIRSTYLES:  # (every style: just his own hair, cut to the hat's shape)
        if os.path.exists(os.path.join(LAYERS, f"hair_{style}.png")):
            save_strip(softened(strip), name, "haircut", "hair_cuts", style)


def nothing_ahead(cut, hero, heads):
    """A style's cut strip that also hides the hair sticking out past the front of his face
    (Cory 2026-10-13: bangs that hang past the front of his face look awkward; the bangs over
    his forehead stay): more than HAIR_FACE_OVER off his head (it stays a little wider than his head, so it
    covers it: Cory 2026-10-13) and forward of HAIR_FACE_FRONT, on every frame but those
    from behind."""
    out = cut.copy()
    fw = hero.fw
    for i, (n, px, fi) in enumerate(zip(hero.names, hero.frames, hero.info)):
        if n in BACK_VIEW:
            continue
        ahead, _ = head_axes(px.shape, fi, fi["head"])
        out[:, i * fw:(i + 1) * fw][(ahead > HAIR_FACE_FRONT) & ~ss.dilate(heads[i], round(HAIR_FACE_OVER * fi["r"]))] = 255
    return out


def as_in(cut, hair, hero, pose_name):
    """A style's cut strip with every side-view frame showing only what `pose_name`'s frame
    shows of it, set on that frame's head (moved, turned and sized with it): Cory 2026-10-12,
    the hair under a hat in the sitting pose looks the best and every pose wears it. Frames
    from behind keep their own."""
    fw, fh = hero.fw, hero.fh
    s = hero.names.index(pose_name)
    src = hair[:, s * fw:(s + 1) * fw] & (cut[:, s * fw:(s + 1) * fw, 3] == 0)  # (what shows there)
    fs = hero.info[s]
    out = cut.copy()
    yy, xx = np.mgrid[0:fh, 0:fw]
    for i, (n, fi) in enumerate(zip(hero.names, hero.info)):
        if i == s or n in BACK_VIEW:
            continue
        rel = np.stack([xx - fi["head"][0], yy - fi["head"][1]]) / fi["r"]
        a = math.radians(fs["tilt"] - fi["tilt"])  # (back into the held pose's turn)
        sx = fs["head"][0] + (rel[0] * math.cos(a) - rel[1] * math.sin(a)) * fs["r"]
        sy = fs["head"][1] + (rel[0] * math.sin(a) + rel[1] * math.cos(a)) * fs["r"]
        ok = (sx >= 0) & (sx < fw) & (sy >= 0) & (sy < fh)
        shows = np.zeros((fh, fw), bool)
        shows[ok] = src[sy[ok].astype(int), sx[ok].astype(int)]
        out[:, i * fw:(i + 1) * fw][~shows] = 255
        out[:, i * fw:(i + 1) * fw][shows] = 0
    return out


def his_head(px, fi):
    """His bald head in one body frame (ears included): the painted area joined to its middle
    without crossing a dark line, above his chin (as head_width)."""
    paint = (px[..., 3] > 127) & (px[..., :3].max(2) >= HEAD_CUT_DARK * 255)
    head = flood(paint, (int(fi["head"][0]), int(fi["head"][1])))
    head[int(fi["head"][1] + fi["r"]):] = False
    return head


def no_loose_hair(strip, solids, heads, hair, fw, radii, tails=False, centres=None, backs=None):
    """A hair cut strip that also hides the bits of one hairstyle's hair the cut leaves loose:
    every patch still showing whose cut edge is mostly out in the air rather than at the hat
    (within HAIR_CUT_TOUCH of it), such as a ponytail's end whose middle went under the hat or a
    twin tail chopped off beside it; every patch the cut reached that doesn't touch his head
    (his_head, within HAIR_CUT_BODY pixels), such as a twin tail hanging from a brim or a lock
    of long hair hanging down his back from under a helm (Cory 2026-10-12: hair that is
    disconnected and floating is trimmed); and any wisp smaller than HAIR_CUT_SPECK head radii squared
    off on its own (or HAIR_CUT_CRUMB anywhere). A patch the cut doesn't reach stays. A style
    with `tails` (HAIR_HEAD_ONLY: long hair, ponytail, twin tails) shows none of its hair off his
    head (outside the HAIR_HEAD_ONLY_OVAL round his brow) under a hat, only the locks framing
    his eyes (Cory 2026-10-12: ponytails and pigtails shouldn't show under hats; long hair
    sticking out of a hat is just the locks by his face, none near his mouth)."""
    out = strip.copy()
    for i, solid in enumerate(solids):
        cut = out[:, i * fw:(i + 1) * fw]
        hidden = cut[..., 3] > 0
        shows = hair[:, i * fw:(i + 1) * fw] & ~hidden
        if not solid.any() or not shows.any():
            continue
        hat_cut = hidden  # (where the hat's own cut chopped it, not the tails' below)
        if tails:  # (its tails go under the hat with the rest)
            hx, hy = centres[i]
            yy, xx = np.mgrid[0:hidden.shape[0], 0:fw]
            # (from behind, the back of his head down to his neck: no bald patch under the hat)
            oval = HAIR_HEAD_ONLY_BACK if backs and backs[i] else HAIR_HEAD_ONLY_OVAL
            rx, ry, up = (k * radii[i] for k in oval)
            on = ((xx - hx) / rx) ** 2 + ((yy - hy + up) / ry) ** 2 <= 1.0  # (a round line, no steps)
            cut[ss.dilate(shows & ~on, 3) & ~(shows & on)] = 255  # (wide enough that its soft edge still hides it all)
            shows &= ~(cut[..., 3] > 0)
        lab, n = ss.label(shows)
        edge = shows & ss.dilate(hat_cut & hair[:, i * fw:(i + 1) * fw], 1)  # (where the cut chopped it)
        at_hat = edge & ss.dilate(solid, HAIR_CUT_TOUCH)
        chopped = np.bincount(lab[edge], minlength=n + 1)
        held = np.bincount(lab[at_hat], minlength=n + 1)
        size = np.bincount(lab.ravel(), minlength=n + 1)
        near = np.bincount(lab[ss.dilate(solid, HAIR_CUT_TOUCH) & shows], minlength=n + 1)
        on_him = np.bincount(lab[ss.dilate(heads[i], HAIR_CUT_BODY) & shows], minlength=n + 1)
        # (and wisps off on their own, or crumbs anywhere)
        speck = ((size < HAIR_CUT_SPECK * radii[i] ** 2) & (near == 0)) | (size < HAIR_CUT_CRUMB * radii[i] ** 2)
        loose_ids = np.nonzero(((chopped > 0) & ((held < chopped * HAIR_CUT_HELD) | (on_him == 0))) | speck)[0]
        loose = np.isin(lab, loose_ids[loose_ids > 0])
        cut[ss.dilate(loose, 3) & ~(shows & ~loose)] = 255  # (wide enough that its soft edge still hides it all)
    return out


def softened(strip, hard=None):
    """A cut strip with its edge blurred (HAIR_CUT_SOFT), so the hair fades out under the hat
    rather than stopping at a step; left as it is where `hard`."""
    out = np.asarray(Image.fromarray(strip, "RGBA").filter(ImageFilter.GaussianBlur(HAIR_CUT_SOFT))).copy()
    if hard is not None:
        out[hard] = strip[hard]
    out[..., :3] = 255  # (only its alpha counts; plain white keeps the file small)
    return out


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
        cut = head & head_area(fi, fw, fh) & hair[:, i * fw:(i + 1) * fw] & ~helm  # (none under its soft edge either: Cory 2026-10-13)
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


def save_strip(strip, name, prefix, key, style=None):
    """Saves a cut strip as <prefix>_<name>.png and names it in the piece's JSON under `key`;
    one hairstyle's (`style`) as <prefix>_<name>_<style>.png, under key[style]."""
    file = f"{prefix}_{name}_{style}.png" if style else f"{prefix}_{name}.png"
    Image.fromarray(strip, "RGBA").save(os.path.join(PIECES, file))
    path = os.path.join(PIECES, name + ".json")
    with open(path) as f:
        data = json.load(f)
    res = "res://" + os.path.relpath(os.path.join(PIECES, file), ROOT)
    if style:
        data.setdefault(key, {})[style] = res
    else:
        data[key] = res
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"))
