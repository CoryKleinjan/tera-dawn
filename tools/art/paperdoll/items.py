"""Gear with art of its own, drawn from its icon (Cory 2026-10-11: a piece looks the same worn
as in the bag): each piece's sheet of the body wearing it in every pose, in the piece's own
colours, lifted off the body and fitted onto the hero's frames as worn_item_<id>.

    art/source/worn/<item id>.png   the body sheet (paperdoll_body.png's grid and poses) with
                                    the hero wearing that one top, bottom, pair of shoes,
                                    gloves or cape (Gemini edits, tools/art/gemini_pass.json)
    art/sheets/shield_backs.json    the back of each shield (cells named by item id); its
                                    front is its icon

Which place a piece is worn at comes from its item data (EquipDef.slot). Unlike the greyscale
cuts (worn.py) these keep their colours: the game draws them untinted (Paperdoll.own_art; shields are pieces, see pieces.py)."""
from .common import *  # noqa: F401,F403
from .common import _paste
from .body import BODY_PIECES, body_fit, drawn_head, shorts_mask
from .gloves import posed_gloves
from .weapons import icon_cut
from .pieces import pose, save_piece

WORN_DIR = os.path.join(ROOT, "art", "source", "worn")
# EquipDef.Slot numbers of the places an item sheet can dress (scripts/data/equip_def.gd)
SLOT_PLACES = {2: "top", 3: "bottom", 4: "shoes", 5: "gloves", 6: "cape"}
# a pixel of an item sheet is the body's (not the piece's) when a body-sheet pixel this close
# (sheet pixels) has nearly its colour (RGB distance); Gemini redraws the body a pixel or two off
BODY_NEAR = 3
BODY_SAME = 34


def item_places():
    """item id -> the place it's worn (top, bottom, shoes, gloves, cape), from its item data."""
    out = {}
    for folder, _, files in os.walk(ITEMS):
        for f in files:
            if f.endswith(".tres"):
                with open(os.path.join(folder, f)) as fh:
                    text = fh.read()
                item, slot = re.search(r'^id = &"(\w+)"', text, re.M), re.search(r'^slot = (\d+)', text, re.M)
                if item and slot and int(slot.group(1)) in SLOT_PLACES:
                    out[item.group(1)] = SLOT_PLACES[int(slot.group(1))]
    return out


def item_sheet(item):
    """The cells of an item's sheet, cut on the body sheet's grid at its scale."""
    with open(BODY_MANIFEST) as fh:
        man = json.load(fh)
    man.pop("sets", None)
    man.update(source=os.path.relpath(os.path.join(WORN_DIR, item + ".png"), ROOT), save=False,
               out_dir=os.path.join("art", "build", "worn", item))
    tmp = os.path.join(ROOT, "art", "build", "worn", item + ".json")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    with open(tmp, "w") as fh:
        json.dump(man, fh)
    sprites = {}
    ss.process(tmp, sprites=sprites)
    return {k.split(":", 1)[1]: Piece(v) for k, v in sprites.items()}


def body_alike(piece, cell):
    """Where a cell of an item sheet still shows the bare body (a bool mask the piece's size):
    a body-sheet pixel within BODY_NEAR has nearly the same colour."""
    arr = np.asarray(piece.img).astype(int)
    h, w = arr.shape[:2]
    b = BODY_PIECES.get(cell)
    out = np.zeros((h, w), bool)
    if b is None:
        return out
    body = np.zeros((h, w, 4), int)
    bx, by = b.x - piece.x, b.y - piece.y
    src = np.asarray(b.img).astype(int)
    y0, x0 = max(by, 0), max(bx, 0)
    y1, x1 = min(by + src.shape[0], h), min(bx + src.shape[1], w)
    if y1 > y0 and x1 > x0:
        body[y0:y1, x0:x1] = src[y0 - by:y1 - by, x0 - bx:x1 - bx]
    solid = arr[..., 3] > 0
    for dy in range(-BODY_NEAR, BODY_NEAR + 1):
        for dx in range(-BODY_NEAR, BODY_NEAR + 1):
            sh = np.roll(np.roll(body, dy, 0), dx, 1)
            near = (sh[..., 3] > 0) & (np.abs(sh[..., :3] - arr[..., :3]).sum(2) < BODY_SAME * 1.7)
            out |= near & solid
    return out


def piece_mask(piece, cell, place):
    """The worn piece in a cell of its sheet: what isn't the bare body, without the (bald)
    head, specks and lone bits of outline. A bottom also takes the body's shorts it is
    drawn over, so none of the grey shorts shows at its edges."""
    arr = np.asarray(piece.img)
    mask = (arr[..., 3] > 0) & ~body_alike(piece, cell)
    if place == "bottom":
        mask |= shorts_mask(piece, cell, 2) & (arr[..., 3] > 0)
    rgb = arr[..., :3].astype(int)
    skin = arr.copy()
    skin[..., 3] = np.where((rgb[..., 0] > 150) & (rgb[..., 0] > rgb[..., 2] + 40), arr[..., 3], 0)
    c, r = drawn_head(skin)
    yy, xx = np.mgrid[0:arr.shape[0], 0:arr.shape[1]]
    mask &= (xx - c[0]) ** 2 + (yy - c[1]) ** 2 > (r * 1.05) ** 2
    lab, n = ss.label(mask)
    if not n:
        return mask
    sizes = np.bincount(lab.ravel())[1:]
    keep = sizes >= max(sizes.max() * 0.04, 12)
    mask = np.isin(lab, 1 + np.nonzero(keep)[0])
    # close pinholes the body test punched in it (a highlight that matched the body's)
    return ~ss.dilate(~ss.dilate(mask, 1), 1) | mask


def posed_item(piece, cell, px, place):
    """One pose of an item sheet, lifted off the body in its own colours and fitted onto the
    hero's frame. Returns (image, top-left), or None if nothing was found."""
    arr = np.asarray(piece.img)
    if not (arr[..., 3] > 0).any():
        return None
    ys = np.nonzero(arr[..., 3] > 0)[0]
    ours = np.nonzero(px[..., 3] > 127)[0]
    base = (ours.max() - ours.min() + 1) / (ys.max() - ys.min() + 1)
    s, x, y = body_fit(arr, np.zeros(arr.shape[:2], bool), px, [base * k for k in (0.92, 0.96, 1.0, 1.04, 1.08)])
    mask = piece_mask(piece, cell, place) & (arr[..., 3] > 0)
    if not mask.any():
        return None
    cut = arr.copy()
    cut[~mask] = 0
    return scaled(Image.fromarray(cut, "RGBA"), s), (int(round(x)), int(round(y)))


def item_layers(hero, rig_frames):
    """Writes worn_item_<id> for every item sheet in art/source/worn/ (a cape also gets
    worn_item_<id>_behind: the part hanging behind him)."""
    if not os.path.isdir(WORN_DIR):
        return
    names, frames, index, anims = hero.names, hero.frames, hero.index, hero.anims
    fw, fh, r, blank, body_cells, spec = hero.fw, hero.fh, hero.r, hero.blank, hero.body_cells, hero.spec
    places = item_places()
    for f in sorted(os.listdir(WORN_DIR)):
        item = f[:-4]
        if not f.endswith(".png") or item not in places:
            continue
        place, drawn = places[item], item_sheet(item)
        front, behind = [], []
        for n, px, entry in zip(names, frames, rig_frames):
            over, back = blank(), blank()
            cell = body_cells[n]
            if place == "gloves":
                points = [entry[k] for k in ("grip", "shield") if k in entry]
                if cell in drawn and points and n not in BACK_VIEW:
                    p = drawn[cell]
                    arr = np.asarray(p.img).copy()
                    arr[~piece_mask(p, cell, place), 3] = 0
                    for img, at in posed_gloves(arr, px, points, r * GLOVE_REACH, keep_colour=True):
                        _paste(over, img, *at)
            elif cell in drawn:
                worn = posed_item(drawn[cell], cell, px, place)
                if worn:
                    _paste(over, worn[0], *worn[1])
                    if place == "cape" and n not in BACK_VIEW:
                        # what the drawn body hides is behind him: the part off his outline
                        # hangs behind the body, the part over it (collar, clasp) in front
                        arr = np.asarray(over)
                        inside = px[..., 3] > 127
                        out_part, in_part = arr.copy(), arr.copy()
                        out_part[inside, 3] = 0
                        in_part[~inside, 3] = 0
                        back, over = Image.fromarray(out_part, "RGBA"), Image.fromarray(in_part, "RGBA")
            front.append(over)
            behind.append(back)
        save_layer(f"worn_item_{item}", front, fw, fh, index, anims, tinted=False)
        if place == "cape":
            save_layer(f"worn_item_{item}_behind", behind, fw, fh, index, anims, tinted=False)


# ---------- shields ----------

def shield_layers(hero, rig_frames):
    """Writes the piece shield_item_<id> for every shield on shield_backs.json: its back on his
    far arm, behind his body, tucked in until about SHIELD_SHOWS of it shows past him, and its
    face (the icon) on his back while he climbs."""
    if not os.path.exists(os.path.join(ss.SHEETS, "shield_backs.json")):
        return
    r = hero.r
    backs = cut("shield_backs")
    fronts = {}
    for f in sorted(os.listdir(ss.SHEETS)):
        if f.startswith(ICON_SHEETS) and f.endswith(".json"):
            fronts.update(icon_cut(f[:-5], set(backs)))
    for item, back in backs.items():
        front = fronts.get(item)
        views = {"back": scaled(back.img, r * SHIELD_HEIGHT / back.img.height)}
        if front:
            views["front"] = scaled(front.img, r * SHIELD_HEIGHT / front.img.height)
        frames = []
        for n, px, entry in zip(hero.names, hero.frames, rig_frames):
            if "shield" not in entry or (n in BACK_VIEW and not front):
                frames.append(None)
            elif n in BACK_VIEW:
                frames.append(pose("front", entry["shield"]))
            else:
                frames.append(pose("back", tucked(views["back"], entry["shield"], px, entry["neck"]), behind=True))
        save_piece(f"shield_item_{item}", {v: (img, (img.width / 2, img.height / 2)) for v, img in views.items()}, frames)


def tucked(img, at, px, neck):
    """Where a shield behind his body goes: from the rig's shield point `at`, moved sideways
    toward his middle (the neck's x) until about SHIELD_SHOWS of it shows past his outline
    (Cory 2026-10-11: mostly hidden by him); left where it is if less shows already."""
    body = px[..., 3] > 127
    solid = np.asarray(img)[..., 3] > 0
    total = max(int(solid.sum()), 1)
    toward = -1.0 if at[0] > neck[0] else 1.0
    best = None
    for step in range(0, int(abs(at[0] - neck[0])) + 1):
        x = at[0] + toward * step
        x0, y0 = int(round(x - img.width / 2)), int(round(at[1] - img.height / 2))
        shown = 0
        ys, xs = np.nonzero(solid)
        fx, fy = xs + x0, ys + y0
        ok = (fx >= 0) & (fx < body.shape[1]) & (fy >= 0) & (fy < body.shape[0])
        shown = int((~body[fy[ok], fx[ok]]).sum()) + int((~ok).sum())
        share = shown / total
        if best is None or abs(share - SHIELD_SHOWS) < abs(best[0] - SHIELD_SHOWS):
            best = (share, x)
        if share <= SHIELD_SHOWS:
            break
    return (best[1], at[1])
