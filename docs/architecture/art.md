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
came back unusable goes in `WORN_BROKEN` (now: shorts, smock), and its items wear
the nearest cut (Berry Smock a tunic, Rolled Shorts breeches).

`paperdoll_layers.py` is a thin entry point: the code is the `tools/art/paperdoll/` package,
one module per part. `common.py` holds the paths, every size and name list (`WORN_BROKEN`,
`WEAPON_KINDS`, `HAIRSTYLES`, `FACES`, ...) and the helpers that cut, place and write layers;
`body.py` reads the body strip and the hand-placed rig; `hair.py`, `faces.py`, `hats.py`,
`worn.py` (clothes, cape, shields), `gloves.py` and `weapons.py` each make their layers; and
`build.py` runs them in turn, then writes the region mask, the rig and `--preview`. A new kind of
layer is a module with its helpers and a `<thing>_layers(hero, ...)` step, called from
`build.main`. Every name stays importable as `paperdoll_layers.<name>` (the art tool tests and
`grip_guide.py` use them).

Art is generated with Google's Gemini image model through its batch API (half price):
add the sheet to `tools/art/gemini_pass.json` (usually an `edit` entry: one existing sheet plus a
short instruction that keeps its layout, on a pure #FF00FF background) and run
`python3 tools/art/gemini_pass.py --dry-run` to see the cost, then `--wait` to make it. Results
land in the project's `art-sheets/gemini-pass-1/`. Every run is paid: ask Cory before redoing a
sheet, unless it came back broken. It needs `GEMINI_API_KEY` in the environment and
`generativelanguage.googleapis.com` allowed by the network policy. `tools/art/gemini_sheet.py`
(one direct, full-price request) is only for quick one-off tests. Check every result like any
upload before it goes in `art/source/`.
