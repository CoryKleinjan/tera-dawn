extends Node
## Renders a few gameplay moments to PNG for reviewing art changes. Needs a GPU (or lavapipe) and a display:
##   xvfb-run godot --path . --resolution 1600x900 res://tests/screenshot.tscn -- <out_dir>

var out := "user://shots"

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	var w := get_child(0) as TDWorld
	if w:
		w.player.inv = 100000 if w.started else 0
	# Freeze the game for the shot.
	get_tree().paused = true
	if w:
		# windows still growing in and speech still typing out show finished
		for win: TDWindow in w.hud.windows.values():
			win.settle()
		w.hud.tooltip.modulate.a = 1.0
	await RenderingServer.frame_post_draw
	get_tree().paused = false
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)
	# achievement toasts and job ribbons belong to the moment they popped up in, not later shots
	if w:
		w.hud.banners.clear()

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## The Equip slot holding an item, or -1.
func _slot_of(id: StringName) -> int:
	for i in Inventory.SLOTS:
		var s := _me().character.inventory.at(ItemDef.Tab.EQUIP, i)
		if s and s.item.id == id:
			return i
	return -1

## The server's side of the player.
func _me() -> SimPlayer:
	return Net.server.sessions[1]

## Moves the player instantly on both sides.
func _teleport(world: TDWorld, at: Vector2) -> void:
	world.player.position = at
	world.player.vel = Vector2.ZERO
	_me().position = at

## Moves the player to map `id` at `x` and waits for it to load.
func _go(id: StringName, x := 300.0) -> void:
	Net.server.enter_map(_me(), id, x)
	await _physics(10)

## The NPC with this id on the map the player is on.
func _npc(world: TDWorld, id: StringName) -> TDNpc:
	return world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == id)[0]

## Puts a monster somewhere on its platform (on the server, which the game then shows).
func _place_mob(m: SimMob, x: float) -> void:
	m.position.x = x

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var only := args[1] if args.size() > 1 else ""
	Net.save_dir = "user://screenshot_characters"
	TestGear.install()  # the shots use the test gear (the game has only starter sets)
	var world: TDWorld = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await _frames(10)
	if only == "" or only == "title":
		await _shot("title")
	for f in ["dawnling.json", "mira.json", "order.json"]:
		DirAccess.remove_absolute("user://screenshot_characters/" + f)
		DirAccess.remove_absolute("user://screenshot_characters/" + f + SafeFile.BACKUP)
	world.hud.title._on_solo()
	await _physics(2)
	if only == "" or only == "creator":
		# The character creator, with a name and a few choices made.
		world.hud.title.character_select.create_button.pressed.emit()
		var creator := world.hud.title.creator
		creator.name_field.text = "Dawnling"
		creator.step("outfit:%d" % EquipDef.Slot.TOP, 1)
		await _frames(10)
		await _shot("creator")
		creator.cancelled.emit()
		await _frames(2)
	Net.create_character("Dawnling", NewCharacter.new())
	Net.create_character("Mira", NewCharacter.new())
	await _physics(2)
	if only == "" or only == "select":
		world.hud.title.character_select.select("Dawnling")
		await _frames(10)
		await _shot("select")
	Net.play("Dawnling")
	await _physics(2)
	var ch := _me().character
	ch.essence = 9
	ch.recalc()
	ch.refill()
	_me().dirty_character = true
	var p := world.player
	_me().inv = 100000
	# new characters start in the village now; the shots below are set in the meadow
	Net.server.enter_map(_me(), &"meadow", 1120)
	await _physics(10)
	if only == "" or only == "menu":
		# The game menu, then each settings tab.
		_teleport(world, Vector2(1120, 620))
		await _physics(20)
		world.hud.show_title(true)
		await _frames(4)
		await _shot("game_menu")
		world.hud.open_settings()
		for tab in ["controls", "audio", "video"]:
			world.hud.settings_menu.show_tab(["controls", "audio", "video"].find(tab))
			await _frames(4)
			await _shot("settings_" + tab)
		world.hud.settings_menu.hide()
		world.hud.resume()
	if only == "" or only == "meadow":
		_teleport(world, Vector2(1120, 620))
		p.face = -1
		await _physics(40)
		await _shot("meadow")
	if only == "" or only == "action":
		# Dawn Slash into a pack of Dewlings on the second platform.
		_teleport(world, Vector2(230, 500))
		p.face = 1
		for m in Net.server.maps[&"meadow"].mobs:
			if m.plat == world.platforms[1]:
				_place_mob(m, randf_range(300, 380))
		_me().character.job = Content.job(&"warrior")
		_me().character.skills.learned[&"dawn_slash"] = 1
		_me().character.set_quickslot(0, &"skill", &"dawn_slash")
		_me().dirty_character = true
		await _physics(40)
		Input.action_press("quick_1")
		await _physics(2)
		Input.action_release("quick_1")
		await _physics(3)
		await _shot("action")
	if only == "" or only == "village":
		# The elder in the village, with a few lines in the log and the chat.
		await _go(Character.START_MAP)
		var elder := _npc(world, &"village_elder")
		_teleport(world, Vector2(elder.position.x - 40, elder.position.y))
		p.face = 1
		world.show_pickup(Content.item(&"moss_tuft"), 3)
		world.add_log("Quest accepted: Moss for the Stall", Palette.SUN)
		world.hud.chat.add("all", "Mossy", "Anyone heading to Fern Hollow?")
		world.hud.chat.add("party", "Kestrel", "On my way!")
		await _physics(15)
		await _shot("village")
		world.log_lines.clear()
		world.hud.chat.lines.clear()
	if only == "chat":
		# Speech bubbles (short, two lines, a pet) and the open chat box with a few lines.
		await _go(Character.START_MAP)
		var elder := _npc(world, &"village_elder")
		_teleport(world, Vector2(elder.position.x - 40, elder.position.y))
		p.face = 1
		await _physics(5)
		world.show_chat("all", ch.name, "Hi!", 1)
		world.hud.chat.add("all", "Mossy", "Anyone heading to Fern Hollow?")
		world.hud.chat.add("party", "Kestrel", "On my way! Wait for me by the big tree near the docks, I'll bring potions.")
		world.hud.chat.add("system", "", "Mossy joined the party.")
		world.hud.chat.open("hello there")
		await _frames(3)
		await _shot("chat_short")
		world.show_chat("all", ch.name, "Anyone want to hunt in the Crystal Caves? I can tank, bring potions!", 1)
		await _frames(3)
		await _shot("chat_long")
		world.hud.chat.close()
	if only == "" or only == "dialogue":
		# Talking to the elder.
		await _go(Character.START_MAP)
		var elder := _npc(world, &"village_elder")
		_teleport(world, Vector2(elder.position.x - 40, elder.position.y))
		await _physics(5)
		elder.talk()
		await _frames(3)
		await _shot("dialogue")
		world.hud.windows["dialogue"].visible = false
	if only == "" or only == "shop":
		# Mira's shop with some loot to sell.
		await _go(&"meadow_store")
		var mira := _npc(world, &"shopkeeper")
		_teleport(world, Vector2(mira.position.x - 40, mira.position.y))
		ch.shards = 1250
		for id in [&"boar_tusk", &"petal_wing", &"dewling_droplet"]:
			ch.inventory.add(Content.item(id), randi_range(3, 40))
		_me().dirty_character = true
		await _physics(5)
		world.hud.open_shop(mira)
		world.hud.windows["shop"].tab = ItemDef.Tab.ETC
		await _frames(3)
		await _shot("shop")
		world.hud.windows["shop"].visible = false
	if only == "" or only == "quests":
		# A quest offer from the elder, the tracker and the quest log.
		ch.quests.accept(Content.quest(&"q02_moss_for_the_stall"))
		ch.inventory.add(Content.item(&"moss_tuft"), 4)
		_me().dirty_character = true
		await _go(Character.START_MAP)
		var elder := _npc(world, &"village_elder")
		_teleport(world, Vector2(elder.position.x - 40, elder.position.y))
		await _physics(5)
		elder.talk()
		var talk: TDDialogueWindow = world.hud.windows["dialogue"]
		talk.choose(0)
		world.hud.toggle_window("quests")
		await _frames(3)
		await _shot("quests")
		talk.visible = false
		world.hud.toggle_window("quests")
	if only == "" or only == "jobs":
		# Guide Sorrel's Magician page, then a Pirate (tinted hero) next to her.
		await _go(Character.START_MAP)
		var guide := _npc(world, &"guide_sorrel")
		_me().dirty_character = true
		_teleport(world, Vector2(guide.position.x - 50, 620))
		await _physics(5)
		guide.talk()
		var talk: TDDialogueWindow = world.hud.windows["dialogue"]
		talk.choose(talk.options.map(func(o: Array) -> String: return o[0]).find("Choose a job"))
		talk.choose(2)
		await _frames(3)
		await _shot("jobs")
		talk.visible = false
		ch.job = Content.job(&"beginner")
	if only == "" or only == "skills":
		await _go(&"meadow", 1120)
		# A Warrior's skill book, quickslots and a running buff.
		ch.job = Content.job(&"warrior")
		ch.essence = maxi(ch.essence, 400)
		for pair in [[&"power_strike", 6], [&"dawn_slash", 3], [&"iron_body", 2], [&"blade_mastery", 1], [&"quick_step", 2], [&"first_aid", 1]]:
			ch.skills.learned[pair[0]] = pair[1]
		ch.set_quickslot(0, &"skill", &"power_strike")
		ch.set_quickslot(1, &"skill", &"dawn_slash")
		ch.set_quickslot(2, &"skill", &"iron_body")
		ch.set_quickslot(3, &"skill", &"quick_step")
		ch.skills.add_buff(Content.skill(&"iron_body"))
		ch.skills.add_buff(Content.skill(&"quick_step"))
		ch.recalc()
		_me().dirty_character = true
		await _physics(5)
		world.hud.toggle_window("skills")
		var book: TDSkillWindow = world.hud.windows["skills"]
		book.tab = 1
		book.selected = &"dawn_slash"
		await _frames(3)
		await _shot("skills")
		world.hud.toggle_window("skills")
	if only == "" or only == "ranged":
		await _go(&"meadow", 1300)
		# An Archer's Heartseeker in flight, and a Magician's spell from a second player.
		ch.job = Content.job(&"archer")
		ch.equipment.take(&"weapon")
		ch.equipment.put(&"weapon", ItemStack.exact(Content.item(&"willow_bow")))
		ch.skills.learned[&"heartseeker"] = 5
		ch.set_quickslot(0, &"skill", &"heartseeker")
		ch.mp = 200
		ch.recalc()
		_me().dirty_character = true
		_teleport(world, Vector2(1300, 620))
		p.face = 1
		var ground: Array = Net.server.maps[&"meadow"].mobs.filter(func(m: SimMob) -> bool: return m.plat == Net.server.maps[&"meadow"].layout.platforms[0])
		for i in mini(2, ground.size()):
			_place_mob(ground[i], 1560 + i * 60)
		await _physics(30)
		_me().cooldown = 0
		p.cooldown = 0
		Input.action_press("quick_1")
		await _physics(2)
		Input.action_release("quick_1")
		await _physics(5)
		await _shot("ranged")
	if only == "muzzles":
		# Each ranged job's shot held still where it leaves, on the frame it leaves on (not in
		# the full run): `_old` from the chest as it used to, `_new` from the bow, the pistol's
		# barrel, the star in his hand or the wand's tip (HeroBody.muzzle).
		await _go(&"greenbough", 900)  # a town: nothing to hit
		for job: Array in [[&"archer", &"hunters_bow", &"", &"bow_shot"], [&"pirate", &"deckhand_scimitar", &"deckhand_pistol", &"broadside"],
				[&"thief", &"footpad_dagger", &"footpad_star", &"star_scatter"], [&"mage", &"novice_wand", &"novice_tome", &"fire_burst"]]:
			for c: Character in [ch, Game.me]:
				c.job = Content.job(job[0])
				c.equipment.take(&"weapon")
				c.equipment.take(&"shield")
				c.equipment.put(&"weapon", ItemStack.exact(Content.item(job[1])))
				if job[2] != &"":
					c.equipment.put(&"shield", ItemStack.exact(Content.item(job[2])))
			_me().dirty_character = true
			await _physics(150)  # the job's ribbon and light fade
			var skill: SkillDef = Content.skill(job[3])
			var weapon: EquipDef = Game.me.equipment.defs().get(&"weapon")
			var move := HeroBody.LOOK.resolve(skill.animation, weapon.weapon_kind)
			var frame: StringName = HeroBody.MUZZLES.frames.get(move, HeroBody.LOOK.frame_at(move, &"", 0.0))
			var spec: Dictionary = HeroBody.LOOK.animations[move]
			var ticks := int(((spec["frames"] as Array).find(frame) + 0.4) / float(spec["fps"]) * 60.0)
			for way in ["old", "new"]:
				p = world.player
				_teleport(world, Vector2(900, world.map.ground_y))
				p.face = 1
				p.scene_pose = skill.animation
				await _frames(2)
				p.body._since = Engine.get_physics_frames() - ticks  # straight to the shot's frame
				await _frames(1)
				var feet := p.position
				var from := feet + Vector2(0, -TDPlayer.CHEST) + Vector2(20, -2)
				if way == "new":
					from = feet + (p.body.muzzle(skill.animation, 1) as Vector2)
				var shot := TDProjectile.create(world, skill.projectile, from, from + Vector2(400, 0), 100000, null, Callable())
				world.fx_layer.add_child(shot)
				shot._sync()
				var at := world.stage.screen(feet, TDStage.Z_PLAYER)
				await _shot("muzzle_%s_%s" % [job[0], way])
				shot.queue_free()
				p.scene_pose = &""
				await _physics(5)  # so the next pose starts from its first frame
				var img := Image.load_from_file("%s/muzzle_%s_%s.png" % [out, job[0], way])
				var k := img.get_width() / TDWorld.VIEW.x
				img.get_region(Rect2i(Vector2i((at + Vector2(-90, -150)) * k), Vector2i(Vector2(220, 170) * k))).save_png("%s/muzzle_%s_%s.png" % [out, job[0], way])
	if only == "" or only == "control":
		# Each job's monster-control skill in action, on a few monsters of a field's widest
		# platform with monsters on it.
		Net.server.enter_map(_me(), &"sandy_shoals", 300.0)
		await _physics(60)
		var field: MapInstance = _me().map
		var plat: Platform = null
		for m in field.mobs:
			if not m.def.flying and not m.def.boss and (plat == null or m.plat.w > plat.w):
				plat = m.plat
		var ground: Array = field.mobs.filter(func(m: SimMob) -> bool: return m.plat == plat and not m.def.flying)
		var left := plat.x + 60.0
		var pack := func(xs: Array) -> void:
			for i in mini(xs.size(), ground.size()):
				var m: SimMob = ground[i]
				_place_mob(m, left + xs[i])
				m.hop = 0.0
				m.hop_v = 0.0
				m.tossed = false
				m.stun_t = 0
				m.hang_t = 0
				m.root_t = 0
				m.health.reset(1000000) # so no blow finishes it before the shot
			for i in range(xs.size(), ground.size()):
				_place_mob(ground[i], plat.x + plat.w - 20.0)
		var cast := func(job: StringName, id: StringName, after: int) -> void:
			ch.job = Content.job(job)
			ch.skills.learned[id] = 10
			ch.set_quickslot(0, &"skill", id)
			ch.mp = 500
			ch.recalc()
			_me().dirty_character = true
			await _physics(20)
			_me().cooldown = 0
			_me().recharge.clear()
			p.cooldown = 0
			p.recharge.clear()
			world.hud.banners.clear()
			Input.action_press("quick_1")
			await _physics(2)
			Input.action_release("quick_1")
			await _physics(after)
			world.hud.banners.clear()
			await _shot("control_" + String(id))
		var stand := func(x: float) -> void:
			_teleport(world, Vector2(left + x, plat.y))
			p.face = 1
		stand.call(0.0)
		pack.call([60, 90, 120])
		await cast.call(&"warrior", &"skyward_cleave", 16)
		await _physics(80)
		stand.call(100.0)
		pack.call([40, 100, 180])
		for i in 2:
			ground[i].launch(9.0)
		await _physics(12)
		await cast.call(&"mage", &"gravity_well", 14)
		await _physics(80)
		stand.call(0.0)
		pack.call([220, 250, 280])
		await cast.call(&"thief", &"shadow_ambush", 40)
		await _physics(80)
		stand.call(0.0)
		pack.call([220])
		ground[0].launch(6.0)
		ch.equipment.take(&"weapon")
		ch.equipment.put(&"weapon", ItemStack.exact(Content.item(&"willow_bow")))
		await cast.call(&"archer", &"pinning_shot", 20)
		await _physics(80)
		stand.call(0.0)
		pack.call([180, 230, 260])
		await cast.call(&"pirate", &"anchor_haul", 14)
	if only == "" or only == "worldmap":
		world.hud.toggle_window("worldmap")
		var wm: TDWorldMapWindow = world.hud.windows["worldmap"]
		wm.open_zone(&"")
		wm._hovered(wm.to_screen(TDWorldMapWindow.capital_pos(Content.regions[&"greenbough"])))
		await _frames(3)
		await _shot("worldmap")
		# every zone up close
		for r: RegionDef in Content.regions.values():
			wm.open_zone(r.id)
			await _frames(3)
			await _shot("worldmap_zone_" + r.id)
		wm.open_zone(&"")
		world.hud.toggle_window("worldmap")
	if only == "" or only == "towns":
		# Every hub town, standing between its store and its hall, and on its raised street.
		for town in [&"dawnharbor", &"greenbough", &"lumewood", &"emberforge", &"lanternfall", &"driftcove"]:
			Net.server.enter_map(_me(), town, 1180)
			await _physics(40)
			await _frames(3)
			await _shot("town_" + town)
		Net.server.enter_map(_me(), &"meadow", 300)
		await _physics(10)
	if only == "" or only == "docks":
		# Captain Marlo with his ship at both docks, and each town's portal to its dock.
		for spot in [[&"dawnrise_dock", 1000], [&"dawnharbor_docks", 1000], [&"dawnrise_village", 560], [&"dawnharbor", 420]]:
			Net.server.enter_map(_me(), spot[0], spot[1])
			await _physics(40)
			await _frames(3)
			await _shot("dock_" + spot[0])
		Net.server.enter_map(_me(), &"meadow", 300)
		await _physics(10)
	if only == "" or only == "rooms":
		# Inside every building you can walk into.
		for m: MapDef in Content.maps.values():
			if m.interior:
				Net.server.enter_map(_me(), m.id, 520)
				await _physics(40)
				await _frames(3)
				await _shot("room_" + m.id)
		Net.server.enter_map(_me(), &"meadow", 300)
		await _physics(10)
	if only == "" or only == "fields":
		# A field from each region, next to its monsters, a boss, and the world map.
		_me().inv = 100000
		for pair in [[&"mushroom_dell", 900], [&"thornwood", 1100], [&"crystal_caves", 1100], [&"smoke_pits", 1100],
				[&"gloom_woods", 1100], [&"coral_reef", 1100], [&"dusk_bridge", 1300], [&"kings_caldera", 700]]:
			Net.server.enter_map(_me(), pair[0], pair[1])
			await _physics(90)
			await _frames(3)
			await _shot("field_" + pair[0])
		_me().inv = 0
		world.hud.toggle_window("worldmap")
		await _frames(3)
		await _shot("worldmap_fields")
		world.hud.toggle_window("worldmap")
		Net.server.enter_map(_me(), &"meadow", 300)
		await _physics(10)
	if only == "subzones":
		# Every field of every region (not in the full run): their variants of the region's look.
		_me().inv = 100000
		for m: MapDef in Content.maps.values():
			if not m.town and not m.interior:
				Net.server.enter_map(_me(), m.id, 900)
				await _physics(40)
				await _frames(3)
				await _shot("subzone_%s_%s" % [m.region, m.id])
		_me().inv = 0
		Net.server.enter_map(_me(), &"meadow", 300)
		await _physics(10)
	if only == "rests":
		# Every rest spot's bench, the hero standing beside it (not in the full run).
		_me().inv = 100000
		for m: MapDef in Content.maps.values():
			for r in m.rest_spots:
				Net.server.enter_map(_me(), m.id, r.x + 80.0, r.y)
				await _physics(40)
				await _frames(3)
				await _shot("rest_%s_%s" % [m.region, m.id])
		_me().inv = 0
		Net.server.enter_map(_me(), &"meadow", 300)
		await _physics(10)
	if only == "" or only == "social":
		# Dawnharbor with friends: a party, chat and the community window.
		var social := Net.server.social
		var friends := []
		for i in 2:
			var f := SimPlayer.new(300 + i, Character.create(["Mossy", "Kestrel"][i]))
			Net.server.sessions[f.peer] = f
			social.joined(f)
			Net.server.enter_map(f, &"dawnharbor", 1000.0 + i * 220.0)
			f.face = -1
			friends.append(f)
		Net.server.enter_map(_me(), &"dawnharbor", 820)
		social.invite(_me(), "party", "Mossy")
		social.on_answer(friends[0].peer, social.invites.keys()[-1], true)
		social.guilds["dawnbreakers"] = {"name": "Dawnbreakers", "master": ch.name, "members": [ch.name, "Mossy"]}
		ch.guild = "Dawnbreakers"
		friends[0].character.guild = "Dawnbreakers"
		_me().dirty_character = true
		social.on_chat(friends[0].peer, "Anyone want to hunt in the Crystal Caves?")
		social.on_chat(_me().peer, "/p I'm in! Meet at Lumewood.")
		social.whisper(friends[1], ch.name, "Want to hunt later?")
		await _physics(40)
		world.hud.toggle_window("community")
		world.hud.windows["community"].tab = 1
		await _frames(3)
		await _shot("social")
		world.hud.toggle_window("community")
		for f in friends:
			social.left(f)
			Net.server.sessions.erase(f.peer)
			f.map.remove_player(f)
		Net.server.enter_map(_me(), &"meadow", 300)
		await _physics(10)
	if only == "" or only == "keepsakes":
		# Sitting on the ground with a pet out, a friend doing the same, and the Monster Book.
		var meadow: MapInstance = Net.server.maps[&"meadow"]
		_teleport(world, Vector2(900, 620))
		p.face = 1
		var friend := SimPlayer.new(400, Character.create("Mossy"))
		meadow.add_player(friend, 1060.0)
		friend.face = -1
		friend.sitting = true
		friend.animation = &"sit"
		friend.character.pet = &"pet_sprout"
		ch.inventory.add(Content.item(&"pet_emberkit"))
		_me().dirty_character = true
		await _physics(3)
		Net.ask(&"req_setup", [Game.me.inventory.find(Content.item(&"pet_emberkit"))])
		Net.ask(&"req_sit", [true])
		var dew: MonsterDef = Content.monster(&"dewling")
		for id in [&"dewling", &"mossling", &"petal_bat", &"sproutcap", &"spore_puff", &"sporecap", &"tide_dewling", &"fern_boar", &"shell_crab"]:
			ch.book.pages[id] = [40 + id.length() * 7, mini(5, id.length() % 6)]
		ch.book.pages[dew.id] = [212, 5]
		ch.achievements.append_array(["first_hunt", "level_10", "first_job", "take_a_seat", "best_friend", "collector"])
		_me().dirty_character = true
		await _physics(240)
		world.log_lines.clear()
		await _frames(3)
		await _shot("sitting_pets")
		world.hud.toggle_window("collection")
		world.hud.windows["collection"].show_monster(dew)
		await _frames(3)
		await _shot("keepsakes")
		world.hud.windows["collection"].tab = 1
		await _frames(3)
		await _shot("achievements")
		world.hud.toggle_window("collection")
		meadow.remove_player(friend)
		Net.ask(&"req_sit", [false])
		await _physics(3)
	if only == "" or only == "players":
		# Two other players nearby. They're on the server but have no game connected.
		_teleport(world, Vector2(1300, 620))
		p.face = 1
		var meadow: MapInstance = Net.server.maps[&"meadow"]
		var others := []
		for i in 2:
			var other := SimPlayer.new(100 + i, Character.create(["Mossy", "Kestrel"][i]))
			meadow.add_player(other, 1380.0 + i * 110.0)
			other.face = -1
			other.animation = [&"idle", &"walk"][i]
			others.append(other)
		await _physics(30)
		await _shot("players")
		for other in others:
			meadow.remove_player(other)
	if only == "" or only == "windows":
		# Inventory, equipment and character windows with some loot, one tooltip showing.
		world.scenes.skip()  # (the intro cutscene would hide the windows)
		for id in [&"leather_boots", &"petal_cape", &"moss_ring", &"oak_shield", &"dawn_blade"]:
			ch.inventory.add(Content.item(id))
		for id in [&"boar_tusk", &"petal_wing", &"dewling_droplet"]:
			ch.inventory.add(Content.item(id), randi_range(3, 40))
		ch.inventory.add(Content.item(&"blue_potion"), 12)
		ch.gear.equip(0)
		ch.essence += 300
		ch.inventory.add(Content.item(&"leaf_cap"))
		ch.gear.equip(_slot_of(&"leaf_cap"))
		ch.inventory.add(Content.item(&"ember_helm"))
		_me().dirty_character = true
		_teleport(world, Vector2(1120, 620))
		await _physics(5)
		# the everyday windows (the world map, community and collection have their own shots)
		var everyday := TDHud.WINDOW_ACTIONS.slice(0, 5)
		for action in everyday:
			world.hud.toggle_window(action)
		var inv: TDInventoryWindow = world.hud.windows["inventory"]
		var helm := _slot_of(&"ember_helm")
		world.hud.tooltip.show_item(inv, Game.me.inventory.at(ItemDef.Tab.EQUIP, helm), inv.global_position + inv.slot_rect(helm).get_center(), "Double-click to equip", true)
		await _frames(3)
		await _shot("windows")
		for action in everyday:
			world.hud.toggle_window(action)
	if only == "" or only == "drops":
		# A spread of loot on the ground: Dawnshards, a potion, an Etc item and gear.
		_teleport(world, Vector2(1000, 620))
		p.face = 1
		var loot := [&"dawnshard", &"red_potion", &"petal_wing", &"dawn_blade", &"elixir", &"leather_boots", &"dawnshard"]
		for i in loot.size():
			var x := 1100 + (i - (loot.size() - 1) / 2.0) * MapInstance.DROP_SPACING
			Net.server.maps[&"meadow"].spawn_drop(Content.item(loot[i]), 3, null, DropFlight.create(Vector2(1100, 600), 620, x), 0)
		await _physics(45)
		await _shot("drops")
	if only == "" or only == "hollow":
		await _go(&"hollow", 760)
		_me().inv = 100000
		await _physics(50)
		var hollow: MapInstance = Net.server.maps[&"hollow"]
		for m in hollow.mobs:
			if m.def.id == &"fern_boar" and m.plat == hollow.layout.platforms[0]:
				_place_mob(m, p.position.x + 150)
				break
		# the boar's Dawn Essence flies to the hero
		hollow.kill_mob(hollow.mobs[0], _me())
		await _physics(25)
		await _shot("hollow")
	if only == "monster_anims":
		# A Bramble Boar walking, hopping, using each move and thrown up and knocked down:
		# frames every few ticks for an animated preview (not in the default run).
		await _monster_anims(world, args[2] if args.size() > 2 else "bramble_boar")
	if only == "boss_anims":
		# A boss's intro roar, each of its moves, its second wind and its fall: frames
		# every two ticks for an in-game preview video (not in the default run).
		await _boss_anims(world, args[2] if args.size() > 2 else "molten_king")
	Net.stop()
	get_tree().quit()

## Frames of a boss fighting the player on its own map (see "boss_anims"): its intro roar,
## each of its moves in order, its second wind and its fall, saved as boss_<id>_<nnnn>.png
## every four ticks (15 a second, real time).
func _boss_anims(world: TDWorld, id: String) -> void:
	# one physics tick per drawn frame, so a slow renderer doesn't skip ticks between shots
	Engine.max_physics_steps_per_frame = 1
	var def := Content.monster(StringName(id))
	var sight := def.sight
	def.sight = 0.0
	for map_id in Content.maps:
		if (Content.maps[map_id] as MapDef).spawns.any(func(s: SpawnDef) -> bool: return s.monster == def):
			Net.server.enter_map(_me(), map_id, 300.0)
			break
	await _physics(60)
	Net.server.scenes.stop(_me())
	world.scenes.stop()
	var field: MapInstance = _me().map
	var mob: SimMob = field.mobs.filter(func(m: SimMob) -> bool: return m.def == def)[0]
	_me().inv = 1000000
	var shots := [0]
	var film := func(ticks: int) -> void:
		var until: int = Net.server.tick + ticks
		while Net.server.tick < until:
			var next: int = Net.server.tick + 4
			while Net.server.tick < next:
				await _physics(1)
			await _shot("boss_%s_%04d" % [id, shots[0]])
			shots[0] += 1
	var stand_off := func() -> void:
		_teleport(world, Vector2(mob.position.x - 230.0, mob.plat.y))
	# it hasn't seen the player yet, then does and roars
	_place_mob(mob, mob.plat.x + mob.plat.w * 0.6)
	stand_off.call()
	world.snap_camera()
	await film.call(30)
	def.sight = sight
	await film.call(def.intro_ticks + 30)
	# each move in its order, the player standing off to its left
	for i in def.moves.size():
		while mob.moves.busy() or mob.roar_t > 0:
			await film.call(2)
		stand_off.call()
		mob.moves.start(i, _me())
		await film.call(def.moves[i].windup + def.moves[i].recover + 50)
	# its second wind at half HP, then its fall
	while mob.moves.busy():
		await film.call(2)
	stand_off.call()
	mob.health.set_hp(def.max_hp / 2 - 1)
	await film.call(def.rage_ticks + 40)
	while mob.moves.busy():
		await film.call(2)
	field.kill_mob(mob, _me())
	await film.call(TDMob.BOSS_DEATH_TICKS + 30)

## Frames of one monster kind going through every animation it has (see "monster_anims"),
## saved as monster_<id>_<nnn>.png. It borrows the moves of every preset family it has
## frames for, so one monster shows them all.
func _monster_anims(world: TDWorld, id: String) -> void:
	var def := Content.monster(StringName(id))
	for map_id in Content.maps:
		if (Content.maps[map_id] as MapDef).spawns.any(func(s: SpawnDef) -> bool: return s.monster == def):
			if _me().map.def.id != map_id:
				Net.server.enter_map(_me(), map_id, 300.0)
			break
	await _physics(60)
	# no intro scene holding the camera
	Net.server.scenes.stop(_me())
	world.scenes.stop()
	var field: MapInstance = _me().map
	var mob: SimMob = null
	for m in field.mobs:
		if m.def == def and (mob == null or m.plat.w > mob.plat.w):
			mob = m
	var others := field.mobs.filter(func(m: SimMob) -> bool: return m != mob)
	for m in others:
		m.die()
		m.respawn = 1000000
	var rig: SpriteRig = world.mobs()[mob.index].rig
	var moves: Array[MonsterMove] = []
	for kind in MonsterMove.Kind.values():
		var mv: MonsterMove = null
		for d: MonsterDef in Content.monsters.values():
			for m: MonsterMove in d.moves:
				if m.kind == kind and not d.boss:
					mv = m
		if mv and rig.has(mv.animation_name()):
			moves.append(mv)
	def.moves = moves
	mob.moves = MobMoves.new(mob)
	mob.health.reset(1000000)
	_me().inv = 1000000
	var x := mob.plat.x + mob.plat.w * 0.5
	var shots := [0]
	var film := func(ticks: int) -> void:
		for i in ticks / 4:
			await _physics(4)
			# a slow renderer runs all four ticks in one frame: let the views catch up
			await _frames(2)
			await _shot("monster_%s_%03d" % [id, shots[0]])
			shots[0] += 1
	# the player stands off to the left, out of its sight while it walks
	var home := x + 110.0
	_teleport(world, Vector2(home - 200.0, mob.plat.y))
	world.snap_camera()
	var reset := func() -> void:
		_place_mob(mob, home)
		mob.dir = -1
		mob.hurt_t = 0
	reset.call()
	var sight := def.sight
	def.sight = 0.0
	await film.call(60)
	def.sight = sight
	# a hop
	reset.call()
	def.jumps = true
	mob.hop_v = def.jump_power
	await film.call(48)
	def.jumps = false
	# each move on the player
	for i in moves.size():
		reset.call()
		mob.moves.start(i, _me())
		await film.call(moves[i].windup + 90)
	# thrown up, then lying knocked down
	reset.call()
	mob.launch(9.0)
	await film.call(100)
