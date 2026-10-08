"""Turn the hand-drawn character grids in the .txt files into images.

Each grid starts with a "# name" line; every following character is one pixel,
looked up in PAL ('.' is transparent)."""
from PIL import Image

from pal import PAL


def grid_img(rows, pal=PAL):
    w = max(len(r) for r in rows)
    im = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch not in pal:
                raise ValueError("unknown pixel %r at %d,%d" % (ch, x, y))
            c = pal[ch]
            if c:
                im.putpixel((x, y), tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) + (255,))
    return im


def load_all(path):
    blocks, cur = {}, None
    for line in open(path).read().splitlines():
        if line.startswith("#"):
            cur = line[1:].strip()
            blocks[cur] = []
        elif cur and line.strip():
            blocks[cur].append(line.rstrip())
    return blocks
