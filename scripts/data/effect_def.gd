class_name EffectDef
extends Resource
## A short visual effect: a flipbook of glowing frames, optionally with a flash of light,
## a burst of particles and a caption. Used for slashes, hits, level ups and pickups.

@export var id: StringName
@export var frames: Array[Texture2D] = []
@export var fps := 18.0
## How long it lasts in ticks; 0 means one pass through the frames.
@export var lifetime := 0
## Size of one frame texel in game pixels.
@export var texel := 1.0
## Where it appears relative to the spawn point, in game pixels (x is mirrored with facing).
@export var offset := Vector2.ZERO
## Brightness: values above 1 bloom.
@export var energy := 1.6
## Keeps following the player (level up).
@export var follow_player := false
@export var fade_out := true

@export_group("Light")
@export var light_color := Color(0, 0, 0, 0)
@export var light_energy := 3.0
@export var light_range := 4.0

@export_group("Particles")
## HDR colour of a one-shot particle burst. Alpha 0 means none.
@export var burst_color := Color(0, 0, 0, 0)
@export var burst_amount := 16

@export_group("Caption")
## Big text above the effect, drawn by the overlay (e.g. "LEVEL UP!").
@export var caption := ""
## Art drawn instead of the caption's text (the "LEVEL UP!" ribbon), this many pixels wide.
@export var caption_art: Texture2D
@export var caption_art_width := 200.0

func duration() -> int:
	if lifetime > 0:
		return lifetime
	return maxi(1, ceili(frames.size() / fps * 60.0))
