class_name QuestObjective
extends Resource
## One thing a quest asks for: defeat some monsters, bring some items, reach a map, or climb
## up onto a spot on one.

enum Kind { KILL, COLLECT, VISIT, REACH }

@export var kind := Kind.KILL
## KILL: which monster.
@export var monster: MonsterDef
## COLLECT: which item. It's taken from the bag when the quest is handed in.
@export var item: ItemDef
## VISIT: which map to reach. REACH: the map the spot is on.
@export var map: StringName
## REACH: the platform to stand on (its index on `map`; 0 is the floor), and what to call it.
@export var platform := 0
@export var spot_name := ""
@export var count := 1
## COLLECT only: the item stays in the bag when the quest is handed in (a gift to keep).
@export var keep := false
## COLLECT only: a monster that drops `item` only while this quest is in progress (quest
## items), and how often.
@export var drop_from: MonsterDef
@export_range(0.0, 1.0) var drop_chance := 0.5

## "Defeat 8 Dewlings", "Bring 10 Moss Tufts", "Reach Fern Hollow", "Reach the big rock".
func describe() -> String:
	match kind:
		Kind.KILL:
			return "Defeat %d %s" % [count, monster.display_name if monster else "?"]
		Kind.COLLECT:
			if keep:
				return "Pick up %s" % (item.display_name if item else "?")
			return "Bring %d %s" % [count, item.display_name if item else "?"]
		Kind.REACH:
			return "Reach %s" % spot_name
		_:
			var m: MapDef = Content.maps.get(map)
			return "Reach %s" % (m.display_name if m else String(map))

## Whether this can be worked on at `m`: its monster (or one dropping its item) lives there,
## or it's the map to reach.
func can_do_on(m: MapDef) -> bool:
	match kind:
		Kind.KILL:
			return m.spawns.any(func(s: SpawnDef) -> bool: return s.monster == monster)
		Kind.COLLECT:
			return m.spawns.any(func(s: SpawnDef) -> bool: return s.monster and (s.monster == drop_from
					or s.monster.drops.any(func(d: DropEntry) -> bool: return d.item == item)))
		_:
			return m.id == map
