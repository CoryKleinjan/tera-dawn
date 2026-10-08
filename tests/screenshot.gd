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
		w.player.inv = 8 if w.started else 0 # a visible frame of the invincibility blink
	await RenderingServer.frame_post_draw
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
	Game.level = 9
	Game.map_id = "meadow"
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
			if m.plat == world.plats[1]:
				m.position.x = randf_range(300, 380)
		await _physics(40)
		Input.action_press("skill")
		await _physics(2)
		Input.action_release("skill")
		await _physics(3)
		await _shot("action")
	if only == "" or only == "hollow":
		world.load_map("hollow", 760)
		p.inv = 100000
		await _physics(60)
		var boar: TDMob = null
		for m in world.mobs():
			if m.type == "emberboar" and m.plat == world.plats[0]:
				boar = m
				break
		if boar:
			boar.position.x = p.position.x + 150
		Game.xp = Game.xp_need() - 1
		world.kill_mob(world.mobs()[0])
		await _physics(25)
		await _shot("hollow")
	get_tree().quit()
