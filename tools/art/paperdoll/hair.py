"""Hair: the one-piece hairstyles (front, back and under-a-hat pieces put on the head found
in each frame), the scalp repainted in hair greys under every style, and the styles drawn in
every pose (hair_<style>_frames sheets), lifted off each pose and set on his head."""
from .common import *  # noqa: F401,F403
from .body import body_fit, drawn_head, without_shorts


# ---------- the scalp ----------

def hair_grey(img):
    """The middle grey of a hair piece (0..255)."""
    arr = np.asarray(img).astype(float)
    solid = arr[..., 3] > 0
    return float(np.median(arr[solid][:, :3].mean(1))) if solid.any() else 128.0


def head_axes(shape, fi, centre):
    """Per pixel of a frame: how far it is (head radii) ahead of and above `centre`, along the
    head's own forward and up (turned with its tilt)."""
    h, w = shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    dx, dy = xx - centre[0], yy - centre[1]
    up, fwd = turned((0, -1), fi["tilt"]), turned((1, 0), fi["tilt"])
    return (dx * fwd[0] + dy * fwd[1]) / fi["r"], (dx * up[0] + dy * up[1]) / fi["r"]


def face_zone(px, fi):
    """The face on a body frame, forehead to chin and ear to cheek: the part of the head inside
    an egg around the face's centre (FACE_ZONE), as a bool mask. No hair is drawn there under a
    hat, and the scalp's hairline follows its rounded top instead of a straight cut."""
    back, front, top, bottom = FACE_ZONE
    ahead, above = head_axes(px.shape, fi, fi["head"] + turned(FACE_AT, fi["tilt"]) * fi["r"])
    sx = np.where(ahead < 0, back, front)
    sy = np.where(above > 0, top, bottom)
    near = np.hypot(*head_axes(px.shape, fi, fi["head"])) <= 1.1  # the head, not the neck below it
    return ((ahead / sx) ** 2 + (above / sy) ** 2 <= 1) & near & (px[..., 3] > 127)


def bare_face(img, px, fi):
    """A hair-under-a-hat layer with the face cut out of it, so the hero's face shows through:
    the face_zone, and the rest of the blank face the sheet draws inside the hair (its palest
    greys, where they run on from the face zone below the eyes: the cheek and jaw), with its
    outline."""
    arr = np.asarray(img).copy()
    zone = face_zone(px, fi)
    rgb = arr[..., :3].astype(int)
    blank = (arr[..., 3] > 0) & (rgb.min(2) >= BLANK_FACE) & (rgb.max(2) - rgb.min(2) < 12)
    ahead, above = head_axes(px.shape, fi, fi["head"])
    blank &= (np.hypot(ahead, above) <= 1.45) & (above < 0)  # cheek and jaw: not pale streaks in the bangs
    lab, n = ss.label(blank | zone)
    if n:
        clear = np.isin(lab, np.unique(lab[zone]))
        arr[ss.dilate(clear, 1) & (rgb.min(2) >= BLANK_FACE - 40), 3] = 0  # and its soft edge
        # and the blank's own outline where it runs across his cheek and jaw (the drawn blank
        # is a little smaller than his face), so no line is left on his skin
        arr[ss.dilate(clear, 3) & (above < 0) & ((rgb.max(2) < BLANK_FACE - 60) | (rgb.min(2) >= BLANK_FACE - 80)), 3] = 0
        arr[clear, 3] = 0
    return Image.fromarray(no_neck(arr, fi), "RGBA")


def no_neck(arr, fi):
    """A hair-under-a-hat layer without the rest of the sheet's blank head below the face: the
    pale neck and ear left under the hair, with their outline. Tinted with the hair colour they
    showed as a brown wedge on his neck and chest."""
    rgb = arr[..., :3].astype(int)
    solid = arr[..., 3] > 0
    pale = solid & (rgb.min(2) >= BLANK_FACE - 30) & (rgb.max(2) - rgb.min(2) < 12)
    ahead, above = head_axes(arr.shape, fi, fi["head"])
    lab, n = ss.label(pale)
    if not n:
        return arr
    low = np.zeros(n + 1, bool)
    for i in range(1, n + 1):  # a pale piece mostly below the middle of his head: skin, not a shine
        part = lab == i
        low[i] = part.sum() >= 6 and np.median(above[part]) < -0.25
    skin = low[lab]
    out = arr.copy()
    if skin.any():
        # its outline: the dark pixels just around it that aren't hair (no mid grey beside them)
        mid = solid & ~pale & (rgb.min(2) >= 90)
        edge = ss.dilate(skin, 3) & solid & ~mid & ~ss.dilate(mid & ~ss.dilate(skin, 1), 1)
        out[skin | edge, 3] = 0
        # and the slivers of that outline left loose under his jaw
        lab, n = ss.label(out[..., 3] > 0)
        for i in range(1, n + 1):
            part = lab == i
            if part.sum() < NECK_SLIVER and np.median(above[part]) < -0.25:
                out[part, 3] = 0
    return out


def scalp(px, fi, back_view, grey):
    """The top and back of the bald head in one body frame, repainted in hair greys with the
    head's own shading. It goes under the hairstyle, so no pose shows a bald patch where the
    hair piece doesn't reach (the back of the head in a slash, the crown when he looks up).
    Facing us, it stops at a hairline around the face (face_zone)."""
    h, w = px.shape[:2]
    ahead, above = head_axes(px.shape, fi, fi["head"])
    head = (ahead ** 2 + above ** 2 <= 1.45 ** 2) & (px[..., 3] > 127)
    on = head & (above > -SCALP_NAPE)
    if not back_view:
        on &= ~face_zone(px, fi)
    rgb = px[..., :3].astype(float)
    lum = rgb.mean(2)
    skin = on & (lum > 90)
    ref = np.median(lum[skin]) if skin.any() else 200.0
    out = np.zeros((h, w, 4), np.uint8)
    shade = (lum * grey / ref).clip(0, 255)
    out[..., 0] = out[..., 1] = out[..., 2] = np.where(skin, shade, lum).round().astype(np.uint8)
    out[..., 3] = np.where(on, 255, 0)
    return Image.fromarray(out, "RGBA")


# ---------- hair drawn in every pose ----------

# Poses where the drawn body matches the hero's closely enough to measure how the drawn
# heads line up with his (the others are placed by the head alone, see posed_hair).
STEADY_POSES = ("idle1", "idle2", "idle3", "idle4", "walk1", "walk2", "walk3", "walk4")

# Poses that all wear one drawn pose's hair, set on each frame's head (and turned with it):
# the sheets draw the hair afresh in every pose, and differently each time (hanging in one,
# blown sideways in the next, a shade lighter or darker), so playing the poses redrew it on
# every frame and snapped it between shapes whenever an action began. Holding one drawing per
# family, the hair bobs and tilts with his head but keeps its shape: one at rest, one on the
# move (streaming back), one from behind while he climbs. Poses in no family (lying in a
# faint) keep their own. The pose to hold is the cleanest drawing of the family;
# HELD_HAIR_STYLE picks another for a style whose usual one came out badly.
HELD_HAIR = {
    "rest": ("idle1", ("idle1", "idle2", "idle3", "idle4", "walk1", "walk2", "walk3", "walk4",
                       "attack1", "attack2", "hit", "hurt", "land", "crouch", "slash1", "slash2",
                       "slash3", "levelup", "sit", "blink")),
    "moving": ("run2", ("run1", "run2", "run3", "run4", "jump", "fall")),
    "climbing": ("ladder1", ("rope1", "rope2", "ladder1", "ladder2", "climb_idle")),
}
HELD_HAIR_STYLE = {}
# A drawn tail or bun no further than this from the head (head radii) is pulled in to touch
# it; the sheets sometimes leave a gap between a ponytail and the head it hangs from.
HAIR_REACH = 0.4
# A drawn piece of hair this far or nearer from the rest of the hair (head radii) is moved in to
# touch it (a pigtail or tail drawn a little apart from the hair it hangs from); a loose piece
# smaller than HAIR_SPECK pixels is a speck of the sheet (a stray outline) and goes.
HAIR_JOIN = 0.35
HAIR_SPECK = 60
HAIR_STRAY = 0.05     # a far piece smaller than this share of the hair is not hair
# Hair under a hat: a loose piece centred this far below his head's centre (head radii) is a
# strand the sheet drew down his chest, not hair on his head.
HAT_HAIR_LOW = 1.2
HAT_HAIR_JOIN = 0.8   # and a loose piece this near the rest is moved in (joined)
# Styles drawn as a tail alone (no hair on top of the head): their crown comes from the style's
# one-piece hair under a hat, combed back with its strands, instead of a plain grey cap.
CROWN_FROM_HAT = ("ponytail",)


def held_hair_pose(style, n):
    """The drawn pose whose hair frame `n` wears for `style`: its family's held pose, or `n`."""
    for family, (pose, frames) in HELD_HAIR.items():
        if n in frames:
            return HELD_HAIR_STYLE.get(style, {}).get(family, pose)
    return n


def hair_mask(arr):
    """The hair in a cell of a hair_<style>_frames sheet (RGBA): everything near its greys
    that isn't the body it's drawn on (peach skin, sky-blue shorts)."""
    rgb = arr[..., :3].astype(float)
    mx, mn = rgb.max(2), rgb.min(2)
    solid = arr[..., 3] > 0
    grey = solid & (mx - mn < 0.15 * np.maximum(mx, 1)) & (mx > 60)
    skin = solid & (rgb[..., 0] > 150) & (rgb[..., 0] > rgb[..., 2] + 40)
    shorts = solid & (rgb[..., 2] > rgb[..., 0] + 40)
    hair = solid & ~skin & ~shorts & ss.dilate(grey, 3)
    lab, n = ss.label(hair)  # drop specks of the body's outline caught near the hair
    if n > 1:
        sizes = np.bincount(lab.ravel())[1:]
        hair &= np.isin(lab, 1 + np.nonzero(sizes >= sizes.max() * 0.05)[0])
    return hair


def head_link(cells, names, info, frames):
    """How a drawn head maps onto the hero's, measured on the steady poses: the scale against
    the two heads' radii, and where the drawn head's centre lands, in hero head radii from
    his head's centre."""
    ks, offs = [], []
    for n, fi, px in zip(names, info, frames):
        arr = cells.get(n)
        if n not in STEADY_POSES or arr is None:
            continue
        s, x, y = body_fit(arr, hair_mask(arr), px)
        c, r = drawn_head(arr)
        ks.append(s * r / fi["r"])
        offs.append((np.array([x, y]) + c * s - fi["head"]) / fi["r"])
    return float(np.median(ks)), np.median(np.array(offs), axis=0)


def hides_face(img, fi):
    """Whether hair covers most of the face (the middle of it, where the eyes are)."""
    at = fi["head"] + turned(FACE_AT, fi["tilt"]) * fi["r"]
    a = np.asarray(img)[..., 3] > 0
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    face = (xx - at[0]) ** 2 + (yy - at[1]) ** 2 <= (fi["r"] * 0.35) ** 2
    return a[face].mean() > 0.5


def posed_hair(arr, fi, link):
    """The hair of one drawn pose, shrunk to the hero's size, with the drawn head's centre on
    his. Returns (image, top-left)."""
    k, off = link
    hair = hair_mask(arr)
    c, r = drawn_head(arr)
    s = k * fi["r"] / r
    at = fi["head"] + turned(off, fi["tilt"]) * fi["r"] - c * s
    cut = arr.copy()
    cut[~hair] = 0
    grey = cut[..., :3].mean(2, keepdims=True)
    cut[..., :3] = np.repeat(grey, 3, 2).round().astype(np.uint8)
    return scaled(Image.fromarray(cut, "RGBA"), s), (int(round(at[0])), int(round(at[1])))



def above_fringe(hair):
    """Where the scalp may show on a head seen from the front: in each column, from the top
    of the drawn hair down to its lowest pixel there (the fringe). Below that is his forehead,
    which the scalp painted as a flat band of hair colour between the fringe and the eyes."""
    rows = np.arange(hair.shape[0])[:, None]
    any_ = hair.any(0)
    low = np.where(any_, hair.shape[0] - 1 - np.argmax(hair[::-1], 0), -1)
    return rows <= low[None, :]


def toned(img, grey):
    """A greyscale piece brightened or darkened so its middle grey is `grey` (0..255)."""
    arr = np.asarray(img).astype(float)
    k = grey / max(hair_grey(img), 1.0)
    arr[..., :3] = (arr[..., :3] * k).clip(0, 255)
    return Image.fromarray(arr.round().astype(np.uint8), "RGBA")


def pulled_in(img, fi):
    """Drawn hair with any piece that floats just off his head (a ponytail drawn a little
    behind the head it hangs from) moved straight in until it touches the head."""
    arr = np.asarray(img).copy()
    solid = arr[..., 3] > 0
    lab, n = ss.label(solid)
    if n < 1:
        return img
    yy, xx = np.mgrid[0:solid.shape[0], 0:solid.shape[1]]
    dist = np.hypot(xx - fi["head"][0], yy - fi["head"][1]) / fi["r"] - 1.0  # head radii off the head
    out = np.zeros_like(arr)
    for i in range(1, n + 1):
        part = lab == i
        gap = dist[part].min()
        if gap <= 0 or gap > HAIR_REACH:
            out[part] = arr[part]
            continue
        # the nearest point of the piece, moved in along the line to the head's centre
        k = np.argmin(np.where(part, dist, np.inf))
        py, px_ = divmod(k, solid.shape[1])
        v = np.array(fi["head"]) - (px_, py)
        step = v / np.linalg.norm(v) * gap * fi["r"]
        dx, dy = int(round(step[0])), int(round(step[1]))
        ys, xs = np.nonzero(part)
        ty, tx = ys + dy, xs + dx
        ok = (ty >= 0) & (ty < solid.shape[0]) & (tx >= 0) & (tx < solid.shape[1])
        out[ty[ok], tx[ok]] = arr[ys[ok], xs[ok]]
    return Image.fromarray(out, "RGBA")

def joined(img, fi, reach=HAIR_JOIN, behind=None):
    """Drawn hair in one piece: every loose piece near the main hair (`reach` head radii) moved
    straight in until it touches it, so no tail floats apart; specks (HAIR_SPECK) dropped. A
    moved piece goes behind `behind` (a mask: his face), hidden where it would cover it."""
    arr = np.asarray(img).copy()
    lab, n = ss.label(arr[..., 3] > 0)
    if n < 2:
        return img
    sizes = np.bincount(lab.ravel())[1:]
    biggest = int(sizes.argmax()) + 1
    main = lab == biggest
    out = arr.copy()
    out[(lab > 0) & ~main, 3] = 0
    ys0, xs0 = np.nonzero(main)
    reach = reach * fi["r"]
    for i in range(1, n + 1):
        part = lab == i
        if i == biggest or sizes[i - 1] < HAIR_SPECK:
            continue
        ys, xs = np.nonzero(part)
        # the closest pair of points between the piece and the main hair (sampled for speed)
        step = max(len(ys) // 400, 1)
        py, px_ = ys[::step], xs[::step]
        d = np.hypot(px_[:, None] - xs0[None, ::4], py[:, None] - ys0[None, ::4])
        k = np.unravel_index(d.argmin(), d.shape)
        gap = d[k]
        if gap > reach:
            if sizes[i - 1] >= sizes.max() * HAIR_STRAY:  # big and far: drawn apart on purpose
                out[part] = arr[part]
            continue  # else a bit of the body's outline caught with the hair (an ear, a hand)
        v = np.array([xs0[::4][k[1]] - px_[k[0]], ys0[::4][k[1]] - py[k[0]]], float)
        move = v / max(np.linalg.norm(v), 1e-6) * max(gap - 1.0, 0.0)
        ty, tx = ys + int(round(move[1])), xs + int(round(move[0]))
        ok = (ty >= 0) & (ty < arr.shape[0]) & (tx >= 0) & (tx < arr.shape[1])
        keep = out[ty[ok], tx[ok], 3] == 0  # under the main hair where they overlap
        if behind is not None:
            keep &= ~behind[ty[ok], tx[ok]]
        out[ty[ok][keep], tx[ok][keep]] = arr[ys[ok][keep], xs[ok][keep]]
    return Image.fromarray(out, "RGBA")

def no_low_strands(img, fi):
    """A hair-under-a-hat layer without loose pieces hanging down on his body (HAT_HAIR_LOW);
    the pieces at his head (a pigtail beside his cheek) stay."""
    arr = np.asarray(img).copy()
    lab, n = ss.label(arr[..., 3] > 0)
    if n < 2:
        return img
    sizes = np.bincount(lab.ravel())[1:]
    _, above = head_axes(arr.shape, fi, fi["head"])
    for i in range(1, n + 1):
        part = lab == i
        if i != int(sizes.argmax()) + 1 and np.median(above[part]) < -HAT_HAIR_LOW:
            arr[part, 3] = 0
    return Image.fromarray(arr, "RGBA")


# ---------- building the hair layers ----------

def one_piece_layers(hero, hair):
    """Writes the hair layers of every style from its one-piece sheet pieces (paperdoll_hair):
    hair_<style>, _back and _hat. Returns the front and under-a-hat frames per style, which the
    styles drawn in every pose fall back on (posed_layers)."""
    names, info, frames, index, anims = hero.names, hero.info, hero.frames, hero.index, hero.anims
    fw, fh, r, blank = hero.fw, hero.fh, hero.r, hero.blank
    # hair: one transform per style from its front piece, used for all four pieces
    old, old_hat = {}, {}
    for style in HAIRSTYLES:
        front = hair[style + "_front"]
        s = r * HAIR_WIDTH / front.img.width
        head_cell = (front.x + front.img.width / 2, front.y + (r * (1 + HAIR_LIFT)) / s)
        grey = hair_grey(front.img)
        out = {"": [], "_back": [], "_hat": []}
        for n, fi, px in zip(names, info, frames):
            back_view = n in BACK_VIEW
            fs = s * fi["r"] / r  # heads are drawn a little bigger or smaller in some poses
            pieces = {"": "_behind" if back_view else "_front", "_back": None if back_view else "_back",
                      "_hat": "_behind" if back_view else "_hat"}
            for layer, which in pieces.items():
                canvas = blank()
                p = hair.get(style + which) if which else None
                if p:
                    if layer != "_back":
                        canvas.alpha_composite(scalp(px, fi, back_view, grey))
                    img = scaled(p.img, fs)
                    anchor = ((head_cell[0] - p.x) * fs, (head_cell[1] - p.y) * fs)
                    place(canvas, img, anchor, fi["head"], fi["tilt"])
                    if layer == "_hat" and not back_view:  # the sheet draws a blank face in it
                        # a pigtail beside his cheek, cut off from the hair by his face: tucked
                        # in behind the cheek
                        canvas = joined(no_low_strands(bare_face(canvas, px, fi), fi), fi,
                                        HAT_HAIR_JOIN, face_zone(px, fi))
                out[layer].append(canvas)
        old[style] = out[""]
        old_hat[style] = out["_hat"]
        for layer, fr in out.items():
            if any(im.getbbox() for im in fr):
                save_layer(f"hair_{style}{layer}", fr, fw, fh, index, anims, grey=True)
    return old, old_hat


def posed_layers(hero, old, old_hat):
    """Writes hair_<style> again for each style with a sheet drawn in every pose
    (hair_<style>_frames), and removes its _back layer."""
    names, info, frames, index, anims = hero.names, hero.info, hero.frames, hero.index, hero.anims
    fw, fh, blank, body_cells = hero.fw, hero.fh, hero.blank, hero.body_cells
    # hairstyles drawn in every pose (hair_<style>_frames sheets) replace the front piece
    for style in HAIRSTYLES:
        manifest = os.path.join(ss.SHEETS, f"hair_{style}_frames.json")
        if os.path.exists(manifest):
            drawn = cut(f"hair_{style}_frames")
            cells = {n: without_shorts(drawn[body_cells[n]], body_cells[n]) for n in names if body_cells[n] in drawn}
            link = head_link(cells, names, info, frames)
            # every pose's hair in the held rest drawing's grey, so it doesn't flicker lighter
            # or darker from one family (or lone pose) to the next
            rest = held_hair_pose(style, HELD_HAIR["rest"][0])
            target = hair_grey(Image.fromarray(cells[rest] * hair_mask(cells[rest])[..., None])) if rest in cells else None
            out = []
            for n, fi, px in zip(names, info, frames):
                canvas = blank()
                drawn_hair = blank()
                drawn_as = held_hair_pose(style, n)
                if drawn_as not in cells:
                    drawn_as = n
                if drawn_as in cells:
                    hair_img, at = posed_hair(cells[drawn_as], fi, link)
                    if target is not None:
                        hair_img = toned(hair_img, target)
                    # a held drawing turns with his head (as far as this frame's head is turned
                    # from the held pose's)
                    turn = fi["tilt"] - info[index[drawn_as]]["tilt"]
                    place(drawn_hair, hair_img, (fi["head"][0] - at[0], fi["head"][1] - at[1]), fi["head"], turn)
                    drawn_hair = joined(pulled_in(drawn_hair, fi), fi)
                # where the drawn hair covers the scalp, the scalp only just around it (it fills
                # slivers where the heads don't quite line up, and doesn't show as a band under a
                # high hairline); where it leaves the crown bald (a ponytail drawn as the tail
                # alone), all of it, so the top of his head is hair, with the strands of the
                # style's one-piece crown on it for CROWN_FROM_HAT; in the drawn hair's own grey,
                # so it doesn't show as a darker cap
                tone = hair_grey(drawn_hair) if drawn_hair.getbbox() else 128.0
                bald = np.asarray(scalp(px, fi, n in BACK_VIEW, tone)).copy()
                near = ss.dilate(np.asarray(drawn_hair)[..., 3] > 0, 3)
                top = bald[..., 3] > 0
                covered = top.any() and (near & top).sum() > top.sum() * SCALP_COVERED
                if covered:
                    bald[~near, 3] = 0
                crown = None
                if style in CROWN_FROM_HAT and not covered and n not in BACK_VIEW:
                    crown = np.asarray(toned(old_hat[style][index[n]], tone)).copy()
                    crown[~top, 3] = 0
                if n not in BACK_VIEW:  # facing us, no scalp shows on his forehead under the fringe
                    hair_now = np.asarray(drawn_hair)[..., 3] > 0
                    if crown is not None:
                        hair_now |= crown[..., 3] > 0
                    under = above_fringe(hair_now)
                    bald[~under, 3] = 0
                    if crown is not None:
                        crown[~under, 3] = 0
                canvas.alpha_composite(Image.fromarray(bald, "RGBA"))
                if crown is not None:
                    canvas.alpha_composite(Image.fromarray(crown, "RGBA"))
                if n in BACK_VIEW or not hides_face(drawn_hair, fi):
                    canvas.alpha_composite(drawn_hair)
                    canvas = joined(canvas, fi)  # and no specks of the crown or scalp left loose
                else:  # drawn in a pose too unlike his (lying face down): the one-piece hair
                    canvas = old[style][index[n]]
                out.append(canvas)
            save_layer(f"hair_{style}", out, fw, fh, index, anims, grey=True)
            for gone in ("_back",):  # the drawn poses include the hair behind the head
                for path in (os.path.join(LAYERS, f"hair_{style}{gone}.png"), os.path.join(ANIMS, f"hair_{style}{gone}.tres")):
                    if os.path.exists(path):
                        os.remove(path)
