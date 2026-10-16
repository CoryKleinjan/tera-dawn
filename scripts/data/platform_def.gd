class_name PlatformDef
extends Resource
## A one-way platform: you can jump up through it and stand on its top edge.

## Share of a `look` picture's width you can stand on (its ends are rounded rock and grass).
const LOOK_SPAN := 0.72
## Art pixels of a `look` picture's grass that rise above the top edge.
const LOOK_GRASS := 7.0

@export var x := 0.0
## The top edge you stand on.
@export var y := 0.0
@export var width := 200.0
## A painted piece of land standing on the floor (a tall ledge) drawn as this platform
## instead of the biome's platform front. It is scaled to the platform's width. Land-shaped
## art always goes here rather than in a map's props, so everything that looks like
## ground can be stood on.
@export var look: Texture2D
## Raised land (a terrace or cliff top): its front runs all the way down to the land it
## stands on (`MapDef.land_under`) instead of hanging as a thin floating ledge. You still
## walk in front of it along the land below, the classic side-scroller way.
@export var solid := false
## Share of the `look` picture's width you can stand on (a flat deck's planks run almost
## edge to edge).
@export var look_span := LOOK_SPAN
## Art pixels of the `look` picture that rise above the top edge (grass, rails, ropes).
@export var look_top := LOOK_GRASS
## The `look` hangs between two platforms (a rope bridge) instead of standing on the floor:
## each end meets another platform at the same height.
@export var hangs := false
## A secret ledge: only a job's movement skill gets you up to it (Flash Jump, Blink, Charge,
## Rolling Dash, Backstep Leap), never a plain jump or a rope, and the minimap leaves it out.
@export var secret := false

## Game pixels per texel of `look`.
func look_texel() -> float:
	return width / (look.get_width() * look_span) if look else 0.0

## How far a `look` picture rises above the top edge, in game pixels.
func look_grass() -> float:
	return look_top * look_texel() * TDStage.art_density(look) if look else 0.0

