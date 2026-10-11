extends SmokeArea
## Keepsakes: chairs, pets, the Monster Book and achievements.

## Chairs, pets, the Monster Book and achievements.
func check() -> void:
	var me := _me()
	var ch := me.character
	var map := me.map
	me.inv = 100000
	_teleport(Vector2(300, 620))
	await _ticks(3)
	# chairs: sit, heal faster, get up by moving
	var stool: ChairDef = Content.item(&"wooden_stool")
	ch.inventory.add(stool)
	me.dirty_character = true
	await _ticks(2)
	var inv: TDInventoryWindow = world.hud.windows["inventory"]
	inv.tab = ItemDef.Tab.SETUP
	inv.use_slot(Game.me.inventory.find(stool))
	await _ticks(3)
	_check(me.chair == &"wooden_stool" and world.player.sitting == &"wooden_stool" and world.player._animation() == &"sit", "double-clicking a chair sits you on it")
	_check(ch.achievements.has("take_a_seat") and world.hud.banners.toasts.any(func(t: Dictionary) -> bool: return t["title"] == "Take a Seat"), "sitting down earns an achievement")
	ch.health.set_hp(10)
	var hp := ch.health.hp
	map.tick = (map.tick / 120 + 1) * 120 - 1
	await _ticks(1)
	_check(ch.health.hp - hp == 2 + ch.level / 3 + ch.skills.regen_bonus().x + stool.regen_hp, "a chair adds to HP recovery")
	await _hold("move_right", 6)
	await _ticks(4)
	_check(me.chair == &"" and world.player.sitting == &"", "moving gets you up")
	# pets: bring one out, it picks things up nearby, it eats, it gets hungry
	var pup: PetDef = Content.item(&"pet_puffpaw")
	ch.inventory.add(pup)
	ch.inventory.add(Content.item(&"pet_snack"), 2)
	me.dirty_character = true
	await _ticks(2)
	Net.ask(&"req_setup", [Game.me.inventory.find(pup)])
	await _ticks(3)
	_check(ch.pet == &"pet_puffpaw" and Game.me.pet == &"pet_puffpaw" and world.player.companion.pet == pup, "double-clicking a pet brings it out")
	var wing := Content.item(&"petal_wing")
	var wings := ch.inventory.count_of(wing)
	# nothing else on the ground for the pet to fetch first
	_clear_drops(map)
	await _until(func() -> bool: return absf(me.position.x - world.player.position.x) < 1.0, 30)
	var x := me.position.x + 110.0
	map.spawn_drop(wing, 1, null, DropFlight.create(Vector2(x, 600), 620.0, x), me.peer)
	await _until(func() -> bool: return ch.inventory.count_of(wing) == wings + 1, SimDrop.SETTLE_TICKS + pup.loot_every * 2 + 4)
	_check(ch.inventory.count_of(wing) == wings + 1, "a pet picks up items out of your reach")
	ch.pet_full = 40
	Net.ask(&"req_use_item", [Game.me.inventory.find(Content.item(&"pet_snack"))])
	await _ticks(2)
	_check(ch.pet_full == 70, "pet food fills your pet up")
	ch.pet_full = 5
	map.tick = (map.tick / pup.hunger_ticks + 1) * pup.hunger_ticks - 1
	await _ticks(3)
	_check(ch.pet == &"" and Game.me.pet == &"", "a hungry pet goes home")
	# the Monster Book: kills and cards
	var dew: MonsterDef = Content.monster(&"dewling")
	_check(ch.book.kills(dew) > 0, "the Monster Book counts kills")
	_check(Content.card(dew) is CardDef and Content.card(dew).monster == dew, "every monster has a card")
	ch.book.pages[&"mossling"] = [1, CardDef.SET]
	ch.book.pages[&"petal_bat"] = [1, CardDef.SET]
	ch.book.pages[dew.id] = [ch.book.kills(dew), CardDef.SET - 1]
	ch.recalc()
	var strength := ch.stats.strength
	map.spawn_drop(Content.card(dew), 1, null, DropFlight.create(me.position + Vector2(0, -20), 620.0, me.position.x), me.peer)
	await _ticks(SimDrop.SETTLE_TICKS + 3)
	await _tap("loot")
	await _ticks(3)
	_check(ch.book.cards(dew) == CardDef.SET and Game.me.book.complete(dew), "picking up a card fills in the book")
	_check(ch.book.level() == 2 and ch.stats.strength == strength + 1, "completed pages raise the book's level and your stats")
	_check(ch.achievements.has("first_hunt") and ch.achievements.has("first_page") and Game.me.achievements.has("first_page"), "kills and pages earn achievements")
	await _press("collection")
	var book: TDCollectionWindow = world.hud.windows["collection"]
	book.show_monster(dew)
	_check(book.visible and book.selected == dew and book.pages() >= 2, "L opens the Monster Book")
	await _press("collection")
	# everything saves
	var copy := Character.create("Copy")
	copy.load_dict(ch.to_dict())
	_check(copy.book.cards(dew) == CardDef.SET and copy.achievements == ch.achievements and copy.visited == ch.visited
		and copy.counters.get("sat", 0) == 1 and copy.pet_full == ch.pet_full, "the book, achievements and pet save")
	me.inv = 0
