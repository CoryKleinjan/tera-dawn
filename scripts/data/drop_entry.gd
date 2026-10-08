class_name DropEntry
extends Resource
## One line of a monster's loot table: this item, this often, this many.

@export var item: ItemDef
## Chance from 0 to 1 that this entry drops at all.
@export_range(0.0, 1.0) var chance := 1.0
@export var min_amount := 1
@export var max_amount := 1

## How many to drop this time, or 0 for none.
func roll() -> int:
	if item == null or randf() >= chance:
		return 0
	return randi_range(min_amount, max_amount)
