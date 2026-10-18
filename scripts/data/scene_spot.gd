class_name SceneSpot
extends Resource
## A spot on a map that does something for a player who stands on it: plays a cutscene
## (each character sees it once), and can then send them to another map, where a second
## cutscene plays. A spot can be open only while a quest is in progress, and can show a
## white glow (a tear) while it's open. The home-world tear is made of these: the light over
## Starfall Ridge that pulls the hero through, the hero's thoughts in the home world, and
## the way back. Add one to a map's `scene_spots`.

## The platform to stand on (0 is the floor), and the stretch of it across the map (all of
## it when `to_x` is 0).
@export var platform := 0
@export var from_x := 0.0
@export var to_x := 0.0
## Open only while one of these quests is in progress (empty: always open).
@export var while_on: Array[QuestDef] = []
## ...and only while it still has something left to do (closed once it's ready to hand in).
@export var until_ready := false
## What plays when a player first stands here.
@export var scene: CutsceneDef
## Where it sends them once `scene` ends (empty: nowhere), and what plays when they arrive.
## A spot that sends you on keeps doing so, without its scene, after the first time.
@export var then_map: StringName
@export var then_x := 0.0
@export var then_scene: CutsceneDef
## A tear drawn here while the spot is open, for the players it's open to: x across the map
## and height above the floor (zero: none). See TDStage.show_spot_glows.
@export var glow := Vector2.ZERO
## The way into this tear: sealed (shut, no glow) until it's open to them (TearState.open).
@export var tear: TearDef

## Whether it's there for `c` at this point of their quests.
func open_to(c: Character) -> bool:
	if tear and not TearState.open(tear, c):
		return false
	if while_on.is_empty():
		return true
	for q in while_on:
		if q and c.quests.active.has(q.id) and not (until_ready and c.quests.is_ready(q, c)):
			return true
	return false

## Whether `x` is on its stretch of the platform.
func covers(x: float) -> bool:
	return to_x <= 0.0 or (x >= from_x and x <= to_x)
