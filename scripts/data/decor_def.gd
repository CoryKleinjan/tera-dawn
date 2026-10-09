class_name DecorDef
extends Resource
## A rule for scattering scenery: pick one of `textures` every `spacing` pixels at a
## random depth and size. Biomes list these for their floors and platforms.

@export var textures: Array[Texture2D] = []
## Gap between pieces in game pixels, picked between x and y.
@export var spacing := Vector2(150, 300)
## Depth range: 0 is where characters walk, negative is further back.
@export var depth := Vector2(-4.0, -2.0)
@export var scale := Vector2(1.0, 1.0)
## Chance each slot gets a piece at all.
@export_range(0.0, 1.0) var chance := 1.0
## Size of one texel in game pixels before `scale`.
@export var texel := 1.25
## Shaded pieces are lit by the sun; unshaded ones keep their painted colours.
@export var shaded := true
