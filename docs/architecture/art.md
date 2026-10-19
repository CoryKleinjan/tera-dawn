# Art

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add art

Drop the sheet in `art/source/`, write a manifest in `art/sheets/`, and run
`python3 tools/art/slice_sheets.py <name>`. `art/sheets/README.md` explains the manifest. The
cut sprites land in `assets/sprites/`, ready to be referenced from data.

The hero (the boy, the one look) is painted whole, each move a sheet with the worn
armor and weapon painted on (see [characters](characters.md)).

## Making art with Gemini

Art comes from Google's Gemini image model through its batch API (half price). Follow the art
rules in [game rules](../game-rules.md) (painted style, clean anti-aliased edges) and the house rules in `CLAUDE.md` (ask about the look, small test first).
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
