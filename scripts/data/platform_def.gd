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

## Game pixels per texel of `look`.
func look_texel() -> float:
	return width / (look.get_width() * LOOK_SPAN) if look else 0.0

## How far a `look` picture's grass rises above the top edge, in game pixels.
func look_grass() -> float:
	return LOOK_GRASS * look_texel() * TDStage.art_density(look) if look else 0.0

