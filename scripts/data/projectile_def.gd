class_name ProjectileDef
extends Resource
## What flies from a ranged skill to its target: an arrow, a star, a bolt of magic.
## Only for show: the server has already worked out the hit, and the damage number pops
## up when the projectile arrives.

@export var id: StringName
@export var texture: Texture2D
## Size of one texel in game pixels.
@export var texel := 1.0
## Game pixels per tick.
@export var speed := 16.0
## Turns per tick, for stars (0 flies straight, pointing where it goes).
@export var spin := 0.0
## Brightness: values above 1 bloom.
@export var energy := 1.2
## Light carried along. Alpha 0 means none.
@export var light_color := Color(0, 0, 0, 0)
## How far it flies when it hits nothing.
@export var max_range := 360.0
