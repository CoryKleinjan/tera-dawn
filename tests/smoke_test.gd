extends Node
## Headless smoke test: godot --headless --path . res://tests/smoke_test.tscn
## Plays a short scripted session and checks the core loop works.

const SAVE_DIR := "user://smoke_test_characters"
const TEST_PORT := 7391

var world: TDWorld
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _hold(action: String, n: int) -> void:
	Input.action_press(action)
	await _ticks(n)
	Input.action_release(action)
	await _ticks(1)

func _tap(action: String) -> void:
	await _hold(action, 2)

func _check_content() -> void:
	_check(Content.monsters.size() >= 9, "monster definitions load (%d)" % Content.monsters.size())
	_check(Content.maps.has(&"meadow") and Content.maps.has(&"hollow"), "both maps load")
	for id in Game.SKILL_BINDINGS.values():
		_check(Content.skill(id) != null, "skill %s is defined" % id)
	var problems := []
	for id in Content.maps:
		var map: MapDef = Content.maps[id]
		var count := map.platforms.size() + 1
		for s in map.spawns:
			if s.monster == null or s.platform >= count:
				problems.append("%s: bad spawn" % id)
		for p in map.portals:
			if not Content.maps.has(p.target_map) or p.platform >= count:
				problems.append("%s: portal to %s" % [id, p.target_map])
		for n in map.npcs:
			if n.npc == null or n.platform >= count:
				problems.append("%s: bad NPC" % id)
			elif n.npc.instructs.any(func(j: StringName) -> bool: return not Content.jobs.has(j)):
				problems.append("%s: %s teaches an unknown job" % [id, n.npc.id])
		for c in map.climbables:
			if c.style == null or c.style.middle == null:
				problems.append("%s: climbable at %d has no style" % [id, c.x])
	for id in Content.monsters:
		var m: MonsterDef = Content.monsters[id]
		if m.sprite_frames == null and m.texture == null:
			problems.append("monster %s has no sprite" % id)
		for d in m.drops:
			if d.item == null:
				problems.append("monster %s drops nothing" % id)
	for id in Content.items:
		var item: ItemDef = Content.items[id]
		if item.icon == null:
			problems.append("item %s has no icon" % id)
		if item is EquipDef and (item as EquipDef).stats == null:
			problems.append("equip %s has no stats" % id)
	for id in Content.jobs:
		var job: JobDef = Content.jobs[id]
		if job.advances_from == &"" and (job.starting_stats == null or job.starting_gear.has(null)):
			problems.append("job %s is missing starting stats or gear" % id)
		if job.advances_from != &"" and not Content.jobs.has(job.advances_from):
			problems.append("job %s advances from unknown job %s" % [id, job.advances_from])
		for g in job.advance_gifts:
			if g == null or g.item == null:
				problems.append("job %s has an empty advancement gift" % id)
	_check(problems.is_empty(), "maps, monsters, items and jobs reference valid content %s" % [problems])
	_check(Content.jobs.has(Character.START_JOB), "the starting job is defined")
	var shop_problems := []
	for id in Content.shops:
		for e in Content.shops[id].items:
			if e == null or e.item == null or e.cost() <= 0:
				shop_problems.append(id)
	_check(not Content.shops.is_empty() and shop_problems.is_empty(), "every shop sells real items at a price %s" % [shop_problems])
	var placed := {}
	for id in Content.maps:
		for n in Content.maps[id].npcs:
			placed[n.npc.id] = true
	var quest_problems := []
	for id in Content.quests:
		var q: QuestDef = Content.quests[id]
		if not placed.has(q.giver) or not placed.has(q.turn_in_npc()) or q.objectives.is_empty():
			quest_problems.append(id)
		for r in q.requires:
			if not Content.quests.has(r):
				quest_problems.append("%s needs %s" % [id, r])
		for o in q.objectives:
			if (o.kind == QuestObjective.Kind.KILL and o.monster == null) or (o.kind == QuestObjective.Kind.COLLECT and o.item == null) \
				or (o.kind == QuestObjective.Kind.VISIT and not Content.maps.has(o.map)):
				quest_problems.append("%s has a broken objective" % id)
	_check(Content.quests.size() >= 6 and quest_problems.is_empty(), "every quest has a placed giver and real objectives %s" % [quest_problems])

func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await _ticks(1)
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await _ticks(1)

func _first_filled(c: Character, tab: int) -> int:
	for i in Inventory.SLOTS:
		if c.inventory.at(tab, i) != null:
			return i
	return -1

## Inventory, equipment, stats and saving, without the world.
func _check_character() -> void:
	var c := Character.create("Tester")
	var sword: EquipDef = Content.item(&"training_sword")
	_check(c.equipment.at(&"weapon") != null and c.equipment.at(&"weapon").item == sword, "a new character wears the starting sword")
	_check(c.inventory.count_of(Content.item(&"red_potion")) == 5, "a new character carries 5 Red Potions")
	var dmg := c.damage_range()
	_check(dmg.x > 0 and dmg.y >= dmg.x, "the damage range comes from stats and the weapon (%d ~ %d)" % [dmg.x, dmg.y])

	# stacking and a full tab
	var red: ItemDef = Content.item(&"red_potion")
	c.inventory.add(red, 150)
	_check(c.inventory.count_of(red) == 155 and c.inventory.at(ItemDef.Tab.USE, 0).count == 100 and c.inventory.at(ItemDef.Tab.USE, 1).count == 55, "potions stack up to 100 a slot")
	var tusk: ItemDef = Content.item(&"boar_tusk")
	var left := c.inventory.add(tusk, 200 * Inventory.SLOTS + 7)
	_check(left == 7 and not c.inventory.has_room(tusk), "a full Etc tab hands back what doesn't fit")
	c.inventory.clear()

	# unequip and equip change stats
	var attack := c.stats.attack
	_check(c.unequip(&"weapon") == "" and c.stats.attack == attack - sword.stats.attack, "taking off the sword lowers Weapon Attack")
	_check(c.equip(_first_filled(c, ItemDef.Tab.EQUIP)) == "" and c.stats.attack == attack, "putting it back on restores Weapon Attack")
	c.inventory.add(Content.item(&"leaf_cap"))
	var defense := c.stats.defense
	c.equip(_first_filled(c, ItemDef.Tab.EQUIP))
	_check(c.stats.defense > defense, "wearing a hat raises Weapon Defense")
	c.inventory.add(Content.item(&"dawn_blade"))
	_check(c.equip(_first_filled(c, ItemDef.Tab.EQUIP)) != "", "level 1 can't wear the level 8 Dawn Blade")

	# levels give Ability Points, and STR raises damage
	c.gain_xp(c.xp_need())
	_check(c.level == 2 and c.ap == c.job.ap_per_level, "levelling up gives Ability Points")
	var top := c.damage_range().y
	for n in 5:
		c.add_ap(&"strength")
	_check(c.ap == 0 and c.damage_range().y > top, "spending AP on STR raises damage")

	# saving and loading keeps the bag and the gear
	c.inventory.add(tusk, 3)
	var store := CharacterStore.new(SAVE_DIR)
	store.save(c)
	var back := store.load_character("Tester")
	_check(back != null and JSON.stringify(back.inventory.to_dict()) == JSON.stringify(c.inventory.to_dict())
		and JSON.stringify(back.equipment.to_dict()) == JSON.stringify(c.equipment.to_dict())
		and back.base.strength == c.base.strength and back.level == 2, "saving and loading keeps inventory, equipment and stats")
	_check(CharacterStore.clean_name("  Dawn<ling>!  ") == "Dawnling", "character names are cleaned up")
	_check_jobs()

## Starting as a Beginner, advancing, and gear only some jobs can use.
func _check_jobs() -> void:
	var c := Character.create("Rookie")
	_check(c.job.id == &"beginner", "new characters start as Beginners")
	var warrior: JobDef = Content.job(&"warrior")
	var mage: JobDef = Content.job(&"mage")
	for id in [&"warrior", &"archer", &"mage", &"thief", &"pirate"]:
		_check(Content.jobs.has(id) and Content.job(id).advances_from == &"beginner", "%s is a first job" % id)
	_check(c.advance(warrior).begins_with("You need to be level"), "a level 1 Beginner can't advance")
	c.level = 10
	_check(c.advance(warrior).contains("STR"), "advancing to Warrior needs 35 STR")
	c.base.strength = 35
	var hp := c.max_hp()
	_check(c.advance(warrior) == "" and c.job == warrior, "a level 10 Beginner with 35 STR becomes a Warrior")
	_check(c.inventory.count_of(Content.item(&"bronze_sword")) == 1 and c.max_hp() >= hp, "the Warrior gets a Bronze Sword")
	_check(c.advance(mage) != "", "a Warrior can't then become a Magician")
	var wand: EquipDef = Content.item(&"apprentice_wand")
	c.inventory.add(wand)
	var slot := -1
	for i in Inventory.SLOTS:
		var st := c.inventory.at(ItemDef.Tab.EQUIP, i)
		if st and st.item == wand:
			slot = i
	_check(c.equip(slot).begins_with("Only Mages"), "a Warrior can't wear a wand")

## Empties the test's character folder, so every run starts from new characters.
func _clear_saves() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	for f in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR.path_join(f))

## The server's view of this game's own player.
func _me() -> SimPlayer:
	return Net.server.sessions.get(multiplayer.get_unique_id())

## Moves the player somewhere instantly, on both sides (a real client can't do this:
## the server would put it back).
func _teleport(at: Vector2) -> void:
	world.player.position = at
	world.player.vel = Vector2.ZERO
	_me().position = at

func _run() -> void:
	_check_content()
	_clear_saves()
	_check_character()
	# Play single player against a server inside this game, with test-only saves.
	_clear_saves()
	Net.save_dir = SAVE_DIR
	Net.import_legacy_save = false
	world = load("res://scenes/world.tscn").instantiate() as TDWorld
	add_child(world)
	await _ticks(5)
	_check(not world.started and world.hud.title.visible, "the game opens on the title screen")
	world.hud.name_field.text = "Tester"
	world.hud._on_play()
	_me().inv = 100000 # keep monsters from hurting the player mid-test
	await _ticks(2)
	_check(world.started and not world.hud.title.visible and Game.me.name == "Tester", "Play starts a single-player game as the named character")
	_check(Net.server != null and _me() != null, "single player runs its own server")
	var p := world.player
	_check(p.on_ground, "player starts on the ground")
	_check(world.npcs().size() == 3, "the meadow has its three NPCs")
	await _ticks(5)
	_check(world.mobs().all(func(m: TDMob) -> bool: return m.known), "the server tells the game where every monster is")

	var x0 := p.position.x
	await _hold("move_right", 40)
	_check(p.position.x > x0 + 60, "walking right moves the player")
	await _ticks(4)
	_check(absf(_me().position.x - p.position.x) < 6.0, "the server hears where the player walked")
	var before := _me().position
	Net.server.on_move(1, before + Vector2(900, 0), 1, &"walk", false)
	_check(_me().position == before and absf(p.position.x - before.x) < 1.0, "the server refuses an impossible move and puts the player back")

	await _tap("jump")
	await _ticks(10)
	_check(p.position.y < 620, "jumping leaves the ground")
	await _ticks(40)
	_check(p.on_ground, "player lands again")

	# Talk to the village elder.
	var elder := world.npcs()[0]
	_teleport(Vector2(elder.position.x - 30, 620))
	await _ticks(2)
	await _tap("move_up")
	var talk: TDDialogueWindow = world.hud.windows["dialogue"]
	_check(talk.visible and talk.npc == elder and talk.text != "", "pressing Up next to an NPC opens their dialogue")
	var greeting := talk.text
	var chat: int = talk.options.map(func(o: Array) -> String: return o[0]).find("Chat")
	talk.choose(chat)
	_check(chat >= 0 and talk.text != greeting, "Chat moves on to their next line")
	talk.choose(talk.options.size() - 1)
	_check(not talk.visible, "Goodbye closes the dialogue")

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
	Net.ask(&"req_sell_all_etc", [mira.def.id])
	await _ticks(1)
	_check(Game.me.inventory.free_slots(ItemDef.Tab.ETC) == Inventory.SLOTS, "Sell all Etc empties the Etc tab")
	_me().character.shards = 0
	_me().dirty_character = true
	await _ticks(1)
	shop.buy(4)
	await _ticks(1)
	_check(Game.me.shards == 0 and Game.me.inventory.count_of(Content.item(&"elixir")) == 0, "you can't buy what you can't afford")
	_teleport(Vector2(mira.position.x + 600, 620))
	await _ticks(2)
	_check(not shop.visible, "walking away closes the shop")
	Net.ask(&"req_buy", [mira.def.id, 0, 1])
	await _ticks(1)
	_check(Game.me.inventory.count_of(red_potion) == reds + 10, "the server won't sell from across the map")

	# Put a Dewling right in front of the player and hit it until it dies.
	var meadow: MapInstance = Net.server.maps[&"meadow"]
	var mob: SimMob = null
	for m in meadow.mobs:
		if m.def.id == &"dewling" and m.plat == meadow.layout.platforms[0]:
			mob = m
			break
	_teleport(Vector2(mob.position.x - 40, 620))
	p.face = 1
	var xp_before: int = Game.me.xp + Game.me.level * 1000
	var shards: int = Game.me.shards
	for i in 12:
		mob.position.x = p.position.x + 40
		await _tap("attack")
		await _ticks(24)
		if mob.dead:
			break
	_check(mob.dead, "basic attacks kill a Dewling")
	await _ticks(4)
	_check(world.mobs()[mob.index].dead, "the game shows the Dewling defeated")
	_check(Game.me.xp + Game.me.level * 1000 > xp_before, "killing a monster gives EXP")
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

	# Items wait for the loot key.
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

	# A Red Potion from the Use tab heals.
	_me().character.health.set_hp(10)
	var red: ItemDef = Content.item(&"red_potion")
	var potions := Game.me.inventory.count_of(red)
	world.hud.windows["inventory"].tab = ItemDef.Tab.USE
	world.hud.windows["inventory"].use_slot(_first_filled(Game.me, ItemDef.Tab.USE))
	await _ticks(1)
	_check(Game.me.health.hp > 10 and Game.me.inventory.count_of(red) == potions - 1, "drinking a Red Potion heals and uses it up")

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

	# The windows open with their keys and Esc closes them.
	for action in TDHud.WINDOW_ACTIONS:
		await _press(action)
	var all_open := true
	for action in TDHud.WINDOW_ACTIONS:
		all_open = all_open and world.hud.windows[action].visible
	_check(all_open, "I, E and S open the inventory, equipment and character windows")
	# Hovering gear in the bag shows its tooltip, compared with what's worn.
	var inv: TDInventoryWindow = world.hud.windows["inventory"]
	inv.tab = ItemDef.Tab.EQUIP
	var slot := _first_filled(Game.me, ItemDef.Tab.EQUIP)
	var move := InputEventMouseMotion.new()
	move.position = get_viewport().get_final_transform() * (inv.global_position + inv.slot_rect(slot).get_center())
	move.global_position = move.position
	Input.parse_input_event(move)
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
		await _press("pause")
	_check(world.started and not world.hud.windows["stats"].visible, "Esc closes the windows before opening the menu")
	await _press("pause")
	_check(world.hud.title.visible and world.hud.pause_panel.visible, "Esc again opens the pause menu")
	world.hud.resume_button.pressed.emit()
	_check(not world.hud.title.visible, "Resume closes it")

	await _check_quests()
	await _check_job_advance()

	# Dawn Slash costs MP and hits several monsters.
	var mp_before := Game.me.mp
	var level := Game.me.level
	p.cooldown = 0
	_me().cooldown = 0
	await _tap("skill")
	_check(p.action_anim == &"slash", "Dawn Slash plays its animation")
	# MP regen may tick once during the key press, and a kill that levels up refills MP.
	_check(Game.me.level > level or mp_before - Game.me.mp >= Content.skill(&"dawn_slash").mp_cost - 1, "Dawn Slash spends MP")

	# Climb the rope at x=700 up to the platform at y=420.
	await _ticks(40)
	_teleport(Vector2(700, 620))
	await _ticks(2)
	await _hold("move_up", 100)
	_check(is_equal_approx(p.position.y, 420.0) and not p.is_climbing(), "climbing a rope reaches the platform above")

	# Walk through the portal to Ember Hollow.
	_teleport(Vector2(2530, 620))
	await _ticks(3)
	await _tap("move_up")
	await _ticks(3)
	_check(world.map.id == &"hollow" and _me().map.def.id == &"hollow", "the portal leads to Ember Hollow")
	var boss := false
	for m in world.mobs():
		boss = boss or m.def.boss
	_check(boss, "Ember Hollow has its boss")

	# Fainting sends the player back to town.
	_me().inv = 0
	_me().character.health.set_hp(1)
	var hollow: MapInstance = Net.server.maps[&"hollow"]
	hollow.touch_player(_me(), hollow.mobs[0])
	_check(p.fainted(), "running out of HP faints the player")
	await _ticks(SimPlayer.FAINT_TICKS + 5)
	_check(not p.fainted() and world.map.id == Character.START_MAP and Game.me.health.hp > 0, "after fainting the player wakes up in town")

	world.hud._on_leave()
	_check(Net.mode == Net.Mode.NONE and world.hud.title.visible, "Leave goes back to the title screen")
	_check(CharacterStore.new(SAVE_DIR).load_character("Tester") != null, "leaving saves the character")

	await _check_multiplayer()

	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Takes Elder Rowan's first quest, does it, hands it in; then a quest whose item only
## drops while you're on it.
func _check_quests() -> void:
	var meadow: MapInstance = Net.server.maps[&"meadow"]
	var elder := world.npcs()[0]
	var q1: QuestDef = Content.quest(&"q01_dewling_trouble")
	_teleport(Vector2(elder.position.x - 30, 620))
	await _ticks(2)
	_check(elder.quest_marker() == "!", "the elder shows a ! for a quest he can give")
	await _tap("move_up")
	var talk: TDDialogueWindow = world.hud.windows["dialogue"]
	var labels: Array = talk.options.map(func(o: Array) -> String: return o[0])
	var i := labels.find("New quest: %s" % q1.title)
	_check(i >= 0, "he offers Dewling Trouble")
	talk.choose(i)
	_check(talk.text.contains(q1.offer_text) and talk.options[0][0] == "Accept", "picking it shows the offer with Accept")
	talk.choose(0)
	await _ticks(1)
	_check(Game.me.quests.active.has(q1.id), "accepting it starts the quest")
	talk.choose(talk.options.size() - 1)
	var xp_level: int = Game.me.level * 100000 + Game.me.xp
	var potions := Game.me.inventory.count_of(Content.item(&"red_potion"))
	var shards := Game.me.shards
	var dewlings := meadow.mobs.filter(func(m: SimMob) -> bool: return m.def.id == &"dewling")
	for n in 8:
		var m: SimMob = dewlings[n % dewlings.size()]
		m._reset()
		meadow.kill_mob(m, _me())
	await _ticks(1)
	_check(Game.me.quests.is_ready(q1, Game.me) and elder.quest_marker() == "?", "defeating 8 Dewlings readies it, and the elder shows a ?")
	world.hud.windows["quests"].toggle()
	_check(world.hud.windows["quests"].listed().has(q1), "the quest log lists it in progress")
	world.hud.windows["quests"].toggle()
	await _tap("move_up")
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	talk.choose(labels.find("Hand in: %s" % q1.title))
	talk.choose(0)
	await _ticks(1)
	_check(Game.me.quests.done.has(q1.id) and not Game.me.quests.active.has(q1.id), "handing it in finishes it")
	_check(Game.me.inventory.count_of(Content.item(&"red_potion")) == potions + 5 and Game.me.shards >= shards + q1.reward_shards
		and Game.me.level * 100000 + Game.me.xp > xp_level, "it pays its EXP, Dawnshards and potions")
	talk.choose(talk.options.size() - 1)

	# Petal Nectar only drops for someone on Sweet Nectar.
	var nectar: ItemDef = Content.item(&"petal_nectar")
	var bat: SimMob = meadow.mobs.filter(func(m: SimMob) -> bool: return m.def.id == &"petal_bat")[0]
	var nectar_drops := func() -> int:
		return meadow.drops.values().filter(func(d: SimDrop) -> bool: return d.item == nectar).size()
	for n in 10:
		bat._reset()
		meadow.kill_mob(bat, _me())
	_check(nectar_drops.call() == 0, "quest items don't drop without the quest")
	var ch := _me().character
	ch.quests.done[&"q02_moss_for_the_stall"] = 1
	ch.level = maxi(ch.level, 3)
	ch.quests.accept(Content.quest(&"q04_sweet_nectar"))
	for n in 10:
		bat._reset()
		meadow.kill_mob(bat, _me())
	_check(nectar_drops.call() > 0, "they do once you're on it")
	server_forfeit_check(ch)

## Guide Sorrel turns a ready Beginner into a Magician through the dialogue window.
func _check_job_advance() -> void:
	var guide: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"guide_sorrel")[0]
	var ch := _me().character
	ch.job = Content.job(&"beginner")
	ch.level = maxi(ch.level, 8)
	ch.base.intelligence = 20
	_me().dirty_character = true
	await _ticks(2)
	_teleport(Vector2(guide.position.x - 30, 620))
	await _ticks(2)
	await _tap("move_up")
	var talk: TDDialogueWindow = world.hud.windows["dialogue"]
	var labels: Array = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels.has("Choose a job"), "the job instructor offers to choose a job")
	talk.choose(labels.find("Choose a job"))
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels.size() == 6, "five first jobs to pick from")
	talk.choose(labels.find("Magician"))
	_check(talk.options[0][0] == "Become a Magician", "a level 8 Beginner with 20 INT may become a Magician")
	talk.choose(0)
	await _ticks(2)
	_check(Game.me.job.id == &"mage" and Game.me.inventory.count_of(Content.item(&"apprentice_wand")) == 1, "the server makes them a Magician and gives a wand")
	_check(world.player.rig.body.modulate == Content.job(&"mage").tint, "the hero takes the Magician's colours")

func server_forfeit_check(ch: Character) -> void:
	Net.ask(&"req_quest_forfeit", [&"q04_sweet_nectar"])
	_check(not ch.quests.active.has(&"q04_sweet_nectar"), "a quest can be given up")

## Hosts a game and has a second copy of the game (tests/bot_client.tscn) join it over
## the network: each must see the other, and the bot's attacks must count on the server.
func _check_multiplayer() -> void:
	_check(Net.host("Host", TEST_PORT) == "", "hosting opens port %d" % TEST_PORT)
	await _ticks(2)
	_check(world.started and Net.mode == Net.Mode.HOST, "the host plays in their own game")
	_me().inv = 100000
	DirAccess.remove_absolute(BotClient.RESULT_PATH)
	var bot := OS.create_process(OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/bot_client.tscn", "--", str(TEST_PORT)])
	_check(bot > 0, "a second game starts to join")
	var bot_peer := 0
	for i in 1200:
		await _ticks(1)
		for peer in Net.server.sessions:
			if peer != 1:
				bot_peer = peer
		if bot_peer != 0:
			break
	_check(bot_peer != 0, "the second game joins the host over the network")
	if bot_peer == 0:
		OS.kill(bot)
		return
	var bot_player: SimPlayer = Net.server.sessions[bot_peer]
	bot_player.inv = 100000
	# hold a Dewling in front of the bot until its attacks defeat one
	var meadow: MapInstance = Net.server.maps[&"meadow"]
	var level := bot_player.character.level
	var xp := bot_player.character.xp
	var seen_name := ""
	for i in 1200:
		await _ticks(1)
		if world.avatars.has(bot_peer):
			seen_name = world.avatars[bot_peer].char_name
		for m in meadow.mobs:
			if m.def.id == &"dewling" and m.plat == meadow.layout.platforms[0] and not m.dead:
				m.position.x = bot_player.position.x + 40
				break
		if bot_player.character.xp != xp or bot_player.character.level != level:
			break
	_check(bot_player.character.xp != xp or bot_player.character.level != level, "the joining player's attacks defeat a monster on the server")
	_check(seen_name == "Bot", "the host sees the other player, with their name")
	for i in 1200:
		await _ticks(1)
		if not OS.is_process_running(bot):
			break
	var f := FileAccess.open(BotClient.RESULT_PATH, FileAccess.READ)
	var result: Variant = JSON.parse_string(f.get_as_text()) if f else null
	_check(result is Dictionary and result.get("saw_host", false), "the other player sees the host %s" % [result])
	_check(result is Dictionary and result.get("saw_mobs", false) and result.get("saw_hits", false), "the other player sees the monsters and their own hits")
	for i in 120:
		await _ticks(1)
		if not Net.server.sessions.has(bot_peer):
			break
	_check(not Net.server.sessions.has(bot_peer) and not world.avatars.has(bot_peer), "when they quit, they leave the host's map")
	world.stop()
