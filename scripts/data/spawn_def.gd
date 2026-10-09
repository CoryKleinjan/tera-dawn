class_name SpawnDef
extends Resource
## Puts `count` monsters of one kind on a platform. They respawn after being defeated.

@export var monster: MonsterDef
## Index of the platform (0 is the floor).
@export var platform := 0
@export var count := 1
