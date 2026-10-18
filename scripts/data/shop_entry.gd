class_name ShopEntry
extends Resource
## One line of a shop: an item, what it costs and what unlocks it. Gear never drops: shops
## sell it, and better gear joins a shop's list as the story goes on or a secret is found.

@export var item: ItemDef
## Dawnshards for one. 0 means the usual price: PRICE_MARKUP times what a shop pays for it.
@export var price := 0

@export_group("Unlock")
## Hidden until the character has handed in this quest (a story step). Empty for none.
@export var after_quest: StringName
## Hidden until the character has beaten this boss. Null for none.
@export var after_boss: MonsterDef
## Hidden until the character has found this secret (Character.found_secret: a chest, wall or
## hidden way). Empty for none.
@export var after_secret: StringName

const PRICE_MARKUP := 4

func cost() -> int:
	return price if price > 0 else maxi(1, item.sell_price * PRICE_MARKUP)

## Whether `c` can see and buy it: everything that unlocks it done.
func open_to(c: Character) -> bool:
	if after_quest != &"" and not c.quests.done.has(after_quest):
		return false
	if after_boss and c.book.kills(after_boss) <= 0:
		return false
	return after_secret == &"" or c.found_secret(after_secret)
