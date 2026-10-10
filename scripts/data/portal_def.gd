class_name PortalDef
extends Resource
## A portal standing on a platform. Pressing Up in it takes the player to another map.

@export var x := 0.0
## Index of the platform it stands on (0 is the floor).
@export var platform := 0
## The id of the MapDef it leads to.
@export var target_map: StringName
## Where the player arrives on that map's floor.
@export var target_x := 100.0
## A building's door rather than a swirl: drawn as a warm doorway (the building's own
## picture has the door; inside, the biome's `door` picture), entered the same way.
@export var door := false
