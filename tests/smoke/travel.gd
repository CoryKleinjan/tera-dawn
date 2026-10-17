extends SmokeArea
## Getting around: the world map, travel NPCs, return scrolls and storage.

## The world map, Hobb's wagon, return scrolls, and waking up in the right town.
func check() -> void:
	var ch := _me().character
	Net.server.enter_map(_me(), Character.START_MAP, 300)
	await _ticks(3)
	await _press("worldmap")
	var wm: TDWorldMapWindow = world.hud.windows["worldmap"]
	_check(wm.visible and TDWorldMapWindow.placed().size() >= 2, "W opens the world map with the maps on it")
	wm.open_zone(&"")
	var isle: StringName = Content.map(Character.START_MAP).region
	wm._click(wm.to_screen(TDWorldMapWindow.capital_pos(Content.regions[isle])), MOUSE_BUTTON_LEFT, false)
	_check(wm.zone == isle, "clicking a region on the world map opens its zone")
	wm._hovered(wm.to_screen(Content.map(&"hollow").world_pos))
	_check(wm.hovered == &"hollow", "hovering a dot picks that map")
	wm.open_zone(&"")
	await _press("worldmap")
	# Hobb's wagon to Fern Hollow costs 150 Dawnshards.
	var hobb: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"wagon_driver")[0]
	# Dawnshards left on the ground from earlier kills would change the purse
	for id in [&"meadow", &"hollow"]:
		if Net.server.maps.has(id):
			_clear_drops(Net.server.maps[id])
	ch.shards = 1000
	_me().dirty_vitals = true
	_me().inv = 100000
	_teleport(Vector2(hobb.position.x - 30, 620))
	await _ticks(2)
	await _tap("move_up")
	var talk: TDDialogueWindow = world.hud.windows["dialogue"]
	var labels: Array = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels.has("Travel"), "the wagon driver offers to travel")
	talk.choose(labels.find("Travel"))
	_check(str(talk.options[0][0]) == "Wagon to Fern Hollow (150 Dawnshards)", "the trip lists where it goes and the fare, no level: %s" % talk.options[0][0])
	talk.choose(0)
	await _until(func() -> bool: return world.map.id == &"hollow" and Game.me.shards == 850, 30)
	_check(world.map.id == &"hollow" and Game.me.shards == 850, "the wagon takes you there for 150 Dawnshards")
	# A Return Scroll brings you back to town.
	var scroll: ItemDef = Content.item(&"return_scroll")
	ch.inventory.add(scroll, 2)
	_me().dirty_character = true
	_me().item_cd = 0
	await _ticks(2)
	world.hud.windows["inventory"].tab = ItemDef.Tab.USE
	world.hud.windows["inventory"].use_slot(Game.me.inventory.find(scroll))
	await _ticks(3)
	_check(world.map.id == Character.START_MAP and Game.me.inventory.count_of(scroll) == 1, "a Return Scroll takes you back to town")
	_me().item_cd = 0
	world.hud.windows["inventory"].use_slot(Game.me.inventory.find(scroll))
	await _ticks(2)
	_check(Game.me.inventory.count_of(scroll) == 1, "it isn't used up when you're already in town")
	_check(Content.map(&"hollow").return_town() == Character.START_MAP and Content.map(&"meadow").return_town() == Character.START_MAP, "maps know their town")
	# Captain Marlo's ship from the village dock to Dawnharbor's docks, then Brin's storage,
	# then Rook's coach.
	var dock: PortalDef = Content.map(Character.START_MAP).portals.filter(func(p: PortalDef) -> bool: return p.target_map == &"dawnrise_dock")[0]
	_teleport(Vector2(dock.x, 620))
	await _ticks(2)
	await _tap("move_up")
	await _until(func() -> bool: return world.map.id == &"dawnrise_dock", 30)
	_check(world.map.id == &"dawnrise_dock", "the village's dock portal leads to Dawnrise Dock")
	var marlo: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"captain_marlo")[0]
	_teleport(Vector2(marlo.position.x - 30, 620))
	await _ticks(2)
	await _tap("move_up")
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	talk.choose(labels.find("Travel"))
	talk.choose(0)
	await _ticks(3)
	_check(world.map.id == &"dawnharbor_docks", "Captain Marlo sails to Dawnharbor's docks")
	_check(world.npcs().any(func(n: TDNpc) -> bool: return n.def.id == &"dock_marlo"), "and he waits there with his ship")
	Net.server.enter_map(_me(), &"dawnharbor", 360)
	await _ticks(3)
	var brin: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"storage_keeper")[0]
	_teleport(Vector2(brin.position.x - 30, brin.position.y))
	await _ticks(2)
	await _tap("move_up")
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels.has("Open storage"), "the storage keeper offers storage")
	talk.choose(labels.find("Open storage"))
	var vault: TDStorageWindow = world.hud.windows["storage"]
	_check(vault.visible, "the storage window opens")
	var tusk: ItemDef = Content.item(&"boar_tusk")
	ch.inventory.remove(tusk, 1000)
	ch.inventory.add(tusk, 7)
	_me().dirty_character = true
	await _ticks(2)
	var shards := Game.me.shards
	vault.tab = ItemDef.Tab.ETC
	vault.store(Game.me.inventory.find(tusk))
	await _ticks(2)
	_check(Game.me.inventory.count_of(tusk) == 0 and Game.me.storage.count_of(tusk) == 7 and Game.me.shards == shards - Character.STORE_FEE, "storing a stack costs the fee")
	vault.take(Game.me.storage.find(tusk))
	await _ticks(2)
	_check(Game.me.inventory.count_of(tusk) == 7 and Game.me.storage.count_of(tusk) == 0, "and it can be taken back")
	vault.visible = false
	var rook: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"harbor_taxi")[0]
	# Earlier checks may have been to some job towns: start from none.
	var towns: Array[String] = ["greenbough", "lumewood", "emberforge", "lanternfall", "driftcove"]
	for c: Character in [_me().character, Game.me]:
		c.visited = c.visited.filter(func(id: String) -> bool: return not towns.has(id))
	_teleport(Vector2(rook.position.x - 30, rook.position.y))
	await _ticks(2)
	await _tap("move_up")
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	talk.choose(labels.find("Travel"))
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels == ["Back"], "Rook's coach goes nowhere you haven't been yet")
	talk.choose(labels.find("Back"))
	for town in towns:
		_me().character.visit(StringName(town))
		Game.me.visit(StringName(town))
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	talk.choose(labels.find("Travel"))
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels.size() == 6, "and once you have, it goes to all five job towns")
	talk.choose(0)
	await _ticks(3)
	_check(world.map.id == &"greenbough", "the coach takes you to Greenbough")
	Net.server.enter_map(_me(), Character.START_MAP, 300)
	await _ticks(3)
