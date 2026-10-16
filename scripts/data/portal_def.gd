class_name PortalDef
extends Resource
## A portal standing on a platform. Pressing Up in it takes the player to another map.

@export var x := 0.0
## Index of the platform it stands on (0 is the floor).
@export var platform := 0
## The id of the MapDef it leads to.
@export var target_map: StringName
## Where the player arrives on that map, along `target_platform`.
@export var target_x := 100.0
## The platform the player arrives on (0 is the floor), so a portal high up a tall map can
## lead to one high up the next.
@export var target_platform := 0
## A building's door: the portal stands in its doorway with a warm light behind it (the
## building's own picture has the door; inside, the biome's `door` picture), entered the same way.
@export var door := false
## The portal only opens (and only shows) once this quest is handed in. Empty: always open.
@export var opens_after: QuestDef
## Leads somewhere with no portal back (a tutorial's way out).
@export var one_way := false
## The portal only opens (and only shows) while this quest is under way (a job test's way in).
@export var while_on: QuestDef
## The portal only opens (and only shows) once this boss has been beaten (a boss arena's
## way home, usually one_way to its town).
@export var after_boss: MonsterDef
## The far end of a shortcut: it only opens (and only shows) once the player has found the
## shortcut with this id (Character.secrets), by coming through its near end
## (`opens_shortcut`) or by breaking what blocks it (a BreakableDef with this id).
@export var shortcut: StringName
## The near end of a shortcut: always open, and going through it finds the shortcut with
## this id for good, so its far end (`shortcut`) opens too.
@export var opens_shortcut: StringName

## Whether it is one end of a shortcut (`shortcut` or `opens_shortcut`): a secret, so the
## world map leaves it out.
func is_shortcut() -> bool:
	return shortcut != &"" or opens_shortcut != &""

## Whether it opens and shuts with a quest, a boss or a shortcut, so it may be hidden.
func locked() -> bool:
	return opens_after != null or while_on != null or after_boss != null or shortcut != &""

## Whether `c` can use (and see) it.
func open_to(c: Character) -> bool:
	if while_on and not c.quests.active.has(while_on.id):
		return false
	if after_boss and c.book.kills(after_boss) <= 0:
		return false
	if shortcut != &"" and not c.found_secret(shortcut):
		return false
	return opens_after == null or c.quests.done.has(opens_after.id)
