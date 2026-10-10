# Sheet manifests

Each file here tells `tools/art/slice_sheets.py` how to cut one sheet from `art/source/`:

```sh
python3 tools/art/slice_sheets.py              # every sheet
python3 tools/art/slice_sheets.py dewling ui   # only these
python3 tools/art/slice_sheets.py --grid ui    # print the cells it finds, write nothing
python3 tools/art/contact_sheet.py assets/sprites/monsters out.png 3   # preview a folder
```

The sheets are laid out as a grid of cells on a magenta (or dark) background, with thin
divider lines between cells and a small white label in each cell's top-left corner. The
slicer finds the cells, removes the background and label, shrinks each cell to game scale and
trims it.

## Adding a sheet

1. Save it as `art/source/<name>.png`.
2. Write `art/sheets/<name>.json` with at least `source`, `out_dir` and `cells`.
3. Run `--grid` first to check the slicer sees the same rows and columns as `cells`.
4. Run it, then look at the output with `contact_sheet.py` and tune `scale` and overrides.

## Keys

| Key | Default | Meaning |
| --- | --- | --- |
| `source` | | The sheet, relative to the repo. |
| `out_dir` | | Where the sprites go (`<out_dir>/<cell name>.png`). |
| `cells` | | Cell names, one list per row, left to right. |
| `region` | | `[x0, y0, x1, y1]`: cut only this part of the sheet, for sheets that hold several things (a group of monsters, a tileset beside its backdrops). Grid rows and columns are then inside the region. |
| `background` | `"magenta"` | `"magenta"` (soft chroma key), `"dark"` (flood fill from the cell border) or `[r, g, b]`. |
| `scale` | `0.25` | Shrink factor from sheet pixels to sprite texels. The hero is 0.25; match its pixel size. |
| `alpha` | `"hard"` | `"hard"` for pixel sprites, `"soft"` for glows, effects and backgrounds. |
| `key` | `[0.35, 0.8]` | Magenta sheets: how magenta a pixel must be to start and finish fading out. Raise it if purple art is being eaten. |
| `label_band` | `0.16` | Top part of each cell (fraction of its height) where the label may be. |
| `strip_labels` | `false` | Paint over the white label letters in the label band first, for small cells where the label sits close to the art. |
| `blank_top` | | Paint the top N rows of the cell with background, for labels that touch the art. |
| `blank_label` | | Rows at the top of the cell holding a label drawn over the art: paints the box around the label's white letters with background. |
| `blank` | | Rects `[[x0, y0, x1, y1], ...]` inside the cell to paint with background, for a label beside art that reaches the top. |
| `keep` | `"all"` | `"largest"` keeps only the biggest piece; `"split"` saves each piece as `name_1`, `name_2`... |
| `shadow` | `false` | Dark sheets: also remove the soft drop shadow under the sprite. |
| `inset` | `3` | Pixels trimmed off every cell edge (the divider lines). |
| `save` | `true` | `false` keeps cells only for animation sets. |
| `grid_threshold` | `0.8` | How much of a row or column must be divider-coloured to count as a divider. |
| `grid` | | Give the cells by hand when detection fails: `{"rows": [y0, y1, y2, ...], "cols": [x0, x1, ...]}` (edges between cells; `cols` can be one list per row). |
| `overrides` | | Per-cell versions of any key above, plus `crop` `[x0, y0, x1, y1]`, `seamless` (tileable texture, with `size`), `extend_bottom` (pad a backdrop downward), `fix` (a named clean-up from `FIXES`) and `out_dir`. |

## Animation sets

A `sets` block lines frames up on one strip with their feet on a shared baseline and writes a
Godot `SpriteFrames` resource. Frames can come from any manifest, as `"<sheet>:<cell>"`:

```json
"sets": {
  "dewling": {
    "frames": {"idle1": "dewling:idle1", "hop1": "dewling:hop1"},
    "anchor": "mass",
    "baseline": "cell",
    "out": "assets/sprites/monsters/dewling.png",
    "sprite_frames": "assets/animations/dewling.tres",
    "animations": {
      "idle": {"frames": ["idle1"], "fps": 3},
      "move": {"frames": ["hop1"], "fps": 6},
      "die":  {"frames": ["defeated"], "fps": 1, "loop": false}
    }
  }
}
```

- `anchor` lines frames up horizontally: `"mass"` (centre of the opaque pixels), `"head"` (the
  topmost pixels, steady for characters whose weapon or cape swings) or `"cell"` (where the art
  sat in its cell).
- `baseline`: `"bottom"` puts every frame's lowest pixel on the floor; `"cell"` keeps the
  height the art had in its cell, so hops and jumps stay in the air.
- `nudge`: `{"frame": [dx, dy]}` fine-tunes one frame.
- `pad_top`: empty rows added above every frame, so layers drawn over the frames (hair, hats) have room.

Actors look for the animations `idle`, `move` (monsters), `attack`, `hurt` and `die`; the hero
has its own list in `art/sheets/paperdoll_body.json`.

## Picks between versions

`meadow_backgrounds` and `ropes_props` each came in two versions once; the repainted sheets
replaced both, so only `meadow_backgrounds_a` and `ropes_props_b` are left.

## Item icons and window art

`items_gear` and `items_consumables` cut the item icons into `assets/sprites/items/`, named
after the item ids, replacing the placeholders from `tools/art/make_item_placeholders.py`
(which never overwrites a real icon). `elixir` and `mana_elixir` are art for future potions.
`ui_windows` cuts the window frame, tabs, slots, buttons and tooltip into
`assets/sprites/ui/`, which the game windows and the status bar's window buttons draw with.
`item_slot_hover` isn't used: its glow kept a pink tint from the magenta key, so the windows
brighten `item_slot` on hover instead.

## Monsters, NPCs, areas and the paperdoll (art prompts parts 1 to 3)

- **Monster group sheets** (`mon_<area>`, `monsters_m1`) hold several monsters each. Every
  monster has its own manifest named after its id, cutting its `region` of the group sheet
  with `strip_labels` and writing `assets/sprites/monsters/<id>.png` and
  `assets/animations/<id>.tres`. Labels drawn over big monsters are cleared with
  `blank_label`. `anim_mossling` and `anim_sproutcap` are the picked Mossling and Sproutcap;
  `sproutcap_extra` is unused.
- **NPC sheets** (`npcs_<town>`) use a fixed `grid`; each NPC's `scale` override sets its
  height next to the hero, and its set writes `assets/animations/npc_<id>.tres` (idle).
- **Area sheets**: each area has `<area>_tileset.png`, cut by `<area>_tileset` into
  `assets/sprites/tiles/<area>/` and by `<area>_buildings` into `buildings/<area>/`, and
  `<area>_backgrounds.png`, cut by `<area>_backgrounds` into `backgrounds/<area>/`. Sheets that
  came back on a darker magenta, with soft pink glows or with the sky painted behind a strip
  were evened out first by `tools/art/clean_sheet.py` (it edits the source in place, so run it
  on the original picture). The sun or moon uses `sky_body`; glowing icons use `glow_backdrop`.
- **Rooms** (`room_<town>`) cut over the stand-ins from `tools/art/make_room_placeholders.py`;
  a cell the sheet has no painting for (crate, plant, floor_soil, some floors) keeps its stand-in.
  The back wall repeats sideways: its crop's last columns were cross-faded in the source toward
  the columns just left of the crop. Floor cells stacked in one column have their own manifest
  (`room_<town>_floor`, with a `region`).
- **Not in the game yet**: `platform_pieces_<area>`, `climb_tops`, `dawnharbor_midground` and
  `buildings_<town>` cut into `art/build/` only.
- **Items, pets, projectiles** cut into `assets/sprites/items/`, `pets/` (and
  `assets/animations/pet_*.tres`) and `projectiles/`.
- **The paperdoll**: `paperdoll_body` cuts the bare hero into the hero strip (`pad_top` leaves
  room for hair). `paperdoll_hair`, `_faces`, `_layers` (cape, gloves, shields per frame) and
  `_weapons` cut into `art/build/` only; `tools/art/paperdoll_layers.py` places those pieces
  on every body frame and writes the layers, the region map and the rig. The weapon hand, the weapon's angle, the shield and the head's tilt
  in each frame are placed by hand in `paperdoll_rig.json` (in 128 px frames; the tool scales them to the strip), with how each
  weapon kind is held ("holds") and which frames hold it behind him (`weapon_behind`). Run it after re-cutting the body.
  `--preview` writes `art/build/paperdoll_preview.png`: every frame with each weapon kind in his hand.
- **Held weapons** (`held_*`, art prompts part 8 W2-W6): one weapon per cell, named by item id, pointing right with a green
  grip dot. `paperdoll_layers.py` puts each in his hand on every frame (`weapon_item_<id>`), in its own colours.
  `hero_main` (the painted hero) now cuts into `art/build/` for reference.
