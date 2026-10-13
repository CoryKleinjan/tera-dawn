class_name SpawnDef
extends Resource
## Puts `count` monsters of one kind on a platform. They respawn after being defeated.

@export var monster: MonsterDef
## Index of the platform (0 is the floor).
@export var platform := 0
@export var count := 1
## Where on the platform they walk, as game-pixel x from `patrol_from` to `patrol_to`.
## A negative value means that edge of the platform. Use it to keep monsters out of a
## stretch of floor, such as a town's NPCs.
@export var patrol_from := -1.0
@export var patrol_to := -1.0
## Waits out of sight until the map's tear opens (MapDef.tear_platform), steps out of it,
## and doesn't come back once defeated.
@export var from_tear := false

## The part of `p` these monsters walk on (all of it unless a patrol range is set).
func patrol_area(p: Platform) -> Platform:
	var from := p.x if patrol_from < 0.0 else clampf(patrol_from, p.x, p.x + p.w)
	var to := p.x + p.w if patrol_to < 0.0 else clampf(patrol_to, from, p.x + p.w)
	return Platform.new(from, p.y, to - from, p.solid)
