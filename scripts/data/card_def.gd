class_name CardDef
extends ItemDef
## A Monster Book card. Content makes one for every monster (id "card_<monster id>"), so
## they need no files. Picking one up puts it in your Monster Book instead of the bag.

## Cards of one monster that complete its page.
const SET := 5
## How often a monster drops its card.
const CHANCE := 0.05

var monster: MonsterDef

static func for_monster(m: MonsterDef, art: Texture2D) -> CardDef:
	var c := CardDef.new()
	c.id = StringName("card_%s" % m.id)
	c.monster = m
	c.display_name = "%s Card" % m.display_name
	c.description = "A Monster Book card. Collect %d to complete its page." % SET
	c.icon = art
	c.sprite_scale = 0.4
	c.glow_color = Color(0.7, 0.85, 1.0)
	c.max_stack = 1
	c.sell_price = 0
	return c
