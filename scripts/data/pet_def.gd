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
## How big it is in the world (its icon is used as its body).
@export var body_scale := 0.6

func tab() -> Tab:
	return Tab.SETUP

func stack_size() -> int:
	return 1
