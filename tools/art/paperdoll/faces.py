"""Faces: each face's expressions put on the head in every frame, with the irises split off
onto their own layer for the eye colour."""
from .common import *  # noqa: F401,F403


def chibi(piece, normal):
    """A face piece with bigger eyes (EYE_SCALE), each grown about its centre on the face's
    normal expression, so every expression's eyes grow in the same place; the nose, mouth and
    cheeks below EYE_LINE stay as drawn, which leaves them small and close under the eyes."""
    if EYE_SCALE == 1:
        return piece
    a = np.asarray(piece.img)
    n = np.asarray(normal.img)[..., 3] > 0
    w, h = normal.img.size
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    left = xx + piece.x - normal.x < w / 2
    eyes = yy + piece.y - normal.y < EYE_LINE * h
    ny, nx = np.nonzero(n)
    pad = int(max(w, h) * (EYE_SCALE - 1))
    out = Image.new("RGBA", (a.shape[1] + 2 * pad, a.shape[0] + 2 * pad))
    rest = a.copy()
    rest[eyes] = 0
    out.alpha_composite(Image.fromarray(rest, "RGBA"), (pad, pad))
    for is_left in (True, False):
        part = a.copy()
        part[~(eyes & (left == is_left))] = 0
        on = (ny < EYE_LINE * h) & ((nx < w / 2) == is_left)
        if not part[..., 3].any() or not on.any():
            continue
        # the eye's centre on the normal face, in this piece's pixels
        cx = (nx[on].min() + nx[on].max()) / 2 + normal.x - piece.x
        cy = (ny[on].min() + ny[on].max()) / 2 + normal.y - piece.y
        img = Image.fromarray(part, "RGBA")
        big = img.resize((round(img.width * EYE_SCALE), round(img.height * EYE_SCALE)), Image.NEAREST)
        out.alpha_composite(big, (int(round(pad + cx - cx * EYE_SCALE)), int(round(pad + cy - cy * EYE_SCALE))))
    box = out.getbbox()
    return Drawn(out.crop(box), piece.x - pad + box[0], piece.y - pad + box[1])


def face_layers(hero, faces):
    """Writes face_<face> and face_<face>_eyes for every face (paperdoll_faces pieces)."""
    names, info, index, anims = hero.names, hero.info, hero.index, hero.anims
    fw, fh, r, blank = hero.fw, hero.fh, hero.r, hero.blank
    # faces: the irises (drawn in greys) go on their own layer for the eye colour
    for face in FACES:
        normal = faces[face + "_normal"]
        s = r * FACE_WIDTH / normal.img.width
        centre = (normal.x + normal.img.width / 2, normal.y + normal.img.height / 2)
        out, eyes = [], []
        for n, fi in zip(names, info):
            canvas, iris = blank(), blank()
            if n not in BACK_VIEW:
                p = chibi(faces[face + "_" + EXPRESSIONS.get(n, "normal")], normal)
                img = scaled(p.img, s)
                anchor = ((centre[0] - p.x) * s, (centre[1] - p.y) * s)
                at = fi["head"] + turned(FACE_AT, fi["tilt"]) * fi["r"]
                place(canvas, img, anchor, at, fi["tilt"])
                px = np.asarray(canvas).copy()
                rgb = px[..., :3].astype(float) / 255
                mx, mn = rgb.max(2), rgb.min(2)
                grey = (px[..., 3] > 0) & (mx - mn < 0.1) & (mx > 0.28) & (mx < 0.8)
                ip = np.zeros_like(px)
                ip[grey] = px[grey]
                px[grey] = 0
                canvas, iris = Image.fromarray(px, "RGBA"), Image.fromarray(ip, "RGBA")
            out.append(canvas)
            eyes.append(iris)
        save_layer(f"face_{face}", out, fw, fh, index, anims, tinted=False)
        save_layer(f"face_{face}_eyes", eyes, fw, fh, index, anims)
