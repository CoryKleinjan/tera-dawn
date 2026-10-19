extends Node
## Headless smoke test: godot --headless --path . res://tests/smoke_test.tscn
## Plays a short scripted session and checks the core loop works.
## The checks live in tests/smoke/, one file per area (see SmokeArea); this runner holds the
## world, the saves and the failure count, has the helpers they share, and runs them in order.

const ContentChecks := preload("res://tests/smoke/content.gd")
const BalanceChecks := preload("res://tests/smoke/balance.gd")
const CharacterChecks := preload("res://tests/smoke/character.gd")
const PlayThrough := preload("res://tests/smoke/play_through.gd")
const QuestChecks := preload("res://tests/smoke/quests.gd")
const JobAdvanceChecks := preload("res://tests/smoke/job_advance.gd")
const SkillChecks := preload("res://tests/smoke/skills.gd")
const RangedChecks := preload("res://tests/smoke/ranged.gd")
const TravelChecks := preload("res://tests/smoke/travel.gd")
const FieldChecks := preload("res://tests/smoke/fields.gd")
const SocialChecks := preload("res://tests/smoke/social.gd")
const KeepsakeChecks := preload("res://tests/smoke/keepsakes.gd")
const NetworkChecks := preload("res://tests/smoke/network.gd")

var world: TDWorld
var failures := 0
## Test-only saves, one folder per run: every checkout of the project shares user://, and
## smoke tests may run side by side.
var save_dir := "user://smoke_test_characters_%d" % OS.get_process_id()

## The areas checked, one file each in tests/smoke/ (see SmokeArea), in the order _run
## takes them.
var content := ContentChecks.new(self)
var balance := BalanceChecks.new(self)
var character := CharacterChecks.new(self)
var play := PlayThrough.new(self)
var quests := QuestChecks.new(self)
var job_advance := JobAdvanceChecks.new(self)
var skills := SkillChecks.new(self)
var ranged := RangedChecks.new(self)
var travel := TravelChecks.new(self)
var fields := FieldChecks.new(self)
var social := SocialChecks.new(self)
var keepsakes := KeepsakeChecks.new(self)
var network := NetworkChecks.new(self)

func _ready() -> void:
	# the game has only starter gear, so the tests bring their own to wear and trade
	TestGear.install()
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
	content.check()
	balance.check()
	_clear_saves()
	character.check()
	# Play single player against a server inside this game, with test-only saves.
	_clear_saves()
	Net.save_dir = save_dir
	world = load("res://scenes/world.tscn").instantiate() as TDWorld
	add_child(world)
	await play.start_game()
	await play.walk_and_jump()
	await play.talk_to_elder()
	await play.visit_shop()
	await play.go_to_meadow()
	await play.first_kill()
	await play.loot()
	await play.heal_and_gear()
	await play.windows()

	await quests.check()
	await job_advance.check()

	await skills.check()
	await ranged.check()
	await travel.check()
	await fields.check()
	await social.check()
	await keepsakes.check()

	await play.portal()
	await play.faint()
	await play.leave()

	await network.check()

	_clear_saves()
	DirAccess.remove_absolute(save_dir)
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
