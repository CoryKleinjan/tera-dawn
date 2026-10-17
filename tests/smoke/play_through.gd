extends SmokeArea
## The single-player play-through: a new character made on the title screen plays the
## village and the meadow. The smoke runner calls these steps in order, with the other areas
## between `windows` and `dawn_slash`.

## The hero (set by start_game).
var p: TDPlayer
## The dialogue window (set by talk_to_elder).
var talk: TDDialogueWindow

## From the title screen through the character creator into a single-player game.
func start_game() -> void:
	await _ticks(5)
	_check(not world.started and world.hud.title.visible, "the game opens on the title screen")
	world.hud.title._on_solo()
	await _ticks(2)
	var select := world.hud.title.character_select
	_check(select.visible and not world.hud.title.title_card.visible and Net.characters.is_empty(), "Play solo opens an empty character select")
	select.create_button.pressed.emit()
	var creator := world.hud.title.creator
	_check(creator.visible and not select.visible and not world.started, "Create opens the character creator")
	creator.name_field.text = "Tester"
	creator.step("outfit:%d" % EquipDef.Slot.TOP, 1)
	var top: EquipDef = creator.made.outfit[EquipDef.Slot.TOP]
	_check(creator.value_text("outfit:%d" % EquipDef.Slot.TOP) == top.display_name, "the creator shows the outfit picked")
	creator.create_button.pressed.emit()
	await _ticks(2)
	_check(select.visible and select.selected == "Tester" and not world.started, "Create goes back to character select with the new character picked")
	select.play_button.pressed.emit()
	await _ticks(2)
	_me().inv = 100000 # keep monsters from hurting the player mid-test
	_check(world.started and not world.hud.title.visible and Game.me.name == "Tester", "Play starts a single-player game as the named character")
	_check(Game.me.equipment.at(&"top").item == top, "the character has the outfit picked")
	_check(Game.me.job.id == Character.START_JOB, "a new character starts as a Beginner")
	_check(Net.server != null and _me() != null, "single player runs its own server")
	p = world.player
	_check(world.map.id == Character.NEW_MAP, "a new character wakes on the tutorial beach")
	# the tutorial has its own tests (server_tutorial_test, tutorial_test): play on in the village
	Net.server.enter_map(_me(), Character.START_MAP, Content.map(Character.START_MAP).start_x)
	await _ticks(3)
	_check(p.on_ground, "player starts on the ground")
	_check(world.npcs().size() == 6, "the village has its six NPCs (Mira keeps shop indoors)")
	await _ticks(5)
	_check(world.mobs().all(func(m: TDMob) -> bool: return m.known), "the server tells the game where every monster is")

## Walking, the server checking moves, and jumping.
func walk_and_jump() -> void:
	var x0 := p.position.x
	await _hold("move_right", 40)
	_check(p.position.x > x0 + 60, "walking right moves the player")
	await _ticks(4)
	_check(absf(_me().position.x - p.position.x) < 6.0, "the server hears where the player walked")
	var before := _me().position
	Net.server.on_move(1, before + Vector2(900, 0), 1, &"walk")
	_check(_me().position == before and absf(p.position.x - before.x) < 1.0, "the server refuses an impossible move and puts the player back")

	await _tap("jump")
	await _ticks(10)
	_check(p.position.y < 620, "jumping leaves the ground")
	await _ticks(40)
	_check(p.on_ground, "player lands again")

## Talking to the village elder.
func talk_to_elder() -> void:
	# Talk to the village elder.
	var elder := world.npcs()[0]
	_teleport(Vector2(elder.position.x - 30, 620))
	await _ticks(2)
	await _tap("move_up")
	talk = world.hud.windows["dialogue"]
	_check(talk.visible and talk.npc == elder and talk.text != "", "pressing Up next to an NPC opens their dialogue")
	var greeting := talk.text
	var chat: int = talk.options.map(func(o: Array) -> String: return o[0]).find("Chat")
	talk.choose(chat)
	_check(chat >= 0 and talk.text != greeting, "Chat moves on to their next line")
	talk.choose(talk.options.size() - 1)
	_check(not talk.visible, "Goodbye closes the dialogue")

## Into Mira's shop room: buying, selling, walking away, and back out.
func visit_shop() -> void:
	# Mira's shop is a room inside her house: walk in through its door.
	var door: PortalDef = Content.map(Character.START_MAP).portals.filter(func(d: PortalDef) -> bool: return d.target_map == &"meadow_store")[0]
	_check(door.door and Content.map(Character.START_MAP).buildings.any(func(b: BuildingPlacement) -> bool: return b.x == door.x),
		"the shop's door is a doorway in a building")
	_teleport(Vector2(door.x, 620))
	await _ticks(2)
	await _tap("move_up")
	await _ticks(TDPlayer.PORTAL_FADE_TICKS + 4)
	_check(world.map.id == &"meadow_store" and world.map.interior, "pressing Up in the doorway walks into the shop")
	_check(world.map.outside() == Character.START_MAP, "the shop is inside the village")
	# Mira runs a shop: buy potions, sell monster parts.
	var mira: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.shop != null)[0]
	_teleport(Vector2(mira.position.x - 30, 620))
	await _ticks(2)
	await _tap("move_up")
	var labels := talk.options.map(func(o: Array) -> String: return o[0])
	_check(talk.visible and labels.has("Open shop"), "the shopkeeper offers her shop")
	talk.choose(labels.find("Open shop"))
	var shop: TDShopWindow = world.hud.windows["shop"]
	_check(shop.visible and not talk.visible and shop.shop == mira.def.shop, "Open shop opens her shop window")
	_me().character.shards = 1000
	_me().character.inventory.add(Content.item(&"boar_tusk"), 5)
	_me().character.inventory.add(Content.item(&"moss_tuft"), 3)
	_me().dirty_character = true
	await _ticks(1)
	var red_potion: ItemDef = Content.item(&"red_potion")
	var reds := Game.me.inventory.count_of(red_potion)
	shop.amount = 10
	shop.buy(0)
	await _ticks(1)
	_check(Game.me.inventory.count_of(red_potion) == reds + 10 and Game.me.shards == 1000 - 10 * mira.def.shop.items[0].cost(), "buying 10 Red Potions takes their price")
	var shards_now := Game.me.shards
	var gear_line := -1
	for i in mira.def.shop.items.size():
		if mira.def.shop.items[i].item is EquipDef:
			gear_line = i
			break
	shop.buy(gear_line)
	await _ticks(1)
	_check(Game.me.shards == shards_now - mira.def.shop.items[gear_line].cost(), "gear is bought one at a time")
	shop.tab = ItemDef.Tab.ETC
	var tusk_slot := -1
	for i in Inventory.SLOTS:
		var st := Game.me.inventory.at(ItemDef.Tab.ETC, i)
		if st and st.item.id == &"boar_tusk":
			tusk_slot = i
	shards_now = Game.me.shards
	shop.amount = 1
	shop.sell(tusk_slot)
	await _ticks(1)
	_check(Game.me.inventory.count_of(Content.item(&"boar_tusk")) == 4 and Game.me.shards == shards_now + Content.item(&"boar_tusk").sell_price, "selling one Boar Tusk pays its price")
	# with the shop open, the Inventory window sells too: double-click, right-click or drag
	var tusk: ItemDef = Content.item(&"boar_tusk")
	var bag: TDInventoryWindow = world.hud.windows["inventory"]
	bag.tab = ItemDef.Tab.ETC
	bag._click(bag.slot_rect(tusk_slot).get_center(), MOUSE_BUTTON_LEFT, true)
	await _ticks(1)
	_check(Game.me.inventory.count_of(tusk) == 3, "double-clicking an item in the Inventory sells it while a shop is open")
	bag._click(bag.slot_rect(tusk_slot).get_center(), MOUSE_BUTTON_RIGHT, false)
	await _ticks(1)
	_check(Game.me.inventory.count_of(tusk) == 2, "right-clicking it sells it too")
	shop._drop_data(Vector2.ZERO, DragPayload.bag_item(ItemDef.Tab.ETC, tusk_slot))
	await _ticks(1)
	_check(Game.me.inventory.count_of(tusk) == 1, "dragging an item onto the shop sells it")
	# gear asks first (only while the shop sells some)
	if gear_line >= 0:
		await _sell_gear_from_bag(bag, mira.def.shop.items[gear_line].item)
	bag.tab = ItemDef.Tab.USE
	Net.ask(&"req_sell_all_etc", [mira.def.id])
	await _ticks(1)
	_check(Game.me.inventory.free_slots(ItemDef.Tab.ETC) == Inventory.SLOTS, "Sell all Etc empties the Etc tab")
	_me().character.shards = 0
	_me().dirty_character = true
	await _ticks(1)
	shop.buy(4)
	await _ticks(1)
	_check(Game.me.shards == 0 and Game.me.inventory.count_of(Content.item(&"elixir")) == 0, "you can't buy what you can't afford")
	_teleport(Vector2(mira.position.x + 450, 620))
	await _until(func() -> bool: return not shop.visible, 30)
	_check(not shop.visible, "walking away closes the shop")
	Net.ask(&"req_buy", [mira.def.id, 0, 1])
	await _ticks(1)
	_check(Game.me.inventory.count_of(red_potion) == reds + 10, "the server won't sell from across the room")
	# and back out into the village, beside the door
	var out: PortalDef = world.map.portals[0]
	_teleport(Vector2(out.x, 620))
	await _ticks(2)
	await _tap("move_up")
	await _ticks(TDPlayer.PORTAL_FADE_TICKS + 4)
	_check(world.map.id == Character.START_MAP and absf(world.player.position.x - door.x) < 120, "the room's door leads back out beside the shop")

## Double-clicks a piece of gear `bought` in the Inventory with a shop open: it asks, then sells on OK.
func _sell_gear_from_bag(bag: TDInventoryWindow, bought: ItemDef) -> void:
	var gear_slot := -1
	for i in Inventory.SLOTS:
		var st := Game.me.inventory.at(ItemDef.Tab.EQUIP, i)
		if st and st.item == bought:
			gear_slot = i
	bag.tab = ItemDef.Tab.EQUIP
	var shards_now := Game.me.shards
	bag._click(bag.slot_rect(gear_slot).get_center(), MOUSE_BUTTON_LEFT, true)
	await _ticks(1)
	_check(world.hud.confirm.visible and Game.me.inventory.count_of(bought) == 1, "selling gear asks first")
	world.hud.confirm.ok_button.pressed.emit()
	await _ticks(1)
	_check(Game.me.inventory.count_of(bought) == 0 and Game.me.shards == shards_now + bought.sell_price, "and sells it on OK")
	bag.tab = ItemDef.Tab.USE

## Out of the village to the meadow.
func go_to_meadow() -> void:
	# the hunting starts in the meadow, through the village's east exit
	var to_meadow: PortalDef = world.map.portals.filter(func(d: PortalDef) -> bool: return d.target_map == &"meadow")[0]
	_teleport(Vector2(to_meadow.x, 620))
	await _ticks(2)
	await _tap("move_up")
	await _ticks(TDPlayer.PORTAL_FADE_TICKS + 4)
	_check(world.map.id == &"meadow" and not world.map.town and not world.mobs().is_empty(), "the village's east exit leads to the meadow, where the monsters are")

## Killing a Dewling, its Dawn Essence and Dawnshards.
func first_kill() -> void:
	# Put a Dewling right in front of the player and hit it until it dies.
	var meadow: MapInstance = Net.server.maps[&"meadow"]
	var mob: SimMob = null
	for m in meadow.mobs:
		if m.def.id == &"dewling" and m.plat == meadow.layout.platforms[0]:
			mob = m
			break
	var others := _hold_mobs(meadow, [mob])
	_teleport(Vector2(mob.position.x - 40, 620))
	p.face = 1
	var essence_before: int = Game.me.essence
	var shards: int = Game.me.shards
	for i in 12:
		mob.position.x = p.position.x + 40
		await _tap("attack")
		await _ticks(24)
		if mob.dead:
			break
	_check(mob.dead, "basic attacks kill a Dewling")
	_release_mobs(others)
	await _ticks(4)
	_check(world.mobs()[mob.index].dead, "the game shows the Dewling defeated")
	_check(Game.me.essence > essence_before, "killing a monster gives Dawn Essence")
	# Drops land next to the player, so some may already be picked up by now.
	_check(not meadow.drops.is_empty() or Game.me.shards > shards, "the monster drops Dawnshards")
	_check(world.drops.size() == meadow.drops.size(), "the game shows the same drops as the server")
	await _ticks(80)
	for d in meadow.drops.values():
		if d.item.is_currency and not d.taken:
			_teleport(Vector2(d.flight.position.x, 620))
			await _ticks(5)
	var currency_left := meadow.drops.values().filter(func(d: SimDrop) -> bool: return d.item.is_currency)
	_check(Game.me.shards > shards and currency_left.is_empty(), "walking over Dawnshards picks them up")

## Items on the ground wait for the loot key.
func loot() -> void:
	# Items wait for the loot key.
	var meadow: MapInstance = Net.server.maps[&"meadow"]
	for d in meadow.drops.values():
		meadow._remove_drop(d, 0)
	var tusk: ItemDef = Content.item(&"boar_tusk")
	var boots: EquipDef = Content.item(&"leather_boots")
	for item in [tusk, boots]:
		meadow.spawn_drop(item, 1, null, DropFlight.create(p.position + Vector2(0, -20), 620, p.position.x), 0)
	await _ticks(40)
	_check(meadow.drops.size() == 2 and world.drops.size() == 2, "items stay on the ground until looted")
	await _hold("loot", 24)
	_check(Game.me.inventory.count_of(tusk) == 1 and Game.me.inventory.count_of(boots) == 1 and world.drops.is_empty(), "the loot key picks up items and gear")

## Drinking a potion, and taking gear off and on.
func potion_and_gear() -> void:
	# A Red Potion from the Use tab heals.
	_me().character.health.set_hp(1)
	var red: ItemDef = Content.item(&"red_potion")
	var potions := Game.me.inventory.count_of(red)
	world.hud.windows["inventory"].tab = ItemDef.Tab.USE
	world.hud.windows["inventory"].use_slot(_first_filled(Game.me, ItemDef.Tab.USE))
	await _ticks(1)
	_check(Game.me.health.hp > 1 and Game.me.inventory.count_of(red) == potions - 1, "drinking a Red Potion heals and uses it up")

	# Gear changes go through the server too.
	var attack := Game.me.stats.attack
	world.hud.windows["equipment"]._click(world.hud.windows["equipment"].slot_rect(&"weapon").get_center(), MOUSE_BUTTON_LEFT, true)
	await _ticks(1)
	_check(Game.me.equipment.at(&"weapon") == null and Game.me.stats.attack < attack, "double-clicking the worn sword takes it off")
	world.hud.windows["inventory"].tab = ItemDef.Tab.EQUIP
	var sword_slot := -1
	for i in Inventory.SLOTS:
		var st := Game.me.inventory.at(ItemDef.Tab.EQUIP, i)
		if st and st.item.id == &"training_sword":
			sword_slot = i
	world.hud.windows["inventory"].use_slot(sword_slot)
	await _ticks(1)
	_check(Game.me.stats.attack == attack, "double-clicking it in the bag wears it again")

## The windows, tooltips, the gear panel and the game menu.
func windows() -> void:
	# The windows open with their keys and Esc closes them.
	for action in TDHud.WINDOW_ACTIONS:
		await _press(action)
	var all_open := true
	for action in TDHud.WINDOW_ACTIONS:
		all_open = all_open and world.hud.windows[action].visible
	_check(all_open, "I, E and S open the inventory, equipment and character windows")
	world.hud.toggle_window("worldmap") # it covers the others
	# Hovering gear in the bag shows its tooltip, compared with what's worn.
	var inv: TDInventoryWindow = world.hud.windows["inventory"]
	inv.tab = ItemDef.Tab.EQUIP
	inv.raise() # the Collection window opens over it
	var slot := _first_filled(Game.me, ItemDef.Tab.EQUIP)
	var move := InputEventMouseMotion.new()
	move.position = get_viewport().get_final_transform() * (inv.global_position + inv.slot_rect(slot).get_center())
	move.global_position = move.position
	Input.parse_input_event(move)
	Input.flush_buffered_events()
	await _ticks(2)
	var tip := world.hud.tooltip
	var lines := tip._lines() if tip.stack else []
	_check(tip.stack == Game.me.inventory.at(ItemDef.Tab.EQUIP, slot) and lines.any(func(l): return str(l[0]).begins_with("vs. worn") or str(l[0]) == "Nothing worn in this slot"),
		"hovering gear in the inventory shows its tooltip and how it compares with what's worn")
	# The equipment window lists what the gear adds.
	var gear: TDEquipmentWindow = world.hud.windows["equipment"]
	gear._click(gear.slot_rect(&"weapon").get_center(), MOUSE_BUTTON_LEFT, false)
	_check(gear.selected == &"weapon", "clicking a worn item shows its own stats in the gear panel")
	gear._click(gear.slot_rect(&"weapon").get_center(), MOUSE_BUTTON_LEFT, false)
	_check(gear.selected == &"", "clicking it again shows the whole set's bonuses")
	for action in TDHud.WINDOW_ACTIONS:
		if world.hud.windows.values().any(func(w: TDWindow) -> bool: return w.visible):
			await _press("pause")
	_check(world.started and not world.hud.title.visible and not world.hud.windows["stats"].visible, "Esc closes the windows before opening the menu")
	await _press("pause")
	_check(world.hud.title.visible and world.hud.game_menu.visible, "Esc again opens the game menu")
	world.hud.game_menu.resume_button.pressed.emit()
	_check(not world.hud.title.visible, "Resume closes it")

## Dawn Slash.
func dawn_slash() -> void:
	_me().inv = 100000 # a monster's touch would knock the player off the portal

	# Dawn Slash costs MP and hits several monsters.
	var mp_before := Game.me.mp
	p.cooldown = 0
	_me().cooldown = 0
	await _tap("quick_2")
	_check(p.action_anim == Content.skill(&"dawn_slash").animation, "Dawn Slash makes its motion")
	# MP regen may tick once during the key press.
	_check(mp_before - Game.me.mp >= Content.skill(&"dawn_slash").mp_at(1) - 1, "Dawn Slash spends MP")

## A portal to Fern Hollow.
func portal() -> void:
	await _ticks(40)
	# Walk through the portal to Fern Hollow.
	_teleport(Vector2(2530, 620))
	await _ticks(3)
	await _tap("move_up")
	await _until(func() -> bool: return world.map.id == &"hollow", 30)
	_check(world.map.id == &"hollow" and _me().map.def.id == &"hollow", "the portal leads to Fern Hollow")
	await _ticks(60)
	_check(world.stage.fade < 0.05, "the new map fades back in after a portal (fade %.2f)" % world.stage.fade)
	var boss := false
	for m in world.mobs():
		boss = boss or m.def.boss
	_check(not world.mobs().is_empty() and not boss, "Fern Hollow has its monsters, and its boss waits in its own arena")

## Fainting and waking up in town.
func faint() -> void:
	# Fainting sends the player back to town.
	_me().inv = 0
	_me().character.health.set_hp(1)
	var hollow: MapInstance = Net.server.maps[&"hollow"]
	for n in 20: # a touch can miss
		if not _me().fainted():
			_me().inv = 0
			hollow.touch_player(_me(), hollow.mobs[0])
	_check(p.fainted(), "running out of HP faints the player")
	await _ticks(SimPlayer.FAINT_TICKS + 5)
	_check(not p.fainted() and world.map.id == Character.START_MAP and Game.me.health.hp > 0, "after fainting the player wakes up in town")

## Leaving the world for character select, then the game.
func leave() -> void:
	world.hud.show_title(true)
	world.hud.game_menu.characters_button.pressed.emit()
	await _ticks(2)
	_check(world.hud.title.character_select.visible and not world.started and Net.mode == Net.Mode.SINGLE, "Character select in the menu leaves the world but stays in the game")
	world.hud.title.character_select.leave_button.pressed.emit()
	_check(Net.mode == Net.Mode.NONE and world.hud.title.title_card.visible, "Back goes to the title screen")
	_check(CharacterStore.new(save_dir).load_character("Tester") != null, "leaving saves the character")
