extends Node
## Headless smoke test: godot --headless --path . res://tests/smoke_test.tscn
## Plays a short scripted session and checks the core loop works.

## The first port the multiplayer check tries. Each run starts somewhere after it (by its
## process id) and moves on past ports in use, so smoke tests running side by side on one
## machine neither fail to host nor join each other's games.
const TEST_PORT := 7391
const TEST_PORTS := 400

var world: TDWorld
var failures := 0
## Test-only saves, one folder per run: every checkout of the project shares user://, and
## smoke tests may run side by side.
var save_dir := "user://smoke_test_characters_%d" % OS.get_process_id()
## Where the bot client writes what it saw.
var bot_result := "user://smoke_test_bot_%d.json" % OS.get_process_id()

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

## Waits until `cond` holds, for at most `max_ticks` physics ticks, and says whether it
## did. Things the server or the windows do a tick or a frame later are waited for this
## way instead of for a fixed number of ticks; the check that follows reports a timeout.
func _until(cond: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if cond.call():
			return true
		await _ticks(1)
	return cond.call()

## Takes everything off a map's ground, so drops left behind by an earlier part of the
## test can't be picked up by (or instead of) what a later part checks.
func _clear_drops(map: MapInstance) -> void:
	for d in map.drops.values():
		map._remove_drop(d, 0)

## Takes every other living monster on `map` out of play until _release_mobs, so none
## wanders into an attack meant for another or bumps the player. Returns them.
func _hold_mobs(map: MapInstance, keep: Array) -> Array[SimMob]:
	var held: Array[SimMob] = []
	for m in map.mobs:
		if not m.dead and m.parent == null and not keep.has(m):
			m.dead = true
			m.death_t = 0
			m.respawn = 1 << 30
			held.append(m)
	return held

## Brings monsters taken out by _hold_mobs back on the next tick, as if they respawned.
func _release_mobs(held: Array[SimMob]) -> void:
	for m in held:
		m.respawn = 1

func _check_content() -> void:
	_check(Content.monsters.size() >= 9, "monster definitions load (%d)" % Content.monsters.size())
	_check(Content.maps.has(&"meadow") and Content.maps.has(&"hollow"), "the starting maps load")
	var towns := Content.maps.values().filter(func(m: MapDef) -> bool: return m.town)
	_check(towns.size() >= 7, "there are hub towns (%d)" % towns.size())
	# instructors teach in their halls, rooms inside the towns
	var town_and_rooms := Content.maps.values().filter(func(m: MapDef) -> bool: return m.town or m.interior)
	for id in [&"warrior", &"archer", &"mage", &"thief", &"pirate"]:
		var teaches := false
		for m in town_and_rooms:
			for n in m.npcs:
				teaches = teaches or id in n.npc.instructs
		_check(teaches, "some town's instructor teaches %s" % id)
	_check(Content.skill(Character.BASIC_ATTACK) != null and Content.skill(Character.BASIC_ATTACK).innate, "the basic attack is an innate skill")
	var problems := []
	for id in Content.skills:
		var sk: SkillDef = Content.skills[id]
		if sk.icon == null:
			problems.append("skill %s has no icon" % id)
		if not sk.innate and not Content.jobs.has(sk.job):
			problems.append("skill %s belongs to unknown job %s" % [id, sk.job])
		if sk.requires != &"" and not Content.skills.has(sk.requires):
			problems.append("skill %s requires unknown skill %s" % [id, sk.requires])
		if sk.kind == SkillDef.Kind.BUFF and sk.duration <= 0:
			problems.append("buff %s has no duration" % id)
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
		if map.region != &"" and not Content.regions.has(map.region):
			problems.append("%s: unknown region %s" % [id, map.region])
		if not Content.maps.has(map.return_town()):
			problems.append("%s: returns to unknown map %s" % [id, map.return_town()])
		for n in map.npcs:
			for route in (n.npc.travel if n.npc else []):
				if not Content.maps.has(route.target_map):
					problems.append("%s: %s travels to unknown map %s" % [id, n.npc.id, route.target_map])
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
	_check_world_graph()

## Every portal leads somewhere with a portal back, every map can be reached from the
## meadow, and every item a quest asks for can be found.
## Every job can fight monsters of its level, and levels take a sensible number of kills
## (see Balance and tests/balance_report.tscn).
func _check_balance() -> void:
	var worst := ""
	var slow := ""
	for m: MonsterDef in Content.monsters.values():
		if m.boss:
			continue
		for j in Balance.LINES:
			var hits := Balance.hits_to_kill(Balance.typical(j, m.level), m)
			if hits < Balance.BAND.x - 0.2 or hits > Balance.BAND.y:
				worst += " %s/%s %.1f" % [j, m.id, hits]
		var kills := Balance.kills_per_level(m.level, m)
		if kills > 1000.0:
			slow += " %s %.0f" % [m.id, kills]
	_check(worst == "", "every job beats monsters of its level in a few hits%s" % worst)
	_check(slow == "", "no monster takes too many kills a level%s" % slow)
	var c := Character.new()
	_check(c.xp_need(1) < 100 and c.xp_need(30) > c.xp_need(20) * 2, "early levels are quick and later ones take longer")
	var steam_ids := {}
	for a in Achievements.LIST:
		steam_ids[a["steam"]] = true
	_check(steam_ids.size() == Achievements.LIST.size() and not steam_ids.has(""), "every achievement has its own Steam id")

func _check_world_graph() -> void:
	var problems := []
	for id in Content.maps:
		var m: MapDef = Content.maps[id]
		for p in m.portals:
			var there: MapDef = Content.maps.get(p.target_map)
			if there == null:
				problems.append("%s portal to missing %s" % [id, p.target_map])
			elif not there.portals.any(func(b: PortalDef) -> bool: return b.target_map == id):
				problems.append("%s -> %s has no way back" % [id, p.target_map])
			elif p.target_x < 0 or p.target_x > there.width or there.portals.any(func(b: PortalDef) -> bool: return absf(b.x - p.target_x) < 34):
				problems.append("%s -> %s lands on a portal or off the map" % [id, p.target_map])
			if p.platform >= m.platforms.size() + 1:
				problems.append("%s portal on a missing platform" % id)
		for s in m.spawns:
			if s.platform > m.platforms.size():
				problems.append("%s spawns on a missing platform" % id)
		if not m.town and m.return_town() == id:
			problems.append("%s has no town" % id)
	# walk the portals and travel routes from the meadow
	var seen := {&"meadow": true}
	var todo: Array[StringName] = [&"meadow"]
	while not todo.is_empty():
		var id: StringName = todo.pop_back()
		var nexts: Array[StringName] = Content.maps[id].neighbours()
		for n in Content.maps[id].npcs:
			for r in n.npc.travel:
				nexts.append(r.target_map)
		for n in nexts:
			if Content.maps.has(n) and not seen.has(n):
				seen[n] = true
				todo.append(n)
	for id in Content.maps:
		if not seen.has(id):
			problems.append("%s can't be reached" % id)
	_check(Content.maps.size() >= 40 and problems.is_empty(), "%d maps joined by portals both ways, all reachable %s" % [Content.maps.size(), problems])
	var dropped := {}
	for id in Content.monsters:
		for d in Content.monsters[id].drops:
			dropped[d.item.id] = true
	var missing := []
	for id in Content.quests:
		for o in Content.quests[id].objectives:
			if o.kind == QuestObjective.Kind.COLLECT and not dropped.has(o.item.id) and o.drop_from == null:
				missing.append(o.item.id)
	_check(missing.is_empty(), "every item a quest asks for drops somewhere %s" % [missing])
	var bosses := Content.monsters.values().filter(func(m: MonsterDef) -> bool: return m.boss)
	var shooters := Content.monsters.values().filter(func(m: MonsterDef) -> bool: return m.shot != null)
	var splitters := Content.monsters.values().filter(func(m: MonsterDef) -> bool: return m.splits_into != null)
	_check(Content.monsters.size() >= 50 and bosses.size() >= 6 and shooters.size() >= 10 and splitters.size() >= 4,
		"%d monsters, with bosses, shooters and splitters" % Content.monsters.size())
	var scrolls := Content.items.values().filter(func(i: ItemDef) -> bool: return i is ScrollDef)
	_check(Content.items.size() >= 200 and scrolls.size() >= 12 and scrolls.all(func(s: ScrollDef) -> bool: return not s.slots.is_empty() and s.stats != null),
		"%d items, with upgrade scrolls for each kind of gear" % Content.items.size())

func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await _ticks(1)
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	Input.flush_buffered_events()
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
	var store := CharacterStore.new(save_dir)
	store.save(c)
	var back := store.load_character("Tester")
	_check(back != null and JSON.stringify(back.inventory.to_dict()) == JSON.stringify(c.inventory.to_dict())
		and JSON.stringify(back.equipment.to_dict()) == JSON.stringify(c.equipment.to_dict())
		and back.base.strength == c.base.strength and back.level == 2, "saving and loading keeps inventory, equipment and stats")
	_check(CharacterStore.clean_name("  Dawn<ling>!  ") == "Dawnling", "character names are cleaned up")
	_check_jobs()
	_check_skill_rules()

## Skill Points, Beginner skills, buffs and save files, without the world.
func _check_skill_rules() -> void:
	var c := Character.create("Skiller")
	_check(c.sp == 0 and c.skill_level(Content.skill(Character.BASIC_ATTACK)) == 1, "a new character knows only the basic attack")
	c.gain_xp(c.xp_need())
	_check(c.sp == 1, "a Beginner gets 1 Skill Point a level")
	var step: SkillDef = Content.skill(&"quick_step")
	_check(c.learn(step) == "" and c.skill_level(step) == 1 and c.sp == 0, "a Beginner learns Quick Step")
	_check(c.learn(step) != "", "no Skill Points, no more levels")
	_check(c.learn(Content.skill(&"power_strike")) != "", "a Beginner can't learn Warrior skills")
	var speed := c.stats.speed
	c.mp = 100
	c.add_buff(step)
	_check(c.stats.speed > speed, "Quick Step makes you faster")
	c.tick_buffs(step.duration_ticks(1))
	_check(c.buffs.is_empty() and c.stats.speed == speed, "and wears off after its time")
	c.sp = 3
	var wind: SkillDef = Content.skill(&"second_wind")
	c.learn(wind)
	_check(c.regen_bonus().x == wind.regen_hp, "Second Wind adds HP recovery")
	var back := Character.new()
	back.load_dict(c.to_dict())
	_check(back.skills == c.skills and back.sp == c.sp and back.quickslots == c.quickslots, "skills, Skill Points and quickslots save")
	var old := c.to_dict()
	old.erase("sp")
	old.erase("skills")
	old.erase("quickslots")
	old["level"] = 12
	old["job"] = "warrior"
	var legacy := Character.new()
	legacy.load_dict(old)
	_check(legacy.sp == 11 * 3 and legacy.quickslots[Character.QUICKSLOTS - 2] == [&"item", &"red_potion"], "older saves get Skill Points for their levels")

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
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))

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
	seed(12345) # monsters wander, drops and hits roll: the same way every run
	_check_content()
	_check_balance()
	_clear_saves()
	_check_character()
	# Play single player against a server inside this game, with test-only saves.
	_clear_saves()
	Net.save_dir = save_dir
	world = load("res://scenes/world.tscn").instantiate() as TDWorld
	add_child(world)
	await _ticks(5)
	_check(not world.started and world.hud.title.visible, "the game opens on the title screen")
	world.hud._on_play()
	await _ticks(2)
	var select := world.hud.character_select
	_check(select.visible and not world.hud.title_card.visible and Net.characters.is_empty(), "Play solo opens an empty character select")
	select.create_button.pressed.emit()
	var creator := world.hud.creator
	_check(creator.visible and not select.visible and not world.started, "Create opens the character creator")
	creator.name_field.text = "Tester"
	creator.step("look:%d" % LookDef.Kind.HAIR, 1)
	creator.step("look:%d" % LookDef.Kind.HAIR_COLOR, 2)
	creator.step("outfit:%d" % EquipDef.Slot.TOP, 1)
	var chosen := creator.made.appearance.to_dict()
	var top: EquipDef = creator.made.outfit[EquipDef.Slot.TOP]
	_check(creator.preview.look["appearance"] == chosen and creator.preview.look["gear"]["top"] == String(top.id), "the preview shows every choice")
	creator.create_button.pressed.emit()
	await _ticks(2)
	_check(select.visible and select.selected == "Tester" and not world.started, "Create goes back to character select with the new character picked")
	select.play_button.pressed.emit()
	await _ticks(2)
	_me().inv = 100000 # keep monsters from hurting the player mid-test
	_check(world.started and not world.hud.title.visible and Game.me.name == "Tester", "Play starts a single-player game as the named character")
	_check(Game.me.appearance.to_dict() == chosen and Game.me.equipment.at(&"top").item == top, "the character has the look and outfit picked")
	_check(Game.me.job.id == Character.START_JOB, "a new character starts as a Beginner")
	_check(world.player.rig.paperdoll.look == Game.me.look(), "the hero is drawn with that look")
	_check(Net.server != null and _me() != null, "single player runs its own server")
	var p := world.player
	_check(p.on_ground, "player starts on the ground")
	_check(world.npcs().size() == 4, "the meadow has its four NPCs (Mira keeps shop indoors)")
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

	# Mira's shop is a room inside her house: walk in through its door.
	var door: PortalDef = Content.map(&"meadow").portals.filter(func(d: PortalDef) -> bool: return d.target_map == &"meadow_store")[0]
	_check(door.door and Content.map(&"meadow").buildings.any(func(b: BuildingPlacement) -> bool: return b.x == door.x),
		"the shop's door is a doorway in a building")
	_teleport(Vector2(door.x, 620))
	await _ticks(2)
	await _tap("move_up")
	await _ticks(4)
	_check(world.map.id == &"meadow_store" and world.map.interior, "pressing Up in the doorway walks into the shop")
	_check(world.map.outside() == &"meadow", "the shop is inside the meadow village")
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
	await _ticks(4)
	_check(world.map.id == &"meadow" and absf(world.player.position.x - door.x) < 120, "the room's door leads back out beside the shop")

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
	var xp_before: int = Game.me.xp + Game.me.level * 1000
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
	world.hud.toggle_window("worldmap") # it covers the others
	# Hovering gear in the bag shows its tooltip, compared with what's worn.
	var inv: TDInventoryWindow = world.hud.windows["inventory"]
	inv.tab = ItemDef.Tab.EQUIP
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

	await _check_quests()
	await _check_job_advance()

	await _check_skills()
	await _check_ranged()
	await _check_travel()
	await _check_fields()
	await _check_social()
	await _check_keepsakes()
	_me().inv = 100000 # a monster's touch would knock the player off the rope or the portal

	# Dawn Slash costs MP and hits several monsters.
	var mp_before := Game.me.mp
	var level := Game.me.level
	p.cooldown = 0
	_me().cooldown = 0
	await _tap("quick_2")
	_check(p.action_anim == WeaponStyle.animation_for(Game.me.look(), &"slash"), "Dawn Slash plays its motion for the weapon in hand")
	# MP regen may tick once during the key press, and a kill that levels up refills MP.
	_check(Game.me.level > level or mp_before - Game.me.mp >= Content.skill(&"dawn_slash").mp_at(1) - 1, "Dawn Slash spends MP")

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
	await _until(func() -> bool: return world.map.id == &"hollow", 30)
	_check(world.map.id == &"hollow" and _me().map.def.id == &"hollow", "the portal leads to Ember Hollow")
	var boss := false
	for m in world.mobs():
		boss = boss or m.def.boss
	_check(boss, "Ember Hollow has its boss")

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

	world.hud.show_title(true)
	world.hud.game_menu.characters_button.pressed.emit()
	await _ticks(2)
	_check(world.hud.character_select.visible and not world.started and Net.mode == Net.Mode.SINGLE, "Character select in the menu leaves the world but stays logged in")
	world.hud.character_select.logout_button.pressed.emit()
	_check(Net.mode == Net.Mode.NONE and world.hud.title_card.visible, "Log out goes back to the title screen")
	_check(CharacterStore.new(save_dir).load_character("Tester") != null, "leaving saves the character")

	await _check_multiplayer()

	_clear_saves()
	DirAccess.remove_absolute(save_dir)
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

## Archmage Celest in Lumewood turns a ready Beginner into a Magician through the dialogue
## window.
func _check_job_advance() -> void:
	var ch := _me().character
	Net.server._enter_map(_me(), &"lumewood", 300)
	await _ticks(3)
	_check(world.map.id == &"lumewood" and world.map.town, "Lumewood is a town")
	Net.server._enter_map(_me(), &"lumewood_hall", 240)
	await _ticks(3)
	_check(world.map.outside() == &"lumewood", "the Magicians' Library is a room in Lumewood")
	var guide: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"lumewood_instructor")[0]
	ch.job = Content.job(&"beginner")
	ch.level = maxi(ch.level, 10)
	ch.base.intelligence = 20
	_me().dirty_character = true
	await _ticks(2)
	_teleport(Vector2(guide.position.x - 30, guide.position.y))
	await _ticks(2)
	await _tap("move_up")
	var talk: TDDialogueWindow = world.hud.windows["dialogue"]
	var labels: Array = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels.has("Choose a job"), "the job instructor offers to choose a job")
	talk.choose(labels.find("Choose a job"))
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels == ["Magician", "Back"], "Lumewood's instructor teaches Magicians")
	talk.choose(labels.find("Magician"))
	_check(talk.options[0][0] == "Become a Magician", "a level 10 Beginner with 20 INT may become a Magician")
	talk.choose(0)
	await _ticks(2)
	_check(Game.me.job.id == &"mage" and Game.me.inventory.count_of(Content.item(&"apprentice_wand")) == 1, "the server makes them a Magician and gives a wand")
	Net.ask(&"req_equip", [Game.me.inventory.find(Content.item(&"apprentice_wand")), &"weapon"])
	await _ticks(2)
	_check(world.player.rig.paperdoll.look["gear"].get("weapon") == "apprentice_wand", "the hero is drawn holding the wand once it's worn")
	Net.server._enter_map(_me(), &"meadow", 300)
	await _ticks(3)

## A Warrior with Skill Points learns skills in the skill window: they land on quickslots,
## a buff raises stats until it runs out, and a passive is always on.
func _check_skills() -> void:
	var ch := _me().character
	ch.job = Content.job(&"warrior")
	ch.sp = 5
	ch.skills.clear()
	ch.quickslots.fill([])
	_me().dirty_character = true
	await _ticks(2)
	var book: TDSkillWindow = world.hud.windows["skills"]
	await _press("skills")
	_check(book.visible and book.jobs() == [&"beginner", &"warrior"], "K opens the skill book with Beginner and Warrior tabs")
	book.tab = 1
	var slash: SkillDef = Content.skill(&"dawn_slash")
	book.learn(slash)
	await _ticks(1)
	_check(Game.me.skill_level(slash) == 0 and Game.me.sp == 5, "Dawn Slash needs Power Strike first")
	book.learn(Content.skill(&"power_strike"))
	book.learn(slash)
	book.learn(Content.skill(&"iron_body"))
	book.learn(Content.skill(&"toughness"))
	await _ticks(1)
	_check(Game.me.skill_level(slash) == 1 and Game.me.sp == 1, "spending Skill Points learns skills")
	_check(Game.me.quickslots[0] == [&"skill", &"power_strike"] and Game.me.quickslots[1] == [&"skill", &"dawn_slash"]
		and Game.me.quickslots[2] == [&"skill", &"iron_body"], "learned skills go on the free quickslots")
	_check(Game.me.max_hp() == Game.me.job.base_hp + Game.me.level * Game.me.job.hp_per_level + Game.me.equipment.bonus().max_hp + 15, "Toughness raises Max HP")
	await _press("skills")
	# Iron Body raises defense until it wears off.
	var defense := Game.me.stats.defense
	ch.mp = ch.max_mp()
	world.player.cooldown = 0
	_me().cooldown = 0
	await _tap("quick_3")
	await _ticks(1)
	_check(Game.me.buffs.has(&"iron_body") and Game.me.stats.defense == defense + 5, "Iron Body raises Weapon Defense")
	ch.buffs[&"iron_body"][1] = 2
	await _ticks(4)
	_check(not Game.me.buffs.has(&"iron_body") and Game.me.stats.defense == defense, "it wears off")
	# Quickslots can be rearranged from the client, and the server keeps them.
	world.hud.quickslots.assign(5, &"skill", &"dawn_slash")
	await _ticks(1)
	_check(ch.quickslots[5] == [&"skill", &"dawn_slash"] and ch.quickslots[1] == [], "moving a skill to another quickslot")
	world.hud.quickslots.assign(1, &"skill", &"dawn_slash")
	# A Red Potion on a quickslot is drunk with its key.
	world.hud.quickslots.assign(7, &"item", &"red_potion")
	ch.health.set_hp(10)
	await _ticks(2)
	_me().item_cd = 0
	await _tap("quick_8")
	await _ticks(1)
	_check(Game.me.health.hp > 10, "a potion's quickslot key drinks it")
	world.player.cooldown = 0
	_me().cooldown = 0
	await _ticks(30)

## An Archer's bow shoots arrows that fly to the monster, a Magician's Energy Bolt uses
## magic, and a claw with no stars can't throw.
func _check_ranged() -> void:
	var ch := _me().character
	var meadow: MapInstance = Net.server.maps[&"meadow"]
	var sword := ch.equipment.take(&"weapon")
	ch.job = Content.job(&"archer")
	ch.equipment.put(&"weapon", ItemStack.exact(Content.item(&"willow_bow")))
	var arrows: ItemDef = Content.item(&"feather_arrow")
	ch.inventory.add(arrows, 50)
	ch.recalc()
	_me().dirty_character = true
	_teleport(Vector2(1380, 620))
	var m: SimMob = meadow.mobs.filter(func(x: SimMob) -> bool: return x.plat == meadow.layout.platforms[0] and not x.dead)[0]
	# only this monster may be in the arrow's way
	var others := _hold_mobs(meadow, [m])
	m.position.x = 1380 + 200
	world.player.face = 1
	_me().face = 1
	world.player.cooldown = 0
	_me().cooldown = 0
	await _ticks(3)
	_check(Game.me.basic_attack().id == &"bow_shot", "a bow turns the attack key into a shot")
	var hp := m.health.hp
	m.position.x = 1380 + 200
	m.walk_t = 1000
	m.dir = 0
	# the game's view of it has to have glided over too, or the arrow lands at once
	var view: TDMob = world.mobs()[m.index]
	await _until(func() -> bool: return absf(view.position.x - m.position.x) < 4.0, 120)
	var flying := []
	var spotted := func(c: Node) -> void:
		if c is TDProjectile:
			flying.append(c)
	world.fx_layer.child_entered_tree.connect(spotted)
	await _tap("attack")
	world.fx_layer.child_entered_tree.disconnect(spotted)
	_check(not flying.is_empty(), "the arrow flies")
	await _until(func() -> bool: return m.health.hp < hp or m.dead, 20)
	_check(m.health.hp < hp or m.dead, "it hits a monster 200 pixels away")
	_release_mobs(others)
	_check(Game.me.inventory.count_of(arrows) == 49, "and uses one arrow")
	# no arrows, no shot
	ch.inventory.remove(arrows, 49)
	_me().cooldown = 0
	world.player.cooldown = 0
	_me().dirty_character = true
	await _ticks(2)
	_check(Game.me.use_problem(Game.me.basic_attack()).contains("out of arrows"), "without arrows the bow can't shoot")
	# a Magician's spell uses Magic Attack
	ch.job = Content.job(&"mage")
	ch.equipment.take(&"weapon")
	ch.equipment.put(&"weapon", ItemStack.exact(Content.item(&"apprentice_wand")))
	ch.base.intelligence = 60
	ch.skills[&"energy_bolt"] = 1
	ch.recalc()
	var bolt: SkillDef = Content.skill(&"energy_bolt")
	var magic := ch.magic_range()
	_check(magic.y > ch.damage_range().y, "a Magician's spells hit harder than their wand")
	var hit := Combat.player_hit(bolt, m.def, ch)
	_check(hit["miss"] or (hit["damage"] >= 1 and hit["damage"] <= roundi(magic.y * 1.6) + 1), "Energy Bolt's damage comes from Magic Attack")
	# a claw needs stars
	ch.job = Content.job(&"thief")
	ch.equipment.take(&"weapon")
	ch.equipment.put(&"weapon", ItemStack.exact(Content.item(&"iron_claw")))
	ch.skills[&"lucky_seven"] = 1
	_check(ch.use_problem(Content.skill(&"lucky_seven")).contains("out of stars"), "Lucky Seven needs throwing stars")
	ch.inventory.add(Content.item(&"iron_star"), 10)
	_check(ch.use_problem(Content.skill(&"lucky_seven")) == "" and ch.ammo_attack() == 15, "with stars it's ready, and stars add attack")
	ch.skills[&"flash_fist"] = 1
	_check(ch.use_problem(Content.skill(&"flash_fist")).contains("needs a knuckle"), "Flash Fist needs a knuckle")
	# back to a Warrior with a sword for the rest of the test
	ch.job = Content.job(&"warrior")
	ch.equipment.take(&"weapon")
	ch.equipment.put(&"weapon", sword)
	ch.recalc()
	_me().dirty_character = true
	await _ticks(2)

## The world map, Hobb's wagon, return scrolls, and waking up in the right town.
func _check_travel() -> void:
	var ch := _me().character
	await _press("worldmap")
	var wm: TDWorldMapWindow = world.hud.windows["worldmap"]
	_check(wm.visible and TDWorldMapWindow.placed().size() >= 2, "W opens the world map with the maps on it")
	wm._hovered(wm.to_screen(Content.map(&"hollow").world_pos))
	_check(wm.hovered == &"hollow", "hovering a dot picks that map")
	await _press("worldmap")
	# Hobb's wagon to Ember Hollow costs 150 Dawnshards.
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
	_check(str(talk.options[0][0]).begins_with("Wagon to Ember Hollow"), "the trip lists where it goes and the fare")
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
	_check(world.map.id == &"meadow" and Game.me.inventory.count_of(scroll) == 1, "a Return Scroll takes you back to town")
	_me().item_cd = 0
	world.hud.windows["inventory"].use_slot(Game.me.inventory.find(scroll))
	await _ticks(2)
	_check(Game.me.inventory.count_of(scroll) == 1, "it isn't used up when you're already in town")
	_check(Content.map(&"hollow").return_town() == &"meadow" and Content.map(&"meadow").return_town() == &"meadow", "maps know their town")
	# Captain Marlo's ship to Dawnharbor, then Brin's storage, then Rook's coach.
	var marlo: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"captain_marlo")[0]
	_teleport(Vector2(marlo.position.x - 30, 620))
	await _ticks(2)
	await _tap("move_up")
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	talk.choose(labels.find("Travel"))
	talk.choose(0)
	await _ticks(3)
	_check(world.map.id == &"dawnharbor", "Captain Marlo sails to Dawnharbor")
	var brin: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"storage_keeper")[0]
	_teleport(Vector2(brin.position.x - 30, 620))
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
	_teleport(Vector2(rook.position.x - 30, 620))
	await _ticks(2)
	await _tap("move_up")
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	talk.choose(labels.find("Travel"))
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels.size() == 6, "Rook's coach goes to all five job towns")
	talk.choose(0)
	await _ticks(3)
	_check(world.map.id == &"greenbough", "the coach takes you to Greenbough")
	Net.server._enter_map(_me(), &"meadow", 300)
	await _ticks(3)

## The new field maps: walking west out of the meadow, monsters that split, hop and shoot,
## and upgrade scrolls.
func _check_fields() -> void:
	var ch := _me().character
	# a monster bumping you off the portal would make this flaky
	_me().inv = 100000
	var west: PortalDef = Content.map(&"meadow").portals.filter(func(p: PortalDef) -> bool: return p.target_map == &"sunny_slope")[0]
	_teleport(Vector2(west.x, 620))
	await _ticks(2)
	await _tap("move_up")
	await _ticks(4)
	_check(world.map.id == &"sunny_slope", "the meadow's west portal leads to Sunny Slope")
	_me().inv = 0
	# a Sporecap splits into Spore Puffs when it's defeated
	Net.server._enter_map(_me(), &"mushroom_dell", 300)
	await _ticks(3)
	var dell: MapInstance = Net.server.maps[&"mushroom_dell"]
	var cap: SimMob = dell.mobs.filter(func(m: SimMob) -> bool: return m.def.id == &"sporecap")[0]
	_check(cap.children.size() == 2 and cap.children.all(func(c: SimMob) -> bool: return c.dead and c.asleep), "a Sporecap's Spore Puffs wait asleep")
	_check(world.mobs().size() == dell.mobs.size(), "the client numbers split-off monsters the same way")
	dell.kill_mob(cap, _me())
	await _ticks(3)
	_check(cap.children.all(func(c: SimMob) -> bool: return not c.dead), "defeating a Sporecap releases its Spore Puffs")
	_check(not world.mobs()[cap.children[0].index].dead, "and the client sees them")
	for c in cap.children:
		dell.kill_mob(c, _me())
	await _ticks(60)
	_check(cap.children.all(func(c: SimMob) -> bool: return c.dead and c.asleep), "defeated Spore Puffs go back to sleep instead of respawning")
	# hoppers hop
	Net.server._enter_map(_me(), &"sunny_slope", 300)
	await _ticks(3)
	var slope: MapInstance = Net.server.maps[&"sunny_slope"]
	var hopper: SimMob = slope.mobs.filter(func(m: SimMob) -> bool: return m.def.jumps and not m.dead)[0]
	var hopped := false
	# a hop starts at random (1 in 80 a tick): give it plenty of ticks
	for i in 4000:
		hopper.step()
		hopped = hopped or hopper.hop > 0.0
		if hopped:
			break
	_check(hopped and hopper.body_position().y <= hopper.plat.y, "a Tide Dewling hops")
	# an Acorn Sentry never moves and shoots anyone near it; the shot lands where they stood
	Net.server._enter_map(_me(), &"thornwood", 300)
	await _ticks(3)
	var wood: MapInstance = Net.server.maps[&"thornwood"]
	var sentry: SimMob = wood.mobs.filter(func(m: SimMob) -> bool: return m.def.id == &"acorn_sentry" and not m.dead)[0]
	var x0 := sentry.position.x
	# only the sentry: another monster's touch would also leave the player blinking
	var others := _hold_mobs(wood, [sentry])
	_teleport(Vector2(sentry.position.x + 150, sentry.plat.y))
	ch.health.reset(ch.max_hp())
	var hp: int = ch.health.hp
	sentry.shot_t = 1
	var shots := 0
	var landed := false
	for i in 400:
		await _ticks(1)
		_me().position = Vector2(x0 + 150, sentry.plat.y)
		world.player.position = _me().position
		shots += world.fx_layer.get_children().filter(func(n: Node) -> bool: return n is TDProjectile).size()
		# a hit costs HP; a dodge still leaves the player blinking
		landed = ch.health.hp < hp or _me().inv > 0
		if landed:
			break
	_check(shots > 0, "the client sees the sentry's shot fly")
	_check(landed, "the shot hits a player who stays put")
	_check(sentry.position.x == x0, "the sentry never moves")
	_release_mobs(others)
	_me().inv = 100000
	# upgrade scrolls: always spend a slot, add their stats when they work
	var sword: EquipDef = Content.item(&"bronze_sword")
	var good: ScrollDef = Content.item(&"scroll_weapon_att_60")
	ch.inventory.add(sword, 1)
	ch.inventory.add(good, 2)
	ch.inventory.add(Content.item(&"scroll_helmet_hp_60"), 1)
	var e := ch.inventory.find(sword)
	var stack := ch.inventory.at(ItemDef.Tab.EQUIP, e)
	var att := stack.stats.attack
	_check(ch.scroll_problem(ch.inventory.find(Content.item(&"scroll_helmet_hp_60")), e) != "", "a helmet scroll doesn't work on a sword")
	var r := ch.use_scroll(ch.inventory.find(good), e, 0.0)
	_check(r["worked"] and stack.stats.attack == att + 2 and stack.slots_used == 1 and stack.upgrades == 1 and stack.display_name().ends_with("+1"),
		"a scroll that works adds its stats and spends a slot")
	r = ch.use_scroll(ch.inventory.find(good), e, 0.99)
	_check(not r["worked"] and stack.stats.attack == att + 2 and stack.slots_used == 2 and stack.slots_left() == sword.upgrade_slots - 2,
		"a scroll that fails still spends a slot")
	var saved := ItemStack.from_dict(stack.to_dict())
	_check(saved.slots_used == 2 and saved.upgrades == 1 and saved.stats.attack == att + 2, "upgrades are saved with the gear")
	# and through the bag window
	ch.inventory.add(good, 1)
	_me().dirty_character = true
	await _ticks(2)
	var bag: TDInventoryWindow = world.hud.windows["inventory"]
	bag.tab = ItemDef.Tab.USE
	bag.use_slot(Game.me.inventory.find(good))
	_check(bag.scrolling >= 0 and bag.tab == ItemDef.Tab.EQUIP, "double-clicking a scroll picks it up and shows the gear")
	bag.use_scroll_on(Game.me.inventory.find(sword))
	await _ticks(3)
	_check(Game.me.inventory.count_of(good) == 0 and Game.me.inventory.at(ItemDef.Tab.EQUIP, Game.me.inventory.find(sword)).slots_used == 3,
		"clicking the gear uses the scroll on it")
	Net.server._enter_map(_me(), &"meadow", 300)
	await _ticks(3)

## Chat, parties, buddies, trading, guilds, fame and player shops, with a second
## character played straight on the server (it has no game of its own).
func _check_social() -> void:
	var social := Net.server.social
	var ch := _me().character
	var ally := SimPlayer.new(4242, Character.create("Ally"))
	Net.server.sessions[ally.peer] = ally
	social.joined(ally)
	Net.server._enter_map(_me(), &"meadow", 400)
	Net.server._enter_map(ally, &"meadow", 470)
	await _ticks(5)
	_check(world.avatars.has(ally.peer) and world.avatars[ally.peer].char_name == "Ally", "the other character shows up on the map")
	# chat
	Net.ask(&"req_chat", ["Hello, meadow!"])
	await _ticks(2)
	var chat := world.hud.chat
	_check(chat.lines.size() > 0 and str(chat.lines[-1]["text"]).ends_with("Hello, meadow!") and world.player.speech_t > 0, "map chat shows in the box and over your head")
	Net.ask(&"req_chat", ["/w Ally psst"])
	await _ticks(2)
	_check(str(chat.lines[-1]["text"]) == "To Ally: psst", "/w whispers to someone")
	chat.open()
	_check(world.input_blocked(), "typing in chat stops the player moving")
	chat.close()
	# the player menu
	world.click_avatar(world.avatars[ally.peer])
	var menu: TDPlayerMenuWindow = world.hud.windows["player"]
	var labels: Array = menu.actions().map(func(a: Array) -> String: return a[0])
	_check(menu.visible and labels.has("Invite to party") and labels.has("Trade") and labels.has("Add buddy"), "clicking a player opens what you can do with them")
	menu.visible = false
	# a party, shared EXP
	Net.ask(&"req_social", [&"party", "Ally"])
	await _ticks(1)
	var id: int = social.invites.keys().filter(func(k: int) -> bool: return social.invites[k]["to"] == ally.peer)[0]
	social.on_answer(ally.peer, id, true)
	await _ticks(35)
	var party: Dictionary = Game.social.get("party", {})
	_check(party.get("leader") == ch.name and party.get("members", []).size() == 2, "a party forms when the invite is accepted")
	var xp := ally.character.xp
	var mob: SimMob = _me().map.mobs.filter(func(m: SimMob) -> bool: return not m.dead)[0]
	_me().map.kill_mob(mob, _me())
	_check(ally.character.xp > xp or ally.character.level > 1, "party members on the map share the EXP")
	Net.ask(&"req_chat", ["/p go team"])
	await _ticks(2)
	_check(str(chat.lines[-1]["text"]) == "[Party] %s: go team" % ch.name, "/p talks to the party")
	# buddies
	social.invite(ally, "buddy", ch.name)
	await _ticks(2)
	_check(world.hud.invites.visible and world.hud.invites.pending[0][1] == "buddy", "an invitation card pops up")
	world.hud.invites.answer(true)
	await _ticks(35)
	_check(ch.buddies.has("Ally") and ally.character.buddies.has(ch.name), "accepting makes you buddies both ways")
	var buddies: Array = Game.social.get("buddies", [])
	_check(buddies.size() == 1 and buddies[0][1], "the buddy list shows them online")
	# trading: an item for Dawnshards
	ch.inventory.remove(Content.item(&"moss_tuft"), 1000)
	ch.inventory.add(Content.item(&"moss_tuft"), 5)
	ally.character.shards = 1000
	_me().dirty_character = true
	await _ticks(2)
	var shards := ch.shards
	social.invite(ally, "trade", ch.name)
	await _ticks(2)
	world.hud.invites.answer(true)
	await _ticks(2)
	var trade: TDTradeWindow = world.hud.windows["trade"]
	_check(trade.visible and trade.state.get("partner") == "Ally", "accepting a trade opens the trade window")
	trade.offer(ItemDef.Tab.ETC, Game.me.inventory.find(Content.item(&"moss_tuft")))
	social.on_trade_shards(ally.peer, 300)
	await _ticks(2)
	_check(Game.me.inventory.count_of(Content.item(&"moss_tuft")) == 0 and trade.state["theirs"]["shards"] == 300, "both offers show in the window")
	Net.ask(&"req_trade_ready")
	await _ticks(1)
	_check(not trade.state.is_empty(), "nothing changes hands until both press Trade")
	social.on_trade_ready(ally.peer)
	await _ticks(3)
	_check(not trade.visible and ch.shards == shards + 300 and ally.character.inventory.count_of(Content.item(&"moss_tuft")) == 5, "then the items and Dawnshards swap")
	# a cancelled trade gives everything back
	social.invite(ally, "trade", ch.name)
	await _ticks(2)
	world.hud.invites.answer(true)
	await _ticks(2)
	social.on_trade_shards(ally.peer, 200)
	trade.cancel()
	await _ticks(2)
	_check(ally.character.shards == 700 and not trade.visible, "cancelling gives back what was offered")
	# fame
	ch.level = maxi(ch.level, TDSocial.FAME_LEVEL)
	ch.fame_day = -1
	Net.ask(&"req_fame", [ally.peer, true])
	Net.ask(&"req_fame", [ally.peer, true])
	_check(ally.character.fame == 1, "fame goes up by one, once a day")
	# a guild
	Net.server._enter_map(_me(), &"dawnharbor", 300)
	Net.server._enter_map(ally, &"dawnharbor", 400)
	await _ticks(3)
	ch.shards = TDSocial.GUILD_COST + 100
	ch.level = maxi(ch.level, TDSocial.GUILD_LEVEL)
	# Hollis keeps the guild register in Dawnharbor's Guild Hall
	Net.server._enter_map(_me(), &"dawnharbor_guild", 240)
	Net.server._enter_map(ally, &"dawnharbor_guild", 400)
	await _ticks(3)
	var clerk: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"guild_clerk")[0]
	_teleport(Vector2(clerk.position.x - 30, clerk.position.y))
	await _ticks(2)
	Net.ask(&"req_guild_create", [&"guild_clerk", "Dawnbreakers"])
	await _ticks(2)
	_check(Game.me.guild == "Dawnbreakers" and ch.shards == 100, "the guild clerk founds a guild for its fee")
	Net.ask(&"req_social", [&"guild", "Ally"])
	id = social.invites.keys().filter(func(k: int) -> bool: return social.invites[k]["kind"] == "guild")[0]
	social.on_answer(ally.peer, id, true)
	await _ticks(5)
	_check(ally.character.guild == "Dawnbreakers" and world.avatars[ally.peer].guild == "Dawnbreakers", "guild members show the guild under their name")
	var reloaded := TDSocial.new(Net.server, save_dir)
	_check(reloaded.guild_of("Ally").get("name") == "Dawnbreakers", "guilds are saved")
	Net.ask(&"req_chat", ["/g hi guild"])
	await _ticks(2)
	_check(str(chat.lines[-1]["text"]) == "[Guild] %s: hi guild" % ch.name, "/g talks to the guild")
	# a player shop in the free market
	Net.server._enter_map(_me(), &"dawnharbor", 300)
	await _ticks(3)
	var market: PortalDef = Content.map(&"dawnharbor").portals.filter(func(p: PortalDef) -> bool: return p.target_map == &"free_market")[0]
	_teleport(Vector2(market.x, 620))
	await _ticks(2)
	await _tap("move_up")
	await _ticks(4)
	_check(world.map.id == &"free_market", "Dawnharbor's portal leads to the Free Market")
	Net.server._enter_map(ally, &"free_market", 900)
	ch.inventory.add(Content.item(&"petal_wing"), 4)
	_me().dirty_character = true
	await _ticks(3)
	var stall: TDPlayerShopWindow = world.hud.windows["player_shop"]
	stall.setup()
	stall.add_entry(ItemDef.Tab.ETC, Game.me.inventory.find(Content.item(&"petal_wing")), 120)
	stall.open_shop()
	await _ticks(3)
	_check(social.shops.has(_me().peer) and world.hud.selling() and Game.me.inventory.count_of(Content.item(&"petal_wing")) == 0, "opening a shop puts your goods on display")
	await _ticks(TDServer.SNAPSHOT_EVERY)
	_check(world.player_infos.get(_me().peer, [""])[-1] == stall.shop_title, "others see the shop sign")
	var before := ch.shards
	social.on_shop_view(ally.peer, _me().peer)
	social.on_shop_buy(ally.peer, _me().peer, 0, &"petal_wing")
	await _ticks(3)
	_check(ally.character.inventory.count_of(Content.item(&"petal_wing")) == 4 and ch.shards == before + 120, "buying pays the owner")
	_check(not social.shops.has(_me().peer) and not world.hud.selling(), "a sold-out shop closes")
	# leaving takes them out of the party
	social.left(ally)
	Net.server.sessions.erase(ally.peer)
	ally.map.remove_player(ally)
	await _ticks(35)
	_check(Game.social.get("party", {}).is_empty(), "a party of one breaks up")
	Net.server._enter_map(_me(), &"meadow", 300)
	await _ticks(3)

## Chairs, pets, the Monster Book and achievements.
func _check_keepsakes() -> void:
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
	_check(ch.health.hp - hp == 2 + ch.level / 3 + ch.regen_bonus().x + stool.regen_hp, "a chair adds to HP recovery")
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

func server_forfeit_check(ch: Character) -> void:
	Net.ask(&"req_quest_forfeit", [&"q04_sweet_nectar"])
	_check(not ch.quests.active.has(&"q04_sweet_nectar"), "a quest can be given up")

## Hosts a game and has a second copy of the game (tests/bot_client.tscn) join it over
## the network: each must see the other, and the bot's attacks must count on the server.
func _check_multiplayer() -> void:
	var port := TEST_PORT + OS.get_process_id() % TEST_PORTS
	var problem := Net.host(port)
	for i in 20:
		if problem == "":
			break
		port = TEST_PORT + (port - TEST_PORT + 1) % TEST_PORTS
		problem = Net.host(port)
	_check(problem == "", "hosting opens a port (%d)%s" % [port, "" if problem == "" else ": " + problem])
	if problem != "":
		return
	Net.create_character("Host", NewCharacter.new())
	Net.play("Host")
	await _ticks(2)
	_check(world.started and Net.mode == Net.Mode.HOST, "the host plays in their own game")
	_me().inv = 100000
	DirAccess.remove_absolute(bot_result)
	var bot := OS.create_process(OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/bot_client.tscn", "--", str(port), bot_result])
	_check(bot > 0, "a second game starts to join")
	var bot_peer := 0
	for i in 1200:
		await _ticks(1)
		for peer in Net.server.sessions:
			if peer != 1:
				bot_peer = peer
		if bot_peer != 0:
			break
	_check(bot_peer != 0, "the second game registers on the host over an encrypted connection and joins")
	_check(Net.server.lobby.accounts.exists(BotClient.USERNAME), "the bot's account is saved on the host")
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
				m.area = m.plat # floor Dewlings keep out of the village, where the bot stands
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
	var f := FileAccess.open(bot_result, FileAccess.READ)
	var result: Variant = JSON.parse_string(f.get_as_text()) if f else null
	f = null
	DirAccess.remove_absolute(bot_result)
	_check(result is Dictionary and result.get("saw_host", false), "the other player sees the host %s" % [result])
	_check(result is Dictionary and result.get("saw_mobs", false) and result.get("saw_hits", false), "the other player sees the monsters and their own hits")
	for i in 120:
		await _ticks(1)
		if not Net.server.sessions.has(bot_peer):
			break
	_check(not Net.server.sessions.has(bot_peer) and not world.avatars.has(bot_peer), "when they quit, they leave the host's map")
	world.stop()
