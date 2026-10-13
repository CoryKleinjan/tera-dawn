class_name ShopEntry
extends Resource
## One line of a shop: an item and what it costs.

@export var item: ItemDef
## Dawnshards for one. 0 means the usual price: PRICE_MARKUP times what a shop pays for it.
@export var price := 0

const PRICE_MARKUP := 4

func cost() -> int:
	return price if price > 0 else maxi(1, item.sell_price * PRICE_MARKUP)

## What one costs `ch`, after their Charisma's discount (CharacterStats.shop_discount).
func cost_for(ch: Character) -> int:
	return maxi(1, roundi(cost() * (1.0 - CharacterStats.shop_discount(ch.stats))))
