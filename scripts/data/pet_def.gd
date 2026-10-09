class_name PetDef
extends ItemDef
## A pet, like MapleStory's: double-click it in the Setup tab to bring it out. It follows
## you around and picks up items near you, and gets hungry: feed it pet food (a UseDef with
## `pet_food`) or it goes home.

## How far either side of you it picks things up, in game pixels.
@export var loot_reach := 160.0
## Ticks between pickups.
@export var loot_every := 20
## How fast it gets hungry: fullness lost every `hunger_ticks`.
@export var hunger_ticks := 1800
## What it says now and then.
@export var chatter: Array[String] = []
## Its animated body: SpriteFrames with idle, walk, jump and happy. Without it, its icon
## is its body and it hops along procedurally.
@export var sprite_frames: SpriteFrames
## How big the animated body is in the world (1.0: the frames are cut at the hero's pixel size).
@export var frames_scale := 1.0
## How big it is in the world when its icon is its body (no `sprite_frames`).
@export var body_scale := 0.6

func tab() -> Tab:
	return Tab.SETUP

func stack_size() -> int:
	return 1
