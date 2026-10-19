extends SmokeArea
## Quickslots in the game: putting an item on one, moving it, and using it with its key.

## A Return Scroll goes on a quickslot, moves to another, and its key reads it.
func check() -> void:
	var ch := _me().character
	var scroll: ItemDef = Content.item(&"return_scroll")
	ch.quickslots.fill([])
	ch.inventory.add(scroll, 2)
	_me().dirty_character = true
	await _ticks(2)
	# Quickslots are set from the client, and the server keeps them.
	world.hud.quickslots.assign(5, &"item", scroll.id)
	await _ticks(1)
	_check(ch.quickslots[5] == [&"item", scroll.id], "an item put on a quickslot stays there")
	world.hud.quickslots.assign(2, &"item", scroll.id)
	await _ticks(1)
	_check(ch.quickslots[2] == [&"item", scroll.id] and ch.quickslots[5] == [], "moving it to another quickslot")
	# Its key reads the scroll, back to the meadow's town.
	var town := Content.map(&"meadow").return_town()
	var scrolls := ch.inventory.count_of(scroll)
	_me().item_cd = 0
	await _tap("quick_3")
	await _until(func() -> bool: return world.map.id == town, 30)
	_check(world.map.id == town and ch.inventory.count_of(scroll) == scrolls - 1, "a Return Scroll's quickslot key reads it and takes you to town")
	Net.server.enter_map(_me(), &"meadow", 300)
	await _ticks(3)
