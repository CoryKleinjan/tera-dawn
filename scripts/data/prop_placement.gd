class_name PropPlacement
extends Resource
## One hand-placed piece of scenery (an arch, a floating rock, a crystal).

@export var texture: Texture2D
@export var x := 0.0
## The prop's bottom edge. Leave at -1 to stand it on the floor.
@export var y := -1.0
## Depth: 0 is where the characters walk, negative is further back.
@export var depth := -3.0
@export var scale := 1.0
@export var flip := false
## A light in the prop (crystals, steam vents). Alpha 0 means none.
@export var light_color := Color(0, 0, 0, 0)
@export var light_energy := 1.5
## Where the light sits above the prop's base, in game pixels.
@export var light_height := 30.0
