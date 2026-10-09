extends Node
## Headless smoke test: godot --headless --path . res://tests/smoke_test.tscn
## Plays a short scripted session and checks the core loop works.

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
		if job.starting_stats == null or job.starting_gear.has(null):
			problems.append("job %s is missing starting stats or gear" % id)
	_check(problems.is_empty(), "maps, monsters, items and jobs reference valid content %s" % [problems])
	_check(Content.jobs.has(Game.START_JOB), "the starting job is defined")

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

func _first_filled(tab: int) -> int:
	for i in Inventory.SLOTS:
		if Game.inventory.at(tab, i) != null:
			return i
	return -1

## Inventory, equipment, stats and saving, without the world.
func _check_character() -> void:
	Game.new_character()
	var sword: EquipDef = Content.item(&"training_sword")
	_check(Game.equipment.at(&"weapon") != null and Game.equipment.at(&"weapon").item == sword, "a new character wears the starting sword")
	_check(Game.inventory.count_of(Content.item(&"red_potion")) == 5, "a new character carries 5 Red Potions")
	var dmg := Game.damage_range()
	_check(dmg.x > 0 and dmg.y >= dmg.x, "the damage range comes from stats and the weapon (%d ~ %d)" % [dmg.x, dmg.y])

	# stacking and a full tab
	var red: ItemDef = Content.item(&"red_potion")
	Game.inventory.add(red, 150)
	_check(Game.inventory.count_of(red) == 155 and Game.inventory.at(ItemDef.Tab.USE, 0).count == 100 and Game.inventory.at(ItemDef.Tab.USE, 1).count == 55, "potions stack up to 100 a slot")
	var tusk: ItemDef = Content.item(&"boar_tusk")
	var left := Game.inventory.add(tusk, 200 * Inventory.SLOTS + 7)
	_check(left == 7 and not Game.inventory.has_room(tusk), "a full Etc tab hands back what doesn't fit")
	Game.inventory.clear()

	# unequip and equip change stats
	var attack := Game.stats.attack
	_check(Game.unequip(&"weapon") == "" and Game.stats.attack == attack - sword.stats.attack, "taking off the sword lowers Weapon Attack")
	_check(Game.equip(_first_filled(ItemDef.Tab.EQUIP)) == "" and Game.stats.attack == attack, "putting it back on restores Weapon Attack")
	Game.inventory.add(Content.item(&"leaf_cap"))
	var defense := Game.stats.defense
	Game.equip(_first_filled(ItemDef.Tab.EQUIP))
	_check(Game.stats.defense > defense, "wearing a hat raises Weapon Defense")
	Game.inventory.add(Content.item(&"dawn_blade"))
	_check(Game.equip(_first_filled(ItemDef.Tab.EQUIP)) != "", "level 1 can't wear the level 8 Dawn Blade")

	# levels give Ability Points, and STR raises damage
	Game.gain_xp(Game.xp_need())
	_check(Game.level == 2 and Game.ap == Content.job(Game.START_JOB).ap_per_level, "levelling up gives Ability Points")
	var top := Game.damage_range().y
	for n in 5:
		Game.add_ap(&"strength")
	_check(Game.ap == 0 and Game.damage_range().y > top, "spending AP on STR raises damage")

	# saving and loading keeps the bag and the gear
	Game.inventory.add(tusk, 3)
	Game.save_game()
	var inv := JSON.stringify(Game.inventory.to_dict())
	var worn := JSON.stringify(Game.equipment.to_dict())
	var strength := Game.base.strength
	Game.new_character()
	Game.load_game()
	_check(JSON.stringify(Game.inventory.to_dict()) == inv and JSON.stringify(Game.equipment.to_dict()) == worn
		and Game.base.strength == strength, "saving and loading keeps inventory, equipment and stats")

func _run() -> void:
	_check_content()
	# Start from a fresh character without touching the real save file.
	Game.save_path = "user://smoke_test_save.json"
	_check_character()
	Game.new_character()
	var scene: PackedScene = load("res://scenes/main.tscn")
	world = scene.instantiate() as TDWorld
	add_child(world)
	await _ticks(5)
	world.start()
	var p := world.player
	p.inv = 100000 # keep monsters from knocking the player around mid-test
	_check(p.on_ground, "player starts on the ground")
	_check(world.npcs().size() == 2, "the meadow has its two NPCs")

	var x0 := p.position.x
	await _hold("move_right", 40)
	_check(p.position.x > x0 + 60, "walking right moves the player")

	await _tap("jump")
	await _ticks(10)
	_check(p.position.y < 620, "jumping leaves the ground")
	await _ticks(40)
	_check(p.on_ground, "player lands again")

	# Talk to the village elder.
	var elder := world.npcs()[0]
	p.position = Vector2(elder.position.x - 30, 620)
	await _ticks(2)
	await _tap("move_up")
	_check(elder.speech() != "", "pressing Up next to an NPC makes them talk")

	# Put a Dewling right in front of the player and hit it until it dies.
	var mob: TDMob = null
	for m in world.mobs():
		if m.def.id == &"dewling" and m.plat == world.platforms[0]:
			mob = m
			break
	p.position = Vector2(mob.position.x - 40, 620)
	p.face = 1
	var xp_before: int = Game.xp + Game.level * 1000
	var shards: int = Game.shards
	for i in 12:
		mob.position.x = p.position.x + 40
		await _tap("attack")
		await _ticks(24)
		if mob.dead:
			break
	_check(mob.dead, "basic attacks kill a Dewling")
	_check(Game.xp + Game.level * 1000 > xp_before, "killing a monster gives EXP")
	# Drops land next to the player, so some may already be picked up by now.
	_check(world.drop_layer.get_child_count() > 0 or Game.shards > shards, "the monster drops Dawnshards")
	await _ticks(80)
	for drop in world.drop_layer.get_children():
		if not is_instance_valid(drop) or not drop.item.is_currency:
			continue # picked up while walking to an earlier one
		p.position = Vector2(drop.position.x, 620)
		await _ticks(5)
	var currency_left := world.drop_layer.get_children().filter(func(d): return is_instance_valid(d) and not d.taken and d.item.is_currency)
	_check(Game.shards > shards and currency_left.is_empty(), "walking over Dawnshards picks them up")

	# Items wait for the loot key.
	for d in world.drop_layer.get_children():
		d.queue_free()
	await _ticks(1)
	var tusk: ItemDef = Content.item(&"boar_tusk")
	var boots: EquipDef = Content.item(&"leather_boots")
	for item in [tusk, boots]:
		var d := TDDrop.create(world, item, 1, p.position + Vector2(0, -20), 620)
		d.land_x = p.position.x
		world.drop_layer.add_child(d)
	await _ticks(40)
	_check(world.drop_layer.get_child_count() == 2, "items stay on the ground until looted")
	await _hold("loot", 24)
	_check(Game.inventory.count_of(tusk) == 1 and Game.inventory.count_of(boots) == 1, "the loot key picks up items and gear")

	# A Red Potion from the Use tab heals.
	Game.health.set_hp(10)
	var red: ItemDef = Content.item(&"red_potion")
	var potions := Game.inventory.count_of(red)
	_check(world.use_item(_first_filled(ItemDef.Tab.USE)) == ""
		and Game.health.hp > 10 and Game.inventory.count_of(red) == potions - 1, "drinking a Red Potion heals and uses it up")

	# The windows open with their keys and Esc closes them.
	for action in TDHud.WINDOW_ACTIONS:
		await _press(action)
	var all_open := true
	for action in TDHud.WINDOW_ACTIONS:
		all_open = all_open and world.hud.windows[action].visible
	_check(all_open, "I, E and S open the inventory, equipment and character windows")
	# Hovering gear in the bag shows its tooltip, compared with what's worn.
	var inv: TDInventoryWindow = world.hud.windows["inventory"]
	world.hud.title.hide() # the test started the world without pressing Play
	inv.tab = ItemDef.Tab.EQUIP
	Game.inventory.add(Content.item(&"leaf_cap"))
	var slot := _first_filled(ItemDef.Tab.EQUIP)
	var move := InputEventMouseMotion.new()
	move.position = get_viewport().get_final_transform() * (inv.global_position + inv.slot_rect(slot).get_center())
	move.global_position = move.position
	Input.parse_input_event(move)
	await _ticks(2)
	var tip := world.hud.tooltip
	var lines := tip._lines() if tip.stack else []
	_check(tip.stack == Game.inventory.at(ItemDef.Tab.EQUIP, slot) and lines.any(func(l): return str(l[0]).begins_with("vs. worn") or str(l[0]) == "Nothing worn in this slot"),
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

	# Dawn Slash costs MP and hits several monsters.
	var mp_before := Game.mp
	var level := Game.level
	p.cooldown = 0
	await _tap("skill")
	_check(p.action_anim == &"slash", "Dawn Slash plays its animation")
	# MP regen may tick once during the key press, and a kill that levels up refills MP.
	_check(Game.level > level or mp_before - Game.mp >= Content.skill(&"dawn_slash").mp_cost - 1, "Dawn Slash spends MP")

	# Climb the rope at x=700 up to the platform at y=420.
	await _ticks(40)
	p.position = Vector2(700, 620)
	p.vel = Vector2.ZERO
	await _ticks(2)
	await _hold("move_up", 100)
	_check(is_equal_approx(p.position.y, 420.0) and not p.is_climbing(), "climbing a rope reaches the platform above")

	# Walk through the portal to Ember Hollow.
	p.position = Vector2(2530, 620)
	await _ticks(3)
	await _tap("move_up")
	await _ticks(3)
	_check(world.map.id == &"hollow", "the portal leads to Ember Hollow")
	var boss := false
	for m in world.mobs():
		boss = boss or m.def.boss
	_check(boss, "Ember Hollow has its boss")

	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
