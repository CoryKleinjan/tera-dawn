# Art

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add art

Drop the sheet in `art/source/`, write a manifest in `art/sheets/`, and run
`python3 tools/art/slice_sheets.py <name>`. `art/sheets/README.md` explains the manifest. The
cut sprites land in `assets/sprites/`, ready to be referenced from data.

Hero layers come from `python3 tools/art/paperdoll_layers.py` instead (after
`slice_sheets.py paperdoll_body`). A new **clothing cut** is a sheet of the body wearing the
piece in every pose, on the body sheet's grid, item in greys: `art/source/<place>_<style>_frames.png`
with a manifest `art/sheets/<place>_<style>_frames.json` (copy `top_tunic_frames.json`; place
is top, bottom or shoes). The tool lifts the piece off each pose into
`layers/<place>_<style>.png`, and any item with `worn_style = &"<style>"` wears it. A sheet that
came back unusable goes in `WORN_BROKEN` (currently smock), and its items use the nearest cut
(Berry Smock wears a tunic).

`paperdoll_layers.py` is a thin entry point for the `tools/art/paperdoll/` package, one module
per part. `common.py` holds the paths, sizes and name lists (`WORN_BROKEN`, `WEAPON_KINDS`,
`HAIRSTYLES`, `FACES`, ...) and the helpers that cut, place and write layers; `body.py` reads
the body strip and hand-placed rig; `hair.py`, `faces.py`, `hats.py`, `worn.py` (clothes, cape,
shields), `gloves.py` and `weapons.py` each make their layers; `build.py` runs them in turn and
writes the region mask, rig and `--preview`. A new kind of layer is a module with a
`<thing>_layers(hero, ...)` step called from `build.main`. Every name stays importable as
`paperdoll_layers.<name>` (the art tool tests and `grip_guide.py` use them).

## Making art with Gemini

Art comes from Google's Gemini image model through its batch API (half price). Follow the art
rules in `CLAUDE.md` (painted style, clean anti-aliased edges, icons matching worn gear).
Art for a zone, its town or a sub-zone keeps that zone's palette, light and materials from
[zone vibes](../zone-vibes.md).

1. Agree the look with Cory, then add the sheet to `tools/art/gemini_pass.json`, usually an
   `edit` entry: one existing sheet plus a short instruction that keeps its layout, on a pure
   #FF00FF background. Every entry sets `"stands"`: `true` for anything that stands on a map
   (buildings, props, signs, lamps, decorations). Those must be flat 2D front elevations with
   one flat bottom edge, never a 3/4 view cut flat; `true` adds `STANDS_RULES` to the request
   and a flat-bottom check to `sheet_check.py`. Look at every result for a top face or side
   depth before showing it to Cory, since the check can't see those.
2. `python3 tools/art/gemini_pass.py --dry-run` shows the cost (free); `--wait` makes what is
   missing. Run a small test first and show the results before the full batch and before
   anything goes in game. Every run is paid: ask Cory before redoing a sheet (`--redo ID`)
   unless it came back broken.
3. Results land in `art-sheets/gemini-pass-1/` in the project files, checked by
   `tools/art/sheet_check.py`. Check each one before it goes in `art/source/`.

It needs `GEMINI_API_KEY` in the environment and `generativelanguage.googleapis.com` allowed by
the network policy. `tools/art/gemini_sheet.py` (one direct, full-price request) is only for
quick one-off tests.
