# Tera's Dawn: notes for Claude

A MapleStory-inspired 2D side-scroller in Godot 4.7 (Forward+), shipping on Steam with a hand-painted look. Its own look, not a close copy.
The game will grow much larger, so keep code extendable and readable.

## Where things are
- `docs/game-rules.md`: every rule for how the game should look and play (hero, gear, weapons,
  maps, towns, monsters and levels, UI, audio). Follow it and keep it current.
- `ARCHITECTURE.md`: the big picture, an index of `docs/architecture/*.md` (one page per system
  and "how to add" guide), and the code conventions. Read the page for the system you touch.
- `docs/zone-vibes.md`: each zone's style and music guide (palette, light, materials,
  instruments) and how its town and sub-zones vary it. Read it before making art, music or a
  map look for a zone; keep it current.
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
python3 tools/art/gemini_pass.py --dry-run                           # Gemini batch cost check (free)
```

## House rules (Cory)

### Workflow
- Plan first: post a short plan (what changes, which files, choices) and wait for Cory's OK
  before changing code or assets.
- Branch fresh off `main` for every change; never stack branches or PRs on other feature branches.
- Merge a PR only after Cory says "merge" and CI is green; an "ok" or "looks good" isn't one.
- No screenshots in replies or PRs for fixes unless Cory asks.

### Art style
- Painted only, never pixel art. The game's NPCs are the style reference: rich warm colours,
  strong light and shadow with bright highlights, visible painted texture (cloth folds, wood
  grain, worn patches) at a fairly chunky brush scale, dark outline. The chibi boy hero sets
  hero proportions.
- Clean edges: cut sprites at about twice on-screen resolution with soft anti-aliased edges,
  never on/off edge pixels (the slicer's `detail` 2 and `"alpha": "smooth"` defaults; the game
  blends the edge in). Never make outlines thicker.
- Never recolour art in code (no tint, modulate or palette swap): another skin, hair or armour
  colour is its own painted sheet, put together as painted.
- An item's inventory/equipment icon shows the same object the character wears (same shape,
  colours, details); keep them matching.

### Making art
- Gemini batch API only: add an entry to `tools/art/gemini_pass.json` (usually an `edit` of an
  existing sheet that keeps its layout, pure #FF00FF background) and run `gemini_pass.py`.
- Anything that stands on a map (buildings, props, decorations) is a flat 2D front elevation
  with a flat bottom, never a 3/4 view cut flat: its entry sets `"stands": true`.
- Ask Cory about the look first, run a small test, and show results before the full batch and
  before anything goes in game. Every run is paid: never repaint anything without Cory's OK for
  that repaint, even a result that came back broken.
- Never fix body art (poses, arms, hands, fists) by pasting, mirroring or compositing pieces;
  offer a repaint instead. Cleaning up a cut (background, border lines) is fine.
- New towns use the town kit (`tools/art/town_kit.py`, rules in `docs/game-rules.md` "Making a
  town"): a town card, fixed canvases, locked prompts, checks that reject and never fix.
- Approved art is final: use it exactly as approved; never re-trim, recombine or remake it, and
  post a plan before any new render, composite or preview.
- Only make or repaint art the game uses. Never use old ChatGPT sheets from git history.

### Game rules
The full list is `docs/game-rules.md`. The ones most often broken:
- The hero's look and all equipment visuals are being restarted from Cory's original reference
  `art/reference/hero.png`: the game has no hero or gear art for now.
- No ammo for any weapon.
- Characters, NPCs, ropes and ladders draw in front of land; no character or land shadows.
- NPCs stand still at idle. Map names only at the top of the screen. Towns have no monsters.
- 2-3 monster kinds per map, each kind in one zone; paths between towns stay Lv 10 or below.
