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

func _run() -> void:
	# Start from a fresh character without touching the real save file.
	Game.save_path = "user://smoke_test_save.json"
	Game.level = 1
	Game.xp = 0
	Game.shards = 0
	Game.map_id = "meadow"
	Game.hp = Game.max_hp()
	Game.mp = Game.max_mp()
	var scene: PackedScene = load("res://scenes/main.tscn")
	world = scene.instantiate() as TDWorld
	add_child(world)
	await _ticks(5)
	world.start()
	var p := world.player
	p.inv = 100000 # keep monsters from knocking the player around mid-test
	_check(p.on_ground, "player starts on the ground")

	var x0 := p.position.x
	await _hold("move_right", 40)
	_check(p.position.x > x0 + 60, "walking right moves the player")

	await _tap("jump")
	await _ticks(10)
	_check(p.position.y < 620, "jumping leaves the ground")
	await _ticks(40)
	_check(p.on_ground, "player lands again")

	# Put a Dewling right in front of the player and hit it until it dies.
	var mob: TDMob = null
	for m in world.mobs():
		if m.type == "dewling" and m.plat == world.plats[0]:
			mob = m
			break
	p.position = Vector2(mob.position.x - 40, 620)
	p.face = 1
	var xp_before: int = Game.xp + Game.level * 1000
	for i in 12:
		mob.position.x = p.position.x + 40
		await _tap("attack")
		await _ticks(24)
		if mob.dead:
			break
	_check(mob.dead, "basic attacks kill a Dewling")
	_check(Game.xp + Game.level * 1000 > xp_before, "killing a monster gives EXP")
	_check(world.drop_layer.get_child_count() > 0, "the monster drops Dawnshards")
	var shards: int = Game.shards
	await _ticks(80)
	var drop := world.drop_layer.get_child(0) as TDDrop
	if drop:
		p.position = Vector2(drop.position.x, 620)
	await _ticks(5)
	_check(Game.shards > shards, "walking over a drop picks it up")

	# Climb the rope at x=700 up to the platform at y=420.
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
	_check(world.map_id == "hollow", "the portal leads to Ember Hollow")

	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
