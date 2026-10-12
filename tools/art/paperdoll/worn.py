"""Worn gear lifted off sheets of the body wearing it in every pose (tops, bottoms, shoes
and the cape), and the shields put on the rig's shield point."""
from .common import *  # noqa: F401,F403
from .common import _paste
from .body import body_fit, drawn_head, shorts_mask


# ---------- clothes drawn on the body ----------

def worn_mask(arr):
    """A worn piece in a cell of a sheet of the body wearing it (RGBA): its greys and their
    outline, without the body (peach skin, a cream undershirt, sky-blue shorts) or coloured
    fringe left by the background."""
    rgb = arr[..., :3].astype(float)
    mx, mn = rgb.max(2), rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1)
    solid = arr[..., 3] > 0
    grey = solid & (sat < 0.15) & (mx > 60)
    skin = solid & (rgb[..., 0] > 150) & (rgb[..., 0] > rgb[..., 2] + 40)
    shorts = solid & (rgb[..., 2] > rgb[..., 0] + 40)
    return solid & ~skin & ~shorts & ss.dilate(grey, 2) & ((sat < 0.3) | (mx < 90))


def posed_worn(piece, cell, px, place):
    """The clothes of one drawn pose of a <place>_<style>_frames sheet (the body wearing a top,
    a bottom or shoes), lifted off the body in greys and fitted onto the hero's frame. The
    sheets keep the body's grey shorts: a bottom is drawn over them, so they count as part of
    it; for a top or shoes they're the body, so the shorts' dark greys are left out (a light
    tunic hem over them stays). Returns (image, top-left), or None if nothing was found."""
    arr = np.asarray(piece.img)
    if not (arr[..., 3] > 0).any():
        return None
    ys = np.nonzero(arr[..., 3] > 0)[0]
    ours = np.nonzero(px[..., 3] > 127)[0]
    base = (ours.max() - ours.min() + 1) / (ys.max() - ys.min() + 1)
    s, x, y = body_fit(arr, np.zeros(arr.shape[:2], bool), px, [base * k for k in (0.92, 0.96, 1.0, 1.04, 1.08)])
    mask = worn_mask(arr)
    # the pale fringe some sheets leave around the whole figure isn't the clothes
    mask &= ~(ss.dilate(arr[..., 3] == 0, 2) & (arr[..., :3].max(2) > WORN_FRINGE))
    # nothing is worn on the (bald, skin) head: its outline is the body's
    rgb = arr[..., :3].astype(int)
    skin = arr.copy()
    skin[..., 3] = np.where((rgb[..., 0] > 150) & (rgb[..., 0] > rgb[..., 2] + 40), arr[..., 3], 0)
    c, r = drawn_head(skin)
    yy, xx = np.mgrid[0:arr.shape[0], 0:arr.shape[1]]
    mask &= (xx - c[0]) ** 2 + (yy - c[1]) ** 2 > (r * 1.05) ** 2
    if place != "bottom":
        mask &= ~(shorts_mask(piece, cell, 4) & (arr[..., :3].max(2) < WORN_SHORTS_GREY))
    # drop specks and bits of the body's outline caught off the clothes (pieces mostly of
    # outline darks rather than the clothes' own greys)
    lab, n = ss.label(mask)
    if not n:
        return None
    sizes = np.bincount(lab.ravel())[1:]
    filled = np.bincount(lab.ravel(), weights=(arr[..., :3].max(2) >= WORN_OUTLINE).ravel())[1:]
    keep = (sizes >= max(sizes.max() * 0.05, 6)) & (filled >= sizes * 0.4)
    mask = np.isin(lab, 1 + np.nonzero(keep)[0])
    if not mask.any():
        return None
    cut = arr.copy()
    cut[~mask] = 0
    # the sheets draw a piece paler in some poses than others: each pose's greys are brought
    # to the same middle grey, so the tinted piece doesn't flicker as he moves
    grey = cut[..., :3].astype(float).mean(2, keepdims=True)
    grey *= 128 / max(np.median(grey[mask]), 1)
    cut[..., :3] = np.repeat(grey, 3, 2).clip(0, 255).round().astype(np.uint8)
    return scaled(Image.fromarray(cut, "RGBA"), s), (int(round(x)), int(round(y)))


def worn_sheets():
    """(place, style) of every clothes sheet there is: art/sheets/<place>_<style>_frames.json
    for the places in WORN_PLACES (the body wearing that piece in every pose)."""
    out = []
    for f in sorted(os.listdir(ss.SHEETS)):
        m = re.fullmatch(r"(%s)_(\w+)_frames\.json" % "|".join(WORN_PLACES), f)
        if m and m.group(2) not in WORN_BROKEN:
            out.append((m.group(1), m.group(2)))
    return out


# ---------- building the worn layers ----------

def cape_layers(hero):
    """Writes cape (behind him) and cape_front from the cape_frames sheet."""
    names, frames, index, anims = hero.names, hero.frames, hero.index, hero.anims
    fw, fh, blank, body_cells = hero.fw, hero.fh, hero.blank, hero.body_cells
    # cape: lifted off the body wearing it (cape_frames), like the clothes. What the drawn body
    # hides is behind him, so the part outside his outline goes behind the body and the part
    # over it (collar and clasp, a fold over the shoulder) in front; seen from behind (climbing)
    # all of it hangs over his back
    capes = cut("cape_frames")
    behind, front = [], []
    for n, px in zip(names, frames):
        back, over = blank(), blank()
        cell = body_cells[n]
        worn = posed_worn(capes[cell], cell, px, "cape") if cell in capes else None
        if worn:
            whole = blank()
            _paste(whole, worn[0], *worn[1])
            if n in BACK_VIEW:
                over = whole
            else:
                arr = np.asarray(whole)
                inside = px[..., 3] > 127
                out_part, in_part = arr.copy(), arr.copy()
                out_part[inside, 3] = 0
                in_part[~inside, 3] = 0
                back, over = Image.fromarray(out_part, "RGBA"), Image.fromarray(in_part, "RGBA")
        behind.append(back)
        front.append(over)
    save_layer("cape", behind, fw, fh, index, anims)
    save_layer("cape_front", front, fw, fh, index, anims)
    for gone in ("cape_back_view",):  # the earlier name of cape_front
        for path in (os.path.join(LAYERS, f"{gone}.png"), os.path.join(ANIMS, f"{gone}.tres")):
            if os.path.exists(path):
                os.remove(path)


def shield_layers(hero, rig_frames):
    """Writes shield_round and shield_kite, each on the rig's shield point."""
    names, index, anims = hero.names, hero.index, hero.anims
    fw, fh, r, blank, body_cells = hero.fw, hero.fh, hero.r, hero.blank, hero.body_cells
    # shields, on the arm (or on the back in back views): one picture per pose, put on the rig's
    # shield point. The round sheet is on the body sheet's grid (cells named by pose); the kite
    # sheet has its own layout, so its manifest's "poses" names the cell each pose uses.
    for style in ("round", "kite"):
        drawn = cut(f"paperdoll_shield_{style}")
        with open(os.path.join(ss.SHEETS, f"paperdoll_shield_{style}.json")) as f:
            poses = json.load(f).get("poses", body_cells)
        s_sh = r * SHIELD_HEIGHT / drawn[poses["idle1"]].img.height
        out = []
        for n, entry in zip(names, rig_frames):
            canvas = blank()
            p = drawn.get(poses.get(n, poses.get(body_cells[n], "")))  # a frame reusing a cell (blink) uses its pose
            if p and "shield" in entry:
                img = scaled(p.img, s_sh)
                place(canvas, img, (img.width / 2, img.height / 2), entry.get("shield_at", entry["shield"]))
            out.append(canvas)
        save_layer(f"shield_{style}", out, fw, fh, index, anims)


def clothes_layers(hero):
    """Writes <place>_<style> for every clothes sheet (worn_sheets)."""
    names, frames, index, anims = hero.names, hero.frames, hero.index, hero.anims
    fw, fh, blank, body_cells = hero.fw, hero.fh, hero.blank, hero.body_cells
    # tops, bottoms and shoes, one layer per cut (EquipDef.worn_style)
    for where, style in worn_sheets():
        drawn = cut(f"{where}_{style}_frames")
        out = []
        for n, px in zip(names, frames):
            canvas = blank()
            cell = body_cells[n]
            if cell in drawn:
                worn = posed_worn(drawn[cell], cell, px, where)
                if worn:
                    _paste(canvas, worn[0], *worn[1])
            out.append(canvas)
        save_layer(f"{where}_{style}", out, fw, fh, index, anims)
