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
	_check(problems.is_empty(), "maps and monsters reference valid content %s" % [problems])

func _run() -> void:
	_check_content()
	# Start from a fresh character without touching the real save file.
	Game.save_path = "user://smoke_test_save.json"
	Game.level = 1
	Game.xp = 0
	Game.shards = 0
	Game.map_id = &"meadow"
	Game.refill()
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
		if not is_instance_valid(drop):
			continue # picked up while walking to an earlier one
		p.position = Vector2(drop.position.x, 620)
		await _ticks(5)
	_check(Game.shards > shards and world.drop_layer.get_child_count() == 0, "walking over drops picks them up")

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
