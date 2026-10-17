class_name MuzzleSetDef
extends Resource
## Where each held piece's shots start: the point of its painting (in its own pixels, like
## HeldDef.anchor) an arrow, bullet, star or spell leaves from: the bow's arrow rest, the
## pistol's barrel, the star itself, the wand's tip. A piece not listed fires nothing of its
## own (a sword, a shield, a tome). On a frame where no piece with a muzzle shows (a bow, pistol
## or star not placed on its attack frame yet), the shot leaves from his hand there (`hands`).
## Kept apart from the held pieces (data/hero/held/) so their
## placements stay as they were placed. Set here by hand.

## Animation (a HeroLookDef.animations key) -> the frame its shot leaves on, for moves where
## that isn't the first (a throw winds up first, then lets go). Others use their first frame.
@export var frames: Dictionary = {}
## EquipDef id -> the muzzle, in that piece's held painting's pixels.
@export var points: Dictionary = {}
## Frame name -> where his shooting fist is on it, in his frame's pixels.
@export var hands: Dictionary = {}
