# Art reference

`hero.png` is Cory's hero and the style reference for all of Tera Dawn's art:
every sprite, monster, prop and tile should match him.

What to match:

- Chibi proportions: a big head (about half his height) on a small body.
- Dark navy-black outlines (around `#14121e`) on every shape.
- Cel shading with three to four tones per colour, lit from the upper left.
- Big glossy eyes with a dark top lash, a deep-blue iris and white highlights.
- His palette: brown hair, red cape, blue tunic with gold trim, brown leather, silver steel.

The game's sprites are cut from the sheets in `art/source/` by `tools/art/slice_sheets.py`
(see `art/sheets/README.md`). New sheets should use the same layout: a grid of cells on a
flat magenta background with thin divider lines, one pose or object per cell.
