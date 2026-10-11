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

## The painted look (2026-10-11)

The game's art is soft painted art, like the NPCs and floating platforms; no pixel art. The
buildings, rooms, backdrops, area tilesets, ropes/props, climb tops and ground textures were
pixel art until then and were repainted as Gemini edits of the same sheets (`paint_*` entries in
`tools/art/gemini_pass.json`), so every cell, `art_px` and manifest stayed as it was. `art_px`
now only sets the cut size. Gemini tinted some backgrounds (grey, pink) and redrew the cell
dividers a few pixels off; those sheets were set back to flat magenta and their original
dividers before cutting, and the slicer drops thin stray divider bits. The room walls were
cross-faded again so they repeat sideways (their `grid` width is the repeat).

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
| `scale` | `0.25` | Shrink factor from sheet pixels to sprite texels. The hero is 0.25; match its pixel size. Land art uses `art_px` instead. |
| `art_px` | | Land art (tiles, platform pieces, ground textures): sheet pixels per art pixel, measured on the sheet. Sets `scale` to `density / art_px x grow`, so every piece of land shows at one on-screen pixel size (`TDStage.TEXEL` game px per art pixel; `TDStage.art_density`). |
| `density` | `2` | With `art_px`: texels cut per art pixel. The game reads 2 for everything under `tiles/`, `platforms/` and `ground/`. |
| `grow` | `1.0` | With `art_px`: how much bigger or smaller a piece is drawn than its sheet's pixel size, 0.8 to 1.25 (a piece Gemini drew too small or too big next to its neighbours). `tools/art/land_pixels.py --check` checks grow x every decor and prop scale stays within 0.75 to 1.3. |
| `alpha` | `"hard"` | `"hard"` for solid sprites, `"soft"` for glows, effects and backgrounds. |
| `key` | `[0.35, 0.8]` | Magenta sheets: how magenta a pixel must be to start and finish fading out. Raise it if purple art is being eaten. |
| `defringe` | `true` | Magenta sheets: after the key, take the magenta out of the dark outline pixels at the cut edge (Gemini blends its outline into the background, which would show as a thin magenta line). Set `false` for a cell whose purple art it wrongly trims. |
| `label_band` | `0.16` | Top part of each cell (fraction of its height) where the label may be. |
| `strip_labels` | `false` | Paint over the white label letters in the label band first, for small cells where the label sits close to the art. |
| `blank_top` | | Paint the top N rows of the cell with background, for labels that touch the art. |
| `blank_label` | | Rows at the top of the cell holding a label drawn over the art: paints the box around the label's white letters with background. |
| `blank` | | Rects `[[x0, y0, x1, y1], ...]` inside the cell to paint with background, for a label beside art that reaches the top. |
| `keep` | `"all"` | `"largest"` keeps only the biggest piece; `"split"` saves each piece as `name_1`, `name_2`... (left to right, or top to bottom with `"split_by": "y"`) |
| `shadow` | `false` | Dark sheets: also remove the soft drop shadow under the sprite. |
| `inset` | `3` | Pixels trimmed off every cell edge (the divider lines). |
| `save` | `true` | `false` keeps cells only for animation sets. |
| `grid_threshold` | `0.8` | How much of a row or column must be divider-coloured to count as a divider. |
| `climb` | | Rope and ladder pieces to line up after cutting, one entry per climb style: `{"ladder": {"top": "ladder_top", "middle": "ladder_middle", "bottom": "ladder_bottom"}}` (`top` and `bottom` optional). See **Climb pieces** below. |
| `grid` | | Give the cells by hand when detection fails: `{"rows": [y0, y1, y2, ...], "cols": [x0, x1, ...]}` (edges between cells; `cols` can be one list per row). |
| `flat_bottom` | false | The piece stands on the ground: `true` squares off a rounded or tapering bottom (cuts the rows where the outline still curves in, up to 22% of its height), a number cuts exactly that many rows. Every piece a map stands on its land needs a flat bottom (content_flat_bottom_test). |
| `overrides` | | Per-cell versions of any key above, plus `crop` `[x0, y0, x1, y1]`, `seamless` (tileable texture, with `size`), `seamless_middle` (end-cap width in sprite px: a bar whose middle is tiled between its caps, its middle cross-faded so it repeats without a seam), `extend_bottom` (pad a backdrop downward), `ground` (with `extend_bottom`: a picture of the padded strip with painted ground in the pad, used in its place so the backdrop meets the floor), `fix` (a named clean-up from `FIXES`), `recolor` (a palette change from `RECOLORS`), `patch` (`[[x0, y0, x1, y1, dx], ...]`: paint a rect with a copy from dx pixels across, to take out an ornament that would stretch in a 9-slice), `flip` (mirror it left to right), `patch_rows` (`[[y0, y1, dy], ...]`: replace rows y0 to y1 with the rows dy away, to take out a divider line drawn across the art) and `out_dir`. |

## Clean-ups and palette changes

`fix` names one of `FIXES` in `tools/art/slice_sheets.py`: `glow_backdrop` (and `_holes`) for the warm glow
painted behind icons, `card_backdrop` for an item drawn on a framed pastel card or pale disc, `card_glow` (the same,
also taking a pink glow round the item), `card_flat` (a card fill for an item that runs out of its cell, with
`crop`), `round_top` (rebuilds the part of a round button's rim that ran under the label box, from the uncovered rim on
either side of it),
`painted_sky`, `sky_body` and `hero_attack_arc`. `recolor` names one of `RECOLORS`: `dark_parchment` turns the big
pale parchment areas of the leather UI sheets (part 7) into dark leather, since the game writes light text in its
panels; `leather` was the stand-in that recoloured the old purple UI.

## The leather UI (art prompts part 7)

`ui`, `ui_windows`, `ui_hud`, `ui_menu`, `ui_dialogue`, `ui_social`, `ui_book` and `ui_creator` cut the leather
sheets. Cells that span two grid rows have their own manifest with a `region` (`ui_windows_frames`, `ui_menu_panel`,
`ui_dialogue_rows`, `ui_book_rows`, `ui_creator_frame`). Pieces the leather sheets don't have, or that didn't suit,
are still cut from the old sheet by a `<sheet>_old` manifest (`art/source/<sheet>_old.png`): the minimap dots and
portal, the keycaps (light keys for dark letters), the three banners with their words painted in, and the attack and
Dawnshard icons. Other sheets do the same: `items_parts_2_old` (ash veil, stalker fang), `skill_icons_old` (the thief
skills), `projectiles_old` (mob wisp) and `skill_effects_old` (portal flash). `ui_map_icons`, `ui_controls_leather` and `ui_extras_leather` are for later (`save` false).

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
`item_slot_hover` isn't used: the windows brighten `item_slot` on hover instead.

## Monsters, NPCs, areas and the paperdoll (art prompts parts 1 to 3)

- **Monster sheets** (`mon_<id>.png`, `anim_<id>.png`, Gemini pass 1) hold one monster each.
  Every monster has its own manifest named after its id, with a hand-measured `grid` (gap rows
  and columns between cells are unnamed) and `strip_labels`, writing
  `assets/sprites/monsters/<id>.png` and `assets/animations/<id>.tres`. Labels and divider
  lines that touch the art are painted out with per-cell `blank` rects; `scale` keeps each
  monster's idle height what it was before the swap. `anim_mossling` is still the older
  sheet; `sproutcap_extra` is cut into `art/build/` only (unused).
- **NPC sheets** (`npcs_<town>`) use a fixed `grid`; each NPC's `scale` override sets its
  height next to the hero, and its set writes `assets/animations/npc_<id>.tres` (idle).
- **Area sheets**: each area has `<area>_tileset.png`, cut by `<area>_tileset` into
  `assets/sprites/tiles/<area>/` and by `<area>_buildings` into `buildings/<area>/`, and
  `<area>_backgrounds.png`, cut by `<area>_backgrounds` into `backgrounds/<area>/`. Sheets that
  came back on a darker magenta, with soft pink glows or with the sky painted behind a strip
  were evened out first by `tools/art/clean_sheet.py` (it edits the source in place, so run it
  on the original picture). The sun or moon uses `sky_body`; glowing icons use `glow_backdrop`.
- **Rooms** (`room_<town>`, from `room_<town>_fine.png`) cut the furniture and most floors.
  The crate, plant, `floor_soil` and the floors those sheets lack come from one shared sheet,
  `room_props.png` (one town per row, cut by `room_props_<town>`). Like the land, rooms
  are cut at 2 texels per art pixel (`rooms/` is in TDStage.ART_DENSITY). The back wall has its
  own finer redraw and manifest (`room_<town>_wall`); it repeats sideways because the source's
  first columns were cross-faded from the columns past its right edge. Floor cells stacked in
  one column have their own manifest (`room_<town>_floor`, with a `region`).
- **Platform pieces** (`platform_pieces_<area>`) cut a left cap, two middles and a right cap
  into `assets/sprites/platforms/<area>/` (the undersides go to `art/build/`). After cutting,
  the slicer runs `tools/art/platform_pieces.py`, which lines up their walking surfaces and
  thins them to the manifest's `"platform"` options (`max_depth`, `top_share`, and `"bottom":
  "under"` to take the underside from the under pieces). The game joins them into one picture
  per platform (`PlatformSkin`). Cut a clipped ornament off a piece's inner edge with `crop`
  rather than leave it: the game cuts through it where pieces join.
- **Buildings** (`building_<area>_<large|small>`) are one building per sheet, Gemini edits of
  the old tileset cuts at four times the detail. Each manifest's `art_px` is the sheet's
  height over the building's art height (its BuildingDef `height` / TDStage.TEXEL), so it shows
  at the shared pixel size and its set height. The old `<area>_buildings` tileset cuts are gone.
- **Backdrops and ropes/props** are cut from the finer Gemini redraws (`*_fine.png`); each
  cell's `scale` makes it two texels per art pixel at the size it shows on screen.
- **Climb pieces** (`ropes_props_b`, its `"climb"` section): after cutting, the slicer runs
  `tools/art/climb_pieces.py`, which centres each middle piece on its rope or rails (leaning a
  vine back so its ends meet), and cuts and pads each end piece so it carries on from a middle
  piece (same centre line, a ladder's rungs keep their spacing). The game stacks the pieces
  edge to edge (`ClimbStyleDef.pieces`), so an end piece needs no hand offsets. The rope, vine
  and rope ladder tops come from `climb_tops_fine` (a Gemini edit with the land taken out; each
  cell's `scale` matches its rope's width to the middle piece's, its `crop` keeps the anchor and a
  short tail). A climb style's pieces may come from several sheets: cutting any of them lines up
  that style again. `top_rise` on the style sets how far its top piece rises above the ledge.
- **Not in the game yet**: `climb_tops`, `dawnharbor_midground` and `buildings_<town>` cut into
  `art/build/` only.
- **Items, pets, projectiles** cut into `assets/sprites/items/`, `pets/` (and
  `assets/animations/pet_*.tres`) and `projectiles/`.
- **The paperdoll**: `paperdoll_body` cuts the bare hero into the hero strip (`pad_top` leaves
  room for hair). `paperdoll_hair`, `_faces`, `_shield_round`, `_shield_kite` (one piece per pose; the kite
  sheet has its own layout, so its `poses` names the cell each pose uses) and
  `_weapons` cut into `art/build/` only; `tools/art/paperdoll_layers.py` places those pieces
  on every body frame and writes the layers, the region map and the rig. The weapon hand, the weapon's angle, the shield and the head's tilt
  in each frame are placed by hand in `paperdoll_rig.json` (in 128 px frames; the tool scales them to the strip), with how each
  weapon kind is held ("holds") and which frames hold it behind him (`weapon_behind`). Run it after re-cutting the body.
  `--preview` writes `art/build/paperdoll_preview.png`: every frame with each weapon kind in his hand.
  His hands are fingerless rounded mittens (MapleStory style, Cory 2026-10-11), so a weapon only needs
  to sit under the fist. To redraw part of the body, `tools/art/body_panels.py` cuts close-up panels of
  a few cells for a Gemini edit (it redraws small details only when they are big in the picture) and
  pastes back only what changed (`hands`), or everything above his shorts (`upper`); `worn-base` and
  `worn-cells` redress changed cells on the worn sheets. While running, his weapon arm swings back in
  run1-2 (the weapon trails behind him) and forward in run3-4.
- **Held weapons** (`held_*`, art prompts part 8 W2-W6): one weapon per cell, named by item id, pointing right with a green
  grip dot. `paperdoll_layers.py` puts each in his hand on every frame (`weapon_item_<id>`), in its own colours.
  `hero_main` (the painted hero) now cuts into `art/build/` for reference.
- **Drawn on the body sheet** (`hair_<style>_frames`, `gloves_frames`, `cape_frames`,
  `paperdoll_shield_round`, `paperdoll_grip`, `top_*_frames`, `bottom_*_frames`, `shoes_*_frames`):
  made by editing `art/source/paperdoll_body.png`, so they keep its size and `grid` and line up with
  it pixel for pixel. The round shield sheet holds the item alone; the others show the body
  wearing it in greys, and `paperdoll_layers.py` lifts the greys off the body into a gear layer the
  game tints (a cut that came back unusable is listed in `WORN_BROKEN`, in `tools/art/paperdoll/common.py`, and its items wear the nearest
  cut). The cape is split where it crosses the hero: the part over him is `cape_front`.
  Sheets with a grey or gradient background are cleaned with `clean_sheet.py --plain` first.
- **Hats**: `paperdoll_hats` shows each hat shape on a head (side and behind views) beside a bare
  head (`bald_side`), and `paperdoll_hats_only` is the same sheet with the heads erased. The tool
  lines each hat up by the head's shoulders and places it on every frame's head (`hat_<shape>`).
  `paperdoll_grip` has no code yet (cut into `art/build/` only), nor do `paperdoll_body_2`,
  `hair_tousled_frames_2` and `paperdoll_gloves_2` (new poses drawn on Gemini's own body, for later).
