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
	# Freeze the game and show the player, who may be mid-blink from their invincibility.
	get_tree().paused = true
	if w:
		w.player.rig.set_opacity(1.0)
	await RenderingServer.frame_post_draw
	get_tree().paused = false
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)

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
	Net.import_legacy_save = false
	var world: TDWorld = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await _frames(10)
	if only == "" or only == "title":
		await _shot("title")
	DirAccess.remove_absolute("user://screenshot_characters/dawnling.json")
	Net.play_single("Dawnling")
	var ch := _me().character
	ch.level = 9
	ch.recalc()
	ch.refill()
	_me().dirty_character = true
	var p := world.player
	_me().inv = 100000
	await _physics(2)
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
		_me().character.skills[&"dawn_slash"] = 1
		_me().character.set_quickslot(0, &"skill", &"dawn_slash")
		_me().dirty_character = true
		await _physics(40)
		Input.action_press("quick_1")
		await _physics(2)
		Input.action_release("quick_1")
		await _physics(3)
		await _shot("action")
	if only == "" or only == "village":
		# The elder and shopkeeper by the village.
		var elder := world.npcs()[0]
		_teleport(world, Vector2(elder.position.x - 40, 620))
		p.face = 1
		await _physics(15)
		await _shot("village")
	if only == "" or only == "dialogue":
		# Talking to the elder.
		var elder := world.npcs()[0]
		_teleport(world, Vector2(elder.position.x - 40, 620))
		await _physics(5)
		elder.talk()
		await _frames(3)
		await _shot("dialogue")
		world.hud.windows["dialogue"].visible = false
	if only == "" or only == "shop":
		# Mira's shop with some loot to sell.
		var mira: TDNpc = world.npcs()[1]
		_teleport(world, Vector2(mira.position.x - 40, 620))
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
		var elder := world.npcs()[0]
		_teleport(world, Vector2(elder.position.x - 40, 620))
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
		var guide: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"guide_sorrel")[0]
		ch.level = maxi(ch.level, 8)
		ch.base.intelligence = 20
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
		# A Warrior's skill book, quickslots and a running buff.
		ch.job = Content.job(&"warrior")
		ch.level = maxi(ch.level, 14)
		ch.sp = 4
		for pair in [[&"power_strike", 6], [&"dawn_slash", 3], [&"iron_body", 2], [&"toughness", 1], [&"quick_step", 2], [&"second_wind", 1]]:
			ch.skills[pair[0]] = pair[1]
		ch.set_quickslot(0, &"skill", &"power_strike")
		ch.set_quickslot(1, &"skill", &"dawn_slash")
		ch.set_quickslot(2, &"skill", &"iron_body")
		ch.set_quickslot(3, &"skill", &"quick_step")
		ch.add_buff(Content.skill(&"iron_body"))
		ch.add_buff(Content.skill(&"quick_step"))
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
		# An Archer's Double Shot in flight, and a Magician's Energy Bolt from a second player.
		ch.job = Content.job(&"archer")
		ch.equipment.take(&"weapon")
		ch.equipment.put(&"weapon", ItemStack.exact(Content.item(&"willow_bow")))
		ch.inventory.add(Content.item(&"feather_arrow"), 300)
		ch.skills[&"double_shot"] = 5
		ch.set_quickslot(0, &"skill", &"double_shot")
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
	if only == "" or only == "worldmap":
		world.hud.toggle_window("worldmap")
		var wm: TDWorldMapWindow = world.hud.windows["worldmap"]
		wm._hovered(wm.to_screen(Content.map(&"hollow").world_pos))
		await _frames(3)
		await _shot("worldmap")
		world.hud.toggle_window("worldmap")
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
		for id in [&"leather_boots", &"petal_cape", &"moss_ring", &"oak_shield", &"dawn_blade"]:
			ch.inventory.add(Content.item(id))
		for id in [&"boar_tusk", &"petal_wing", &"dewling_droplet"]:
			ch.inventory.add(Content.item(id), randi_range(3, 40))
		ch.inventory.add(Content.item(&"blue_potion"), 12)
		ch.equip(0)
		ch.ap = 40
		for n in 30:
			ch.add_ap(&"strength")
		ch.inventory.add(Content.item(&"leaf_cap"))
		ch.equip(_slot_of(&"leaf_cap"))
		ch.inventory.add(Content.item(&"ember_helm"))
		_me().dirty_character = true
		_teleport(world, Vector2(1120, 620))
		await _physics(5)
		for action in TDHud.WINDOW_ACTIONS:
			world.hud.toggle_window(action)
		var inv: TDInventoryWindow = world.hud.windows["inventory"]
		var helm := _slot_of(&"ember_helm")
		world.hud.tooltip.show_item(inv, Game.me.inventory.at(ItemDef.Tab.EQUIP, helm), inv.global_position + inv.slot_rect(helm).get_center(), "Double-click to equip", true)
		await _frames(3)
		await _shot("windows")
		for action in TDHud.WINDOW_ACTIONS:
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
	if only == "" or only == "rope":
		_teleport(world, Vector2(700, 600))
		await _physics(2)
		Input.action_press("move_up")
		await _physics(40)
		Input.action_release("move_up")
		await _shot("rope")
	if only == "" or only == "hollow":
		_teleport(world, Vector2(2530, 620))
		await _physics(3)
		Input.action_press("move_up")
		await _physics(2)
		Input.action_release("move_up")
		_me().inv = 100000
		_teleport(world, Vector2(760, 620))
		await _physics(60)
		var hollow: MapInstance = Net.server.maps[&"hollow"]
		for m in hollow.mobs:
			if m.def.id == &"ember_boar" and m.plat == hollow.layout.platforms[0]:
				_place_mob(m, p.position.x + 150)
				break
		ch.xp = ch.xp_need() - 1
		hollow.kill_mob(hollow.mobs[0], _me())
		await _physics(25)
		await _shot("hollow")
	Net.stop()
	get_tree().quit()
