class_name QuestObjective
extends Resource
## One thing a quest asks for: defeat some monsters, bring some items, or reach a map.

enum Kind { KILL, COLLECT, VISIT }

@export var kind := Kind.KILL
## KILL: which monster.
@export var monster: MonsterDef
## COLLECT: which item. It's taken from the bag when the quest is handed in.
@export var item: ItemDef
## VISIT: which map to reach.
@export var map: StringName
@export var count := 1
## COLLECT only: a monster that drops `item` only while this quest is in progress (quest
## items), and how often.
@export var drop_from: MonsterDef
@export_range(0.0, 1.0) var drop_chance := 0.5

## "Defeat 8 Dewlings", "Bring 10 Moss Tufts", "Reach Ember Hollow".
func describe() -> String:
	match kind:
		Kind.KILL:
			return "Defeat %d %s" % [count, monster.display_name if monster else "?"]
		Kind.COLLECT:
			return "Bring %d %s" % [count, item.display_name if item else "?"]
		_:
			var m: MapDef = Content.maps.get(map)
			return "Reach %s" % (m.display_name if m else String(map))
