class_name UseDef
extends ItemDef
## A consumable: return scrolls, pet food and the like (no potions, Cory Oct 19). Used from the Use tab of the inventory. What each
## field does when used is in ServerItems.on_use_item.

## `teleport` value for "the town of the map you're on".
const TELEPORT_TOWN := &"town"

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
