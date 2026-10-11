"""Reading the body strip: the head, body axis and regions of each frame, the hand-placed rig
points, and how sheets drawn on the body sheet's grid line up with the hero's frames."""
from .common import *  # noqa: F401,F403


# The scale the body sheet is cut at (paperdoll_body.json): sheets drawn on its grid fit the
# hero at about this scale. Set by frame_names().
BODY_SCALE = 0.5


class Hero:
    """The body strip, read once and shared by every layer: its frame names and animations
    (the body manifest's hero set), each frame's pixels and analyse() result, the hand-placed
    rig, and each frame's cell on the body sheet. `r` is idle1's head radius, which pieces are
    sized against."""

    def blank(self):
        """An empty frame."""
        return Image.new("RGBA", (self.fw, self.fh))


def read_hero():
    """Reads the body strip and its rig into a Hero."""
    hero = Hero()
    names, spec = frame_names()
    index = {n: i for i, n in enumerate(names)}
    anims = spec["animations"]
    strip = Image.open(STRIP).convert("RGBA")
    fw, fh = strip.width // len(names), strip.height
    frames = [np.asarray(strip.crop((i * fw, 0, (i + 1) * fw, fh))) for i in range(len(names))]
    info = [analyse(f) for f in frames]
    hands, hold_spec = hand_rig(fw)
    missing = [n for n in names if n not in hands]
    if missing:
        sys.exit(f"{os.path.relpath(HAND_RIG, ROOT)} has no entry for {missing}")
    for n, fi in zip(names, info):
        fi["tilt"] = float(hands[n].get("head_tilt", 0))
    ref = info[0]  # idle1: pieces are sized against this frame
    hero.names, hero.spec, hero.index, hero.anims = names, spec, index, anims
    hero.strip, hero.fw, hero.fh, hero.frames, hero.info = strip, fw, fh, frames, info
    hero.hands, hero.hold_spec, hero.r = hands, hold_spec, ref["r"]
    hero.body_cells = {n: spec["frames"][n].split(":", 1)[1] for n in names}  # frame -> its cell on the body sheet
    return hero


# ---------- reading the body ----------

def frame_names():
    global BODY_SCALE
    with open(BODY_MANIFEST) as f:
        man = json.load(f)
    BODY_SCALE = man["scale"]
    spec = man["sets"]["hero"]
    return list(spec["frames"]), spec


def analyse(px):
    """The head, body axis and regions of one body frame (RGBA uint8 array)."""
    a = px[..., 3] > 127
    rgb = px[..., :3].astype(float) / 255
    mx, mn = rgb.max(2), rgb.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-3), 0)
    grey = a & (sat < 0.16) & (mx > 0.18) & (mx < 0.75)
    dark = a & (mx < 0.22)
    dist = distance_inside(a)
    r = dist.max()
    ys, xs = np.nonzero(dist >= r * 0.8)
    head = np.array([xs.mean(), ys.mean()])
    gy, gx = np.nonzero(grey)
    hips = np.array([gx.mean(), gy.mean()]) if len(gx) else head + [0, 2.5 * r]
    up = head - hips
    up /= max(np.linalg.norm(up), 1e-3)
    down = -up
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    along = (xx - head[0]) * down[0] + (yy - head[1]) * down[1]
    side = (xx - head[0]) * -down[1] + (yy - head[1]) * down[0]
    skin = a & ~grey & ~dark
    region = np.zeros(a.shape, np.uint8)
    region[skin] = R["skin"]
    region[grey] = R["bottom"]
    neck = r * NECK
    shorts_top = along[grey].min() if grey.any() else neck + 1.5 * r
    shorts_bottom = along[grey].max() if grey.any() else shorts_top + r
    feet = along[a].max()
    chest = skin & (along > neck) & (along < shorts_top + 2) & (np.abs(side) < r * 0.62)
    region[chest] = R["top"]
    soles = skin & (along > shorts_bottom + (feet - shorts_bottom) * 0.62)
    region[soles] = R["shoes"]
    return {"r": float(r), "head": head, "up": up, "region": region,
            "neck": head + down * neck, "feet_y": float(np.nonzero(a)[0].max()), "top_y": float(np.nonzero(a)[0].min())}


def body_offsets(names, cells, fw, fh):
    """Per frame, (dx, dy) that takes a point of its cell on the body sheet (in cut pixels, from
    the cell's corner) to the strip frame, the way slice_sheets.build_set put the body there
    (anchor "head", baseline "bottom"). Sheets drawn by editing the body sheet line up with it
    pixel for pixel, so their pieces land on the hero with this."""
    body = cut("paperdoll_body")
    BODY_PIECES.update(body)
    out = {}
    for n in names:
        p = body[cells[n]]
        x = round(fw / 2 - ss.head_x(p.img))
        y = fh - 1 - p.img.height
        out[n] = (x - p.x, y - p.y)
    return out


BODY_PIECES = {}  # the body sheet's cut cells, by cell name (set by body_offsets)


def without_shorts(piece, cell):
    """The pixels of a piece cut from a sheet of the body wearing something (on the body sheet's
    grid) as an RGBA array, with the body's grey shorts taken out: they are greys like the worn
    piece's, so they'd pass for hair or gloves. The shorts are where the body sheet has them."""
    arr = np.asarray(piece.img).copy()
    arr[shorts_mask(piece, cell, 3), 3] = 0
    return arr


def shorts_mask(piece, cell, grow):
    """Where the body sheet has its grey shorts, on a piece of a sheet drawn on its grid (a
    bool mask the piece's size), grown by `grow` pixels, since a redrawn sheet may sit a pixel
    or two off the body."""
    h, w = piece.img.height, piece.img.width
    out = np.zeros((h, w), bool)
    b = BODY_PIECES.get(cell)
    if b is None:
        return out
    px = np.asarray(b.img).astype(float)
    mx, mn = px[..., :3].max(2), px[..., :3].min(2)
    shorts = ss.dilate((px[..., 3] > 0) & (mx - mn < 0.15 * np.maximum(mx, 1)) & (mx > 40) & (mx < 150), grow)
    ys, xs = np.nonzero(shorts)
    ys, xs = ys + b.y - piece.y, xs + b.x - piece.x
    ok = (ys >= 0) & (ys < h) & (xs >= 0) & (xs < w)
    out[ys[ok], xs[ok]] = True
    return out


def aligned(piece, offset):
    """A piece of a sheet drawn on the body sheet's grid, put on a blank frame where it sits on
    the body; returns (image, top-left)."""
    return piece.img, (piece.x + offset[0], piece.y + offset[1])


def drawn_head(arr):
    """The centre and radius of the head (with its hair) in a drawn pose."""
    d = distance_inside(arr[..., 3] > 0)
    r = d.max()
    ys, xs = np.nonzero(d >= r * 0.8)
    return np.array([xs.mean(), ys.mean()]), float(r)


def body_fit(arr, hair, px, scales=None):
    """Lines the body a pose was drawn on up with the hero's: (scale, x, y) of the best overlap.
    The sheets are drawn at the size of the body sheet's cells, so the scale is near the body's
    own cut scale (BODY_SCALE)."""
    if scales is None:
        scales = [BODY_SCALE * k for k in (0.92, 0.96, 1.0, 1.04, 1.08)]
    slack = int(round(24 * BODY_SCALE))
    figure = (arr[..., 3] > 0) & ~ss.dilate(hair, 1)
    ours = px[..., 3] > 127
    oy, ox = np.nonzero(ours)
    best = None
    for s in scales:
        m = np.asarray(Image.fromarray((figure * 255).astype(np.uint8)).resize(
            (max(1, round(figure.shape[1] * s)), max(1, round(figure.shape[0] * s))), Image.BOX)) > 127
        my, mx_ = np.nonzero(m)
        if not len(my):
            continue
        x0 = int(round(ox.mean() - mx_.mean()))
        y0 = int(oy.max() - my.max())
        for dy in range(-slack, slack + 1):
            for dx in range(-slack, slack + 1):
                score = overlap(m, ours, x0 + dx, y0 + dy)
                if best is None or score > best[0]:
                    best = (score, s, x0 + dx, y0 + dy)
    return best[1:]


def overlap(m, ours, x, y):
    """How well mask `m` placed at (x, y) covers `ours`: shared pixels minus half the pixels
    it puts off the body."""
    h, w = ours.shape
    mh, mw = m.shape
    sx0, sy0 = max(0, -x), max(0, -y)
    ex, ey = min(mw, w - x), min(mh, h - y)
    if ex <= sx0 or ey <= sy0:
        return -1e9
    part = m[sy0:ey, sx0:ex]
    under = ours[y + sy0:y + ey, x + sx0:x + ex]
    return (part & under).sum() - 0.5 * (part & ~under).sum() - 0.5 * (m.sum() - part.sum())


def hand_rig(fw):
    """paperdoll_rig.json's frames and holds, its points scaled from the frame size they were
    placed on to the strip's."""
    with open(HAND_RIG) as f:
        spec = json.load(f)
    k = fw / spec.get("frame_size", [fw])[0]
    frames = {}
    for n, h in spec["frames"].items():
        h = dict(h)
        if "weapon" in h:
            h["weapon"] = [h["weapon"][0] * k, h["weapon"][1] * k, h["weapon"][2]]
        if "shield" in h:
            h["shield"] = [h["shield"][0] * k, h["shield"][1] * k]
        if "hands" in h:
            h["hands"] = [[x * k, y * k] for x, y in h["hands"]]
        frames[n] = h
    holds = {}
    for kind, h in spec.get("holds", {}).items():
        h = dict(h)
        h["frames"] = {n: [v[0] * k, v[1] * k, v[2]] if isinstance(v, list) else v for n, v in h.get("frames", {}).items()}
        holds[kind] = h
    return frames, holds
