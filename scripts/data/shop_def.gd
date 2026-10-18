class_name ShopDef
extends Resource
## What a shopkeeper sells. Give an NpcDef a shop and talking to them offers "Open shop".
## Every shop also buys anything the player carries for the item's `sell_price`.

@export var id: StringName
@export var display_name := ""
@export var items: Array[ShopEntry] = []

## The places in `items` of the lines `c` has unlocked (ShopEntry.open_to), in order.
func open_to(c: Character) -> Array[int]:
	var out: Array[int] = []
	for i in items.size():
		if items[i].open_to(c):
			out.append(i)
	return out
