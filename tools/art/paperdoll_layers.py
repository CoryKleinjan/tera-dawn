#!/usr/bin/env python3
"""Build the hero's layers from the part 2 paperdoll sheets.

The hero is drawn in layers: a bald, faceless body (assets/sprites/characters/hero.png, cut
by the paperdoll_body manifest), with hair, a face and worn gear on top. The hair, face and
shield sheets draw each piece once (or once per pose) in its own cell, not where it sits on
every frame, so this tool finds the head, neck and hands in each body frame and places the
pieces there; clothes, gloves and the cape come from sheets of the body wearing them in every
pose and are lifted off it onto his frame, writing one strip per layer that lines up frame for
frame with the body. The game plays a layer in step with the body (Paperdoll, PaperdollSprite).

    python3 tools/art/slice_sheets.py paperdoll_body   # the body strip first
    python3 tools/art/paperdoll_layers.py              # then the layers, mask and rig
    python3 tools/art/paperdoll_layers.py --preview    # also art/build/paperdoll_preview.png
    python3 tools/art/paperdoll_layers.py --pieces     # only weapons, shields and hats (quick: new gear)

Writes:
- assets/sprites/characters/hero_regions.png: the body strip's twin. Red channel = region
  id * 16 (Paperdoll.Region): skin, top (the chest a worn top covers), bottom (the shorts),
  shoes (the feet a worn pair covers). Alpha copies the body's.
- assets/sprites/characters/hero_rig.json: per frame, where the head, face, neck, hand and
  shield are (frame pixels), and whether the frame is seen from behind; plus each weapon's
  grip point.
- assets/sprites/characters/layers/*.png and assets/animations/paperdoll/*.tres: hair (front,
  back, under a hat) per hairstyle, face and eyes per face, cape (behind, and in front: its
  collar and clasp, or all of it in back views), round and kite shields, gloves.
- layers/weapon_<kind>.png (+ _behind): each weapon kind in his fist in every frame, greyscale,
  with a hole where his fingers wrap the grip so the hand shows over it; on his back while he
  climbs or sits. layers/weapon_item_<id>.png: the same for a weapon with its own held picture
  (art/sheets/held_*.json, cells named by item id), in full colour.

A hairstyle with a sheet drawn in every pose (art/sheets/hair_<style>_frames.json, the body
wearing the hair on the body sheet's grid) uses that instead of its one front piece: the
hair is lifted off each pose and set on the hero's head, so it moves with him. Resting, moving and
climbing each hold one drawing (HELD_HAIR) on every frame of theirs, so the hair keeps its shape. Under every
hairstyle the top and back of his bald head are repainted in hair greys, so no pose shows
scalp where the hair doesn't reach.

Gloves come from a sheet of the body wearing them in every pose (art/sheets/gloves_frames.json):
each pose's two gloves are lifted off and set on the hero's hands (the rig's grip and shield
points), at the size the drawn body is to his.

How each kind is held (a bow upright, a staff planted, a gun pointed) and which frames hold
the weapon behind his body are in art/sheets/paperdoll_rig.json ("holds", "weapon_behind").
Rig angles are the way the weapon points; sword, wand and staff art drawn at a slant on its
sheet is measured and straightened first (AXIAL), so the angles hold whatever the art.

Hair, cape, shields, gloves and weapons are greyscale; the game tints them (hair colour, the worn
item's colour). The irises are split off the faces into their own layer for the eye colour.

The code is the paperdoll package next to this script (tools/art/paperdoll/), one module per
part: common (paths, the sizes everything is measured in, cutting and placing pieces, writing
a layer), body (reading the body strip and the rig), hair, faces, hats, worn (clothes, cape and
shields), gloves, weapons, and build (the driver: every layer in turn, then the mask, the rig
and the preview). Everything is also importable from here, as `paperdoll_layers.<name>`; the
shared tables (HELD_HAIR_STYLE, BODY_PIECES) are the package's own, but BODY_SCALE, which
frame_names() sets, is only current as paperdoll.body.BODY_SCALE.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paperdoll.common import *  # noqa: E402,F401,F403
from paperdoll.body import *  # noqa: E402,F401,F403
from paperdoll.hair import *  # noqa: E402,F401,F403
from paperdoll.faces import *  # noqa: E402,F401,F403
from paperdoll.hats import *  # noqa: E402,F401,F403
from paperdoll.worn import *  # noqa: E402,F401,F403
from paperdoll.gloves import *  # noqa: E402,F401,F403
from paperdoll.weapons import *  # noqa: E402,F401,F403
from paperdoll.build import main, preview, rig_entries  # noqa: E402,F401

if __name__ == "__main__":
    main()
