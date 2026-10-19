class_name UseDef
extends ItemDef
## A consumable: potions and the like. Used from the Use tab of the inventory. What each
## field does when used is in ServerItems.on_use_item.

## `teleport` value for "the town of the map you're on".
const TELEPORT_TOWN := &"town"

@export var heal_hp := 0
@export var heal_mp := 0
## Extra healing as a percentage of max HP / MP.
@export_range(0, 100) var heal_hp_percent := 0
@export_range(0, 100) var heal_mp_percent := 0
## Shown on the player when used.
@export var use_effect: EffectDef
## Takes you to another map: a map id, or TELEPORT_TOWN ("town") for the town of the map
## you're on (MapDef.return_town). Empty for none.
@export var teleport: StringName
## Fullness this gives the pet you have out (0 for anything that isn't pet food).
@export var pet_food := 0
## Ticks before another item can be used.
@export var cooldown := 30

func tab() -> Tab:
	return Tab.USE

## How much HP this restores for a character with `max_hp`.
func hp_for(max_hp: int) -> int:
	return heal_hp + roundi(max_hp * heal_hp_percent / 100.0)

func mp_for(max_mp: int) -> int:
	return heal_mp + roundi(max_mp * heal_mp_percent / 100.0)
