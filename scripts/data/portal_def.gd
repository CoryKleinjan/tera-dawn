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
## A building's door: the portal stands in its doorway with a warm light behind it (the
## building's own picture has the door; inside, the biome's `door` picture), entered the same way.
@export var door := false
## The portal only opens (and only shows) once this quest is handed in. Empty: always open.
@export var opens_after: QuestDef
## Leads somewhere with no portal back (a tutorial's way out).
@export var one_way := false
## The portal only opens (and only shows) while this quest is under way (a job test's way in).
@export var while_on: QuestDef

## Whether it opens and shuts with a quest (opens_after, while_on), so it may be hidden.
func locked() -> bool:
	return opens_after != null or while_on != null

## Whether `c` can use (and see) it.
func open_to(c: Character) -> bool:
	if while_on and not c.quests.active.has(while_on.id):
		return false
	return opens_after == null or c.quests.done.has(opens_after.id)
