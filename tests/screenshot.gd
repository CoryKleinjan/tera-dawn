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

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var only := args[1] if args.size() > 1 else ""
	Game.save_path = "user://screenshot_save.json"
	Game.new_character()
	Game.level = 9
	Game.map_id = &"meadow"
	Game.refill()
	var world: TDWorld = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await _frames(10)
	if only == "" or only == "title":
		await _shot("title")
	world.hud.title.hide()
	world.start()
	var p := world.player
	p.inv = 100000
	if only == "" or only == "meadow":
		p.position = Vector2(1120, 620)
		p.face = -1
		await _physics(40)
		await _shot("meadow")
	if only == "" or only == "action":
		# Dawn Slash into a pack of Dewlings on the second platform.
		p.position = Vector2(230, 500)
		p.face = 1
		for m in world.mobs():
			if m.plat == world.platforms[1]:
				m.position.x = randf_range(300, 380)
		await _physics(40)
		Input.action_press("skill")
		await _physics(2)
		Input.action_release("skill")
		await _physics(3)
		await _shot("action")
	if only == "" or only == "village":
		# The elder and shopkeeper by the village.
		var elder := world.npcs()[0]
		p.position = Vector2(elder.position.x - 40, 620)
		p.face = 1
		await _physics(5)
		elder.talk()
		await _physics(10)
		await _shot("village")
	if only == "" or only == "windows":
		# Inventory, equipment and character windows with some loot, one tooltip showing.
		for id in [&"leather_boots", &"petal_cape", &"moss_ring", &"oak_shield", &"dawn_blade"]:
			Game.inventory.add(Content.item(id))
		for id in [&"boar_tusk", &"petal_wing", &"dewling_droplet"]:
			Game.inventory.add(Content.item(id), randi_range(3, 40))
		Game.inventory.add(Content.item(&"blue_potion"), 12)
		Game.equip(0)
		Game.ap = 40
		for n in 30:
			Game.add_ap(&"strength")
		p.position = Vector2(1120, 620)
		await _physics(5)
		for action in TDHud.WINDOW_ACTIONS:
			world.hud.toggle_window(action)
		var inv: TDInventoryWindow = world.hud.windows["inventory"]
		world.hud.tooltip.show_item(inv, Game.inventory.at(ItemDef.Tab.EQUIP, 3), inv.global_position + inv.slot_rect(3).get_center())
		await _frames(3)
		await _shot("windows")
		for action in TDHud.WINDOW_ACTIONS:
			world.hud.toggle_window(action)
	if only == "" or only == "drops":
		# A spread of loot on the ground: Dawnshards, a potion, an Etc item and gear.
		p.position = Vector2(1000, 620)
		p.face = 1
		var loot := [&"dawnshard", &"red_potion", &"petal_wing", &"dawn_blade", &"leather_boots", &"dawnshard"]
		for i in loot.size():
			var d := TDDrop.create(world, Content.item(loot[i]), 3, Vector2(1100, 600), 620)
			d.land_x = 1100 + (i - (loot.size() - 1) / 2.0) * TDWorld.DROP_SPACING
			world.drop_layer.add_child(d)
		await _physics(45)
		await _shot("drops")
	if only == "" or only == "rope":
		p.position = Vector2(700, 600)
		await _physics(2)
		Input.action_press("move_up")
		await _physics(40)
		Input.action_release("move_up")
		await _shot("rope")
		p.inv = 100000
	if only == "" or only == "hollow":
		world.load_map(&"hollow", 760)
		p.inv = 100000
		await _physics(60)
		var boar: TDMob = null
		for m in world.mobs():
			if m.def.id == &"ember_boar" and m.plat == world.platforms[0]:
				boar = m
				break
		if boar:
			boar.position.x = p.position.x + 150
		Game.xp = Game.xp_need() - 1
		world.kill_mob(world.mobs()[0])
		await _physics(25)
		await _shot("hollow")
	get_tree().quit()
