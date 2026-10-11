# Tera's Dawn: notes for Claude

A MapleStory-inspired 2D side-scroller in Godot 4.3 (Forward+), shipping on Steam with HD-2D
rendering (Octopath Traveler style depth, lighting and bloom). Its own look, not a close copy.
The game will grow much larger, so keep code extendable and readable.

## Where things are
- `ARCHITECTURE.md`: the big picture, an index of `docs/architecture/*.md` (one page per system
  and "how to add" guide), and the code conventions. Read the page for the system you touch.
- `data/`: all content as `.tres` (monsters, maps, items, skills, jobs, NPCs, quests, biomes).
  Code never names a specific monster, map or item.
- `scripts/`: data classes (`scripts/data/`), rules (`scripts/systems/`), server, actors, world, UI.
- `art/source/` sheets + `art/sheets/*.json` manifests -> `tools/art/slice_sheets.py` ->
  `assets/` (generated: fix art in the sheet or manifest, not the output). See `art/sheets/README.md`.
- Project memory lives outside the repo: `/mnt/project-files/MEMORY.md` (index) and
  `/mnt/project-files/memory/*.md`.

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

### Workflow
- Plan first: post a short plan (what changes, which files, choices) and wait for Cory's OK
  before changing code or assets.
- Branch fresh off `main` for every change; never stack branches or PRs on other feature branches.
- No screenshots in replies or PRs for fixes unless Cory asks.

### Art style
- Painted only, never pixel art. The game's NPCs are the style reference: rich warm colours,
  strong light and shadow with bright highlights, visible painted texture (cloth folds, wood
  grain, worn patches) at a fairly chunky brush scale, dark outline. The chibi boy hero sets
  hero proportions.
- Clean edges: cut sprites at about twice on-screen resolution with soft anti-aliased edges,
  never on/off edge pixels (the slicer's `detail` 2 and `"alpha": "smooth"` defaults; the game
  blends the edge in). Never make outlines thicker.
- An item's inventory/equipment icon shows the same object the character wears (same shape,
  colours, details); keep them matching.

### Making art
- Gemini batch API only: add an entry to `tools/art/gemini_pass.json` (usually an `edit` of an
  existing sheet that keeps its layout, pure #FF00FF background) and run `gemini_pass.py`.
- Ask Cory about the look first, run a small test, and show results before the full batch and
  before anything goes in game. Every run is paid: ask before redoing a sheet unless it came
  back broken.
- Only make or repaint art the game uses. Never use old ChatGPT sheets from git history.

### Game rules
- Characters, NPCs, ropes and ladders draw in front of land; no character shadows.
- NPCs stand still at idle. Map names only at the top of the screen. Towns have no monsters.
