"""Sets how Godot imports the game's art, by folder, in each picture's .import file.

World art is big (backdrops, rooms, buildings, monster strips), so it is stored GPU-compressed
(BC7 on PC and the Steam Deck: a quarter of the memory with nearly the same look) with
mipmaps, so art drawn smaller than it was cut doesn't shimmer when the camera moves. UI, item
and skill icons stay lossless and the hero's layers stay as they are (their placements are
measured from the exact pixels).

Run it after slicing new art, then `godot --headless --import --path .` to rebuild the
imports. `--check` lists pictures that don't match and exits 1 (the tests run the same check).

  python3 tools/art/import_settings.py [--check]
"""
import argparse, glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPRITES = os.path.join(ROOT, "assets", "sprites")
## Folders stored GPU-compressed with mipmaps.
COMPRESSED = ["backgrounds", "rooms", "buildings", "monsters", "tiles"]
## Folders kept lossless but given mipmaps (smaller world art drawn at many sizes).
MIPMAPPED = ["npcs", "props", "pets", "effects", "projectiles"]
COMPRESSED_PARAMS = {"compress/mode": "2", "compress/high_quality": "true", "mipmaps/generate": "true"}
MIPMAPPED_PARAMS = {"compress/mode": "0", "compress/high_quality": "false", "mipmaps/generate": "true"}


def wanted(folder):
    if folder in COMPRESSED:
        return COMPRESSED_PARAMS
    if folder in MIPMAPPED:
        return MIPMAPPED_PARAMS
    return None


def imports():
    """(path of a .import file, the params it should have) for every picture in a listed folder."""
    for folder in COMPRESSED + MIPMAPPED:
        for path in sorted(glob.glob(os.path.join(SPRITES, folder, "**", "*.png.import"), recursive=True)):
            yield path, wanted(folder)


def apply(text, params):
    for key, value in params.items():
        text = re.sub(rf"^{re.escape(key)}=.*$", f"{key}={value}", text, flags=re.M)
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    wrong = []
    missing = [p for f in COMPRESSED + MIPMAPPED
               for p in glob.glob(os.path.join(SPRITES, f, "**", "*.png"), recursive=True)
               if not os.path.exists(p + ".import")]
    for path, params in imports():
        text = open(path).read()
        new = apply(text, params)
        if new != text:
            wrong.append(os.path.relpath(path, ROOT))
            if not a.check:
                open(path, "w").write(new)
    if a.check:
        for p in wrong + [os.path.relpath(m, ROOT) + " (not imported yet)" for m in missing]:
            print(p)
        sys.exit(1 if wrong or missing else 0)
    print(f"{len(wrong)} imports changed" + (f"; {len(missing)} pictures not imported yet: run godot --import, then this again" if missing else ""))


if __name__ == "__main__":
    main()
