# Sheet manifests

Each file here tells `tools/art/slice_sheets.py` how to cut one sheet from `art/source/`:

```sh
python3 tools/art/slice_sheets.py              # every sheet
python3 tools/art/slice_sheets.py dewling ui   # only these
python3 tools/art/slice_sheets.py --grid ui    # print the cells it finds, write nothing
python3 tools/art/contact_sheet.py assets/sprites/monsters out.png 3   # preview a folder
```

A sheet is a grid of cells on a magenta (or dark) background, with thin divider lines and a
small white label in each cell's top-left corner. The slicer finds the cells, removes the
background and label, shrinks each cell to game scale and trims it. Its output (`assets/`) is
generated: fix art in the sheet or manifest, never in the output.

## Clean edges

Every sprite is cut at two texels per art pixel and keeps the smooth, anti-aliased edge of the
painting, and the game blends that edge in (`TDStage.style_sprite`). Cut at one texel per art
pixel with on/off alpha, the dark outline showed as a stair-stepped, pixelated line on a 1080p
screen. `detail` and `alpha` default to this for every asset;
`tools/art/tests/test_smooth_edges.py` checks the cut sprites.

## Adding a sheet

1. Save it as `art/source/<name>.png`.
2. Write `art/sheets/<name>.json` with at least `source`, `out_dir` and `cells`.
3. Run `--grid` first to check the slicer sees the same rows and columns as `cells`.
4. Cut it, look at the output with `contact_sheet.py`, and tune `scale` and overrides.

## Keys

| Key | Default | Meaning |
| --- | --- | --- |
| `source` | | The sheet, relative to the repo. |
| `out_dir` | | Where the sprites go (`<out_dir>/<cell name>.png`). |
| `cells` | | Cell names, one list per row, left to right. |
| `region` | | `[x0, y0, x1, y1]`: cut only this part of the sheet (for sheets holding several things, or cells spanning two grid rows). |
| `grid` | | Cells by hand when detection fails: `{"rows": [y0, y1, ...], "cols": [x0, x1, ...]}` (edges between cells; `cols` can be one list per row). Unnamed gap rows/columns are skipped. |
| `grid_threshold` | `0.8` | How much of a row or column must be divider-coloured to count as a divider. |
| `inset` | `3` | Pixels trimmed off every cell edge (the divider lines). |
| `background` | `"magenta"` | `"magenta"` (soft chroma key), `"dark"` (flood fill from the cell border) or `[r, g, b]`. |
| `key` | `[0.35, 0.8]` | Magenta sheets: how magenta a pixel must be to start and finish fading out. Raise it if purple art is eaten. |
| `dark_key` | `true` | Magenta sheets: dark magenta is background (floor shadows); `false` keeps plum line art. |
| `light` | `false` | Magenta sheets: the art is light with no outline (a glow, a beam of light). Each pixel is read as light laid over the magenta and the magenta is taken out exactly, so soft halos fade out with no pink fringe. Light seen over magenta reads bluer than it is, so `[r, g, b]` instead of `true` also gives the light that colour (keeping its whiteness). |
| `trim` | `true` | `false` keeps the whole cell (or `crop`) instead of trimming to the visible pixels, so animation frames cut as separate pictures line up. |
| `defringe` | `true` | Magenta sheets: take the magenta out of the dark outline pixels at the cut edge. `false` for a cell whose purple art it wrongly trims. |
| `shadow` | `false` | Dark sheets: also remove the soft drop shadow under the sprite. |
| `alpha` | `"smooth"` | `"smooth"` keeps each sprite's anti-aliased edge (and feathers the cut a `fix` makes); `"soft"` also keeps the faint glow round it (effects, UI); `"hard"` makes every pixel fully on or off (never for game art). |
| `min_area` | `6` | Specks smaller than this (art pixels) are dropped. |
| `scale` | `0.25` | Shrink from sheet pixels to art pixels, the unit the game sizes art in. Land art uses `art_px`. |
| `detail` | `2` | With `scale`: texels cut per art pixel, so the art keeps its detail and a clean edge on screen. The output folder must be in `TDStage.ART_DENSITY` at the same number. Set `1` where `scale` already cuts two texels per art pixel (rooms, backdrops, props) or the art is drawn at its cut size (UI). An animation set (`sets`) may use another number: its frames carry it as `art_density` metadata, so a monster shown big (`sprite_scale` above 1) is cut sharper at the same size. Monsters use about `2.56 x sprite_scale` (one texel per screen pixel at 1080p, like the NPCs), up to `1 / scale` (one texel per sheet pixel). |
| `art_px` | | Land art (tiles, platform pieces, ground, buildings): sheet pixels per art pixel. Sets `scale` to `density / art_px x grow`, so all land shows at one pixel size (`TDStage.TEXEL`, `TDStage.art_density`). |
| `density` | `2` | With `art_px`: texels per art pixel (the game reads 2 for the folders in `TDStage.ART_DENSITY`). |
| `grow` | `1.0` | With `art_px`: draw a piece 0.8 to 1.25 times its sheet size. `tools/art/land_pixels.py --check` keeps grow x every decor and prop scale within 0.75 to 1.3. |
| `label_band` | `0.16` | Top part of each cell (fraction of its height) where the label may be. |
| `strip_labels` | `false` | Paint over the white label letters in the label band first (small cells, labels close to the art). |
| `blank_top` | | Paint the top N rows of the cell with background. |
| `blank_label` | | Rows at the top holding a label drawn over the art: paints the box around its white letters. |
| `blank` | | Rects `[[x0, y0, x1, y1], ...]` in the cell to paint with background. |
| `keep` | `"all"` | `"largest"` keeps the biggest piece; `"split"` saves each piece as `name_1`, `name_2`... (left to right, or top to bottom with `"split_by": "y"`). |
| `drop_edge` | `false` | Drop pieces that touch the cell's edge: art from a neighbouring cell poking in. Use it instead of a `blank` rect that would cut into the art. |
| `flat_bottom` | `false` | The piece stands on the ground: `true` squares off a rounded bottom (up to 22% of its height), a number cuts that many rows. Every piece a map stands on its land needs one (`content_flat_bottom_test`). |
| `fix` | | A named clean-up from `FIXES` (below). |
| `recolor` | | A palette change from `RECOLORS` (below). |
| `save` | `true` | `false`: cells only feed animation sets (or are for later, cut into `art/build/`). |
| `climb` | | Rope and ladder pieces to line up, per climb style: `{"ladder": {"top": "ladder_top", "middle": "ladder_middle", "bottom": "ladder_bottom"}}` (`top`, `bottom` optional). See Climb pieces. |
| `overrides` | | Per-cell versions of any key above, plus: `crop` `[x0, y0, x1, y1]`; `flip` (mirror); `out_dir`; `seamless` (tileable texture, with `size`); `seamless_middle` (end-cap width in sprite px: the middle is cross-faded so it tiles between its caps); `extend_bottom` (pad a backdrop downward) with optional `ground` (a picture of the padded strip used in its place); `patch` (`[[x0, y0, x1, y1, dx], ...]`: copy a rect from dx pixels across, to remove an ornament that would stretch in a 9-slice); `patch_rows` (`[[y0, y1, dy], ...]`: replace rows with the rows dy away, to remove a divider drawn across the art). |

## Clean-ups and palette changes

`fix` names one of `FIXES` in `slice_sheets.py`:

- `glow_backdrop`, `glow_backdrop_holes`: the warm glow painted behind icons.
- `card_backdrop`: an item drawn on a framed pastel card or pale disc; `card_glow` also takes a
  pink glow round it; `card_flat` is a card fill for an item that runs out of its cell (with `crop`).
- `round_top`: rebuilds a round button's rim that ran under the label box.
- `medal_symbol`: keeps only the symbol on a cream medal, outlined (the quest markers).
- `painted_sky`, `sky_body` (the sun or moon).

`recolor` names one of `RECOLORS`: `dark_parchment` turns the leather UI sheets' pale parchment
into dark leather (the game writes light text on its panels), `leather` recolours older purple
UI to leather, `despill` whitens pale art the background tinted pink, and `sandstone` turns
cool grey-blue stone into the warm sandstone of Dawnharbor's floor (its walls and terrace ends).

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

- `anchor`: `"mass"` (centre of the opaque pixels), `"head"` (topmost pixels, steady when a
  weapon or cape swings) or `"cell"` (where the art sat in its cell).
- `baseline`: `"bottom"` puts every frame's lowest pixel on the floor; `"cell"` keeps the
  height it had in its cell, so hops stay in the air.
- `nudge`: `{"frame": [dx, dy]}` fine-tunes one frame. `pad_top`: empty rows above every frame
  (room for hair and hats). Both are in art pixels. Animations may give per-frame `durations`.

Actors look for `idle`, `move` (monsters), `attack`, `hurt` and `die`. The hero and all gear
have no art for now: their look is being restarted from `art/reference/hero.png`.

## Sheet families

- **Monsters**: one sheet per monster with a manifest named after its id (hand-measured
  `grid`, `strip_labels`, per-cell `blank` rects), writing `assets/sprites/monsters/<id>.png`
  and `assets/animations/<id>.tres`.
- **NPCs** (`npcs_<town>`): a fixed `grid`; each NPC's `scale` override sets its height next to
  the hero, and its set writes `assets/animations/npc_<id>.tres`.
- **Areas**: `<area>_tileset` cuts into `assets/sprites/tiles/<area>/` and `<area>_backgrounds`
  into `backgrounds/<area>/`. A sheet that came back on uneven magenta, with pink glows or a
  sky behind a strip, is evened out first by `tools/art/clean_sheet.py` (edits the source in
  place; `--plain` for a grey or graded background).
- **Platform pieces** (`platform_pieces_<area>`): left cap, two middles and right cap into
  `assets/sprites/platforms/<area>/` (undersides to `art/build/`). The slicer then runs
  `tools/art/platform_pieces.py`, which keeps the pieces at the rows they had in the sheet (so
  the caps meet the middles) and thins them to the manifest's `"platform"` options
  (`max_depth`, `top_share`, `"bottom": "under"`, and `shift` to nudge a cap painted as its own
  picture). The game
  joins them into one picture per platform (`PlatformSkin`), so `crop` off a clipped ornament on
  a piece's inner edge.
- **Buildings** (`building_<town>_<building>`): one building per sheet and manifest; `art_px` is
  the sheet's height over the building's art height (BuildingDef `height` / `TDStage.TEXEL`).
  Town kit buildings all use `art_px` 3.461 (Dawnharbor's tavern scale), so every door is the same
  size; `town_kit.py height <cut png>` gives the BuildingDef `height`.
- **Rooms** (`room_<town>`): furniture and floors, at 2 texels per art pixel. Crate, plant,
  `floor_soil` and missing floors come from `room_props_<town>` (one town per row of
  `room_props.png`). The back wall has its own manifest (`room_<town>_wall`; its `grid` width
  is the repeat, its first columns cross-faded so it tiles); stacked floor cells have
  `room_<town>_floor` with a `region`.
- **Backdrops and ropes/props** come from finer redraws (`*_fine.png`); each cell's `scale`
  makes it two texels per art pixel at its on-screen size. A town's backdrop is one 4K panorama
  (like Dawnharbor's), never strips.
- **Climb pieces** (`ropes_props_b`'s `"climb"` section, tops from `climb_tops_fine`): the
  slicer runs `tools/art/climb_pieces.py`, which centres each middle piece on its rope or rails
  and cuts and pads each end piece to carry on from it. The game stacks pieces edge to edge
  (`ClimbStyleDef.pieces`), so ends need no offsets; `top_rise` on the style sets how far the
  top rises above the ledge. Cutting any sheet of a style lines that style up again.
- **UI**: `ui`, `ui_windows`, `ui_hud`, `ui_menu`, `ui_dialogue`, `ui_social`, `ui_book` and
  `ui_creator` cut the leather sheets into `assets/sprites/ui/`; cells spanning two rows have
  their own `region` manifest (`ui_windows_frames`, `ui_menu_panel`, `ui_dialogue_rows`,
  `ui_book_rows`, `ui_creator_frame`). Pieces cut from older sheets use `<sheet>_old`
  manifests (`ui_old`, `ui_hud_old`, `ui_menu_old`, `ui_dialogue_old`, `items_parts_2_old`,
  `projectiles_old`, `skill_effects_old`).
- **Skill icons**: `skill_icons_<sheet>` cut the painted Gemini badges (2x2 sheets, one skill
  per cell, named by skill id) into `assets/sprites/skills/`; `skill_icons` keeps only `bow_shot`.
- **Items, pets, projectiles**: into `assets/sprites/items/` (named by item id), `pets/` (and
  `assets/animations/pet_*.tres`) and `projectiles/`.
- Cells the game doesn't load have `"save": false` in their overrides, so the slicer skips them;
  art the game never uses is removed rather than kept in the repo.

## Town kit

Every new town is painted with `tools/art/town_kit.py` (the rules are in `docs/game-rules.md`,
"Making a town"):

1. Copy `tools/art/towns/_template.json` to `tools/art/towns/<town>.json` and fill it from
   `docs/zone-vibes.md`. `signature` is the town's own materials; every other town's prompts ban
   them. The first building in `buildings` is the pilot. Cory agrees the card first.
2. `python3 tools/art/town_kit.py entries <town> --pilot --write` adds the pilot building and the
   backdrop to `gemini_pass.json`; dry-run, ask Cory, run, show him. Add the approved pilot to
   `approved_refs`, then `entries <town> --write` adds the rest (existing ids are never replaced;
   a repaint gets its own id).
3. Each entry carries a `town_check`; `gemini_pass.py` passes it to `sheet_check.py`, which
   reports the door on its mark, the base on the ground line, art cut off at the edge, stray
   bits, glow halos and a busy backdrop foreground. Fails go to Cory as keep, repaint or leave
   out; results are never retouched.
4. Cut each building with its own `building_<town>_<building>` manifest at `art_px` 3.461 and set
   its BuildingDef `height` from `town_kit.py height`.

The fixed canvases live in `tools/art/templates/town/` (`town_kit.py canvases` redraws them):
`building_wide`, `building_narrow`, `building_tall` (doorway marked at the bottom centre),
`lamp_post`, `props` (2x3), `panorama`, `townsfolk` (1x4) and `room_wall`.
