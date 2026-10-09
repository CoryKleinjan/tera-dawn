extends TestCase
## Your own character's jump in a running game: coyote time after walking off a ledge and
## jump buffering before landing (JumpGrace), and neither changes how high you go.
## Runs on Dawnrise Meadow: off the right edge of the one-way platform at x 600..880, y 420,
## and over open floor at x 1305.

const LEDGE := Vector2(880, 420)
const FLOOR := 620.0

var ui: UiHelpers
var me: TDPlayer

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()
	me = ui.world.player

func after_each() -> void:
	for a in ["jump", "move_right"]:
		Input.action_release(a)
	ui.stop()

## Stands on the platform just left of its right edge and walks off. Returns once the feet
## have left it.
func _walk_off_ledge() -> void:
	ui.teleport(LEDGE + Vector2(-20, 0))
	me.on_ground = true
	await ui.ticks(2)
	Input.action_press("move_right")
	for i in 60:
		await ui.ticks(1)
		if not me.on_ground:
			break
	Input.action_release("move_right")

## Presses and lets go of the jump key (the player sees the press on the tick after it).
func _tap_jump() -> void:
	Input.action_press("jump")
	await ui.ticks(2)
	Input.action_release("jump")

## The highest point (smallest y) over the next `n` ticks.
func _peak(n: int) -> float:
	var top := me.position.y
	for i in n:
		await ui.ticks(1)
		top = minf(top, me.position.y)
	return top

func test_a_jump_just_after_walking_off_a_ledge_still_jumps() -> void:
	await _walk_off_ledge()
	check(not me.on_ground and me.position.x > LEDGE.x, "walked off")
	await ui.ticks(JumpGrace.COYOTE_TICKS - 3)
	var y := me.position.y
	await _tap_jump()
	check(me.vel.y < 0.0, "rising")
	check(await _peak(40) < y - 40.0, "a real jump")

func test_too_late_after_walking_off_falls() -> void:
	await _walk_off_ledge()
	await ui.ticks(JumpGrace.COYOTE_TICKS + 2)
	await _tap_jump()
	check(me.vel.y > 0.0, "still falling")

func test_a_jump_pressed_just_before_landing_goes_off_on_landing() -> void:
	ui.teleport(Vector2(1305, 560))
	me.on_ground = false
	# press when the landing is two or three ticks off
	for i in 60:
		await ui.ticks(1)
		if me.vel.y > 0.0 and FLOOR - me.position.y < me.vel.y * 2.5:
			break
	check(not me.on_ground, "still in the air when pressed")
	await _tap_jump()
	check(await _peak(30) < FLOOR - 40.0, "jumped right after landing")

func test_a_press_long_before_landing_is_forgotten() -> void:
	ui.teleport(Vector2(1305, 300))
	me.on_ground = false
	await _tap_jump()
	for i in 120:
		await ui.ticks(1)
		if me.on_ground:
			break
	check(me.on_ground, "landed")
	await ui.ticks(3)
	check(me.on_ground and me.position.y == FLOOR, "stays on the ground")

func test_jump_height_is_unchanged() -> void:
	ui.teleport(Vector2(1305, FLOOR))
	me.on_ground = true
	await ui.ticks(2)
	await _tap_jump()
	var top := await _peak(40)
	# rising from the jump speed under gravity: the sum of the speeds until they reach 0
	var want := 0.0
	var v := TDPlayer.JUMP_SPEED * CharacterStats.jump_multiplier(Game.me.stats)
	while v + TDPlayer.GRAVITY < 0.0:
		v += TDPlayer.GRAVITY
		want += v
	check_near(top, FLOOR + want, "same height as before", 0.01)
