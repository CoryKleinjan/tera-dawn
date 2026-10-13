# Art reference

`hero.png` is the chibi boy hero, the first idle pose of the old painted hero sheet. He sets the proportions for the hero and every character:

- Chibi proportions: a big head (about half his height) on a small body.
- Big glossy eyes with a dark top lash, a deep-blue iris and white highlights.
- His palette: brown hair, red cape, blue tunic with gold trim, brown leather, silver steel.

`hero_look.png` is Cory's approved look for the new paperdoll hero (2026-10-13): the boy (top two
rows) and girl (bottom two) in their poses, wearing the blue tunic, dark trousers and every hat
type. It is the reference for how characters look in game: painted at full resolution, hair
under each hat as on the hat-hair templates, worn gear following the pose, the weapon hand
forward.

The painting style comes from the game's NPC sprites (see [game rules](../../docs/game-rules.md), "Art"): painted only,
never pixel art, with rich warm colours, strong light and shadow, visible brush texture and a dark
outline.

The game's sprites are cut from the sheets in `art/source/` by `tools/art/slice_sheets.py`
(see `art/sheets/README.md`). New sheets use the same layout: a grid of cells on a flat magenta
background with thin divider lines, one pose or object per cell.
