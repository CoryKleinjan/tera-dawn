# Tera's Dawn: notes for Claude

A MapleStory-like 2D side-scroller in Godot 4.3 (Forward+), shipping on Steam with an HD-2D look.
The game will grow much larger, so keep code extendable and readable.

## Where things are
- `ARCHITECTURE.md`: the big picture, an index of `docs/architecture/*.md` (one page per system
  and "how to add" guide), and the code conventions. Read the page for the system you touch.
- `data/`: all content as `.tres` (monsters, maps, items, skills, jobs, NPCs, quests, biomes).
  Code never names a specific monster, map or item.
- `scripts/`: data classes (`scripts/data/`), rules (`scripts/systems/`), server, actors, world, UI.
- `art/source/` sheets + `art/sheets/*.json` manifests -> `tools/art/slice_sheets.py` ->
  `assets/` (generated: fix art in the sheet or manifest, not the output). See `art/sheets/README.md`.
- Project memory (shared across threads) lives outside the repo: `/mnt/project-files/MEMORY.md`
  (index) and `/mnt/project-files/memory/*.md`.

## Commands
```sh
tests/run_all.sh                 # every Godot test + smoke test, as CI runs it
tests/run_all.sh inventory       # only tests matching a name
python3 -m unittest discover -s tools/art/tests -t tools/art/tests   # art tool tests
python3 tools/art/slice_sheets.py [manifest]                         # cut sheets into assets/
python3 tools/art/paperdoll_layers.py                                # rebuild hero layers
python3 tools/art/gemini_pass.py --dry-run                           # Gemini batch cost check (free)
```

## House rules (Cory)
- Plan first: post a short plan (what changes, which files, choices) and wait for Cory's OK
  before changing code or art.
- Branch off `main` for every change; never stack branches or PRs on other feature branches.
- Art is painted only (like the NPCs and floating platforms), never pixel art. The chibi boy hero
  is the character reference. Only repaint art the game uses.
- Every asset is cut at double detail with smooth, clean edges (the slicer's `detail` 2 and
  `"alpha": "smooth"` defaults); never on/off alpha, which makes outlines look pixelated.
- Art is made with the Gemini batch API: add an entry (usually an `edit` of an existing sheet,
  pure #FF00FF background) to `tools/art/gemini_pass.json` and run `gemini_pass.py`. Every run is
  paid: ask Cory before redoing a sheet unless it came back broken. No ChatGPT sheets.
- Characters, NPCs, ropes and ladders draw in front of land; no character shadows; NPCs stand still
  at idle; map names only at the top of the screen; towns have no monsters.
- No screenshots in replies or PRs for fixes unless Cory asks.
