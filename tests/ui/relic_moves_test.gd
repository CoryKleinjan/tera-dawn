extends TestCase
## Moves from boss relics on your own character in a running game: nothing without its relic,
## a Dash bursts flat ahead (once per jump in the air), a double jump works once per jump, a
## Slam drops straight down, and a Surge charges with Down + Dash held and flies once let go
## (let go too soon, it fizzles). Dash, Double Jump and Surge play their painted effects
## round him. Runs on Dawnrise Meadow's open floor.

const FLOOR := Vector2(1305, 620)

var ui: UiHelpers
var me: TDPlayer

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()
	await ui.enter_map(&"meadow", 200)
	me = ui.world.player
	for m in ui.player().map.mobs:
		m.dead = true
		m.respawn = 1 << 30

func after_each() -> void:
	for a in ["dash", "jump", "move_down"]:
		Input.action_release(a)
	ui.stop()

func _learn(id: StringName) -> void:
	await ui.edit(func(c: Character) -> void:
		c.learn_relic(Content.item(id) as RelicDef))

func _stand() -> void:
	ui.teleport(FLOOR)
	me.on_ground = true
	me.face = 1
	await ui.ticks(2)

func _in_air() -> void:
	ui.teleport(FLOOR + Vector2(0, -200))
	me.on_ground = false
	me.face = 1
	await ui.ticks(1)
	me.jump_grace.cancel() # no ledge grace: this is mid-air

## Presses `action` and lets go `hold` ticks later (the player sees the press a tick later).
func _tap(action: String, hold := 2) -> void:
	Input.action_press(action)
	await ui.ticks(hold)
	Input.action_release(action)

## Whether relic `id`'s painted effect is playing round him.
func _effect_of(id: StringName) -> bool:
	var def := (Content.item(id) as RelicDef).effect
	return def != null and ui.world.fx_layer.get_children().any(func(n: Node) -> bool:
		return n is TDEffect and (n as TDEffect).def == def and (n as TDEffect).follow == me)

func test_no_dash_without_its_relic() -> void:
	await _stand()
	await _tap("dash")
	await ui.ticks(TDPlayer.DASH_TICKS)
	check_near(me.position.x, FLOOR.x, "stays put", 1.0)

func test_a_dash_bursts_flat_ahead() -> void:
	await _learn(&"tusk_charm")
	await _stand()
	await _tap("dash", 1)
	await ui.ticks(TDPlayer.DASH_TICKS + 1)
	check_near(me.position.x - FLOOR.x, TDPlayer.DASH_SPEED * TDPlayer.DASH_TICKS, "about its distance ahead", 16.0)
	check_eq(me.position.y, FLOOR.y, "along the ground")
	check_near(ui.player().position.x, me.position.x, "the server agrees", 40.0)
	check(_effect_of(&"tusk_charm"), "its painted spray follows him")

func test_a_dash_in_the_air_is_flat_and_once_per_jump() -> void:
	await _learn(&"tusk_charm")
	await _in_air()
	await _tap("dash", 1)
	var y := me.position.y
	await ui.ticks(3)
	check_eq(me.position.y, y, "flat through the air")
	await ui.ticks(TDPlayer.DASH_TICKS)
	var x := me.position.x
	await _tap("dash", 1)
	await ui.ticks(3)
	check(me.position.x < x + 20.0, "no second Dash in the same jump")

func test_a_double_jump_works_once_per_jump() -> void:
	await _learn(&"wingstone")
	await _in_air()
	me.vel.y = 4.0
	await _tap("jump")
	check(me.vel.y < 0.0, "jumps again in mid-air")
	check(_effect_of(&"wingstone"), "with its painted burst")
	me.vel.y = 4.0
	await _tap("jump")
	check(me.vel.y > 0.0, "only once")

func test_no_double_jump_without_its_relic() -> void:
	await _in_air()
	me.vel.y = 4.0
	await _tap("jump")
	check(me.vel.y > 0.0, "keeps falling")

func test_a_slam_drops_straight_down_to_the_ground() -> void:
	await _learn(&"magma_heart")
	await _in_air()
	me.vel.x = 3.0
	Input.action_press("move_down")
	await _tap("jump")
	check(me._slamming, "slamming")
	check_eq(me._animation(), &"fall", "in its pose")
	for i in 40:
		await ui.ticks(1)
		if me.on_ground:
			break
	Input.action_release("move_down")
	check(me.on_ground and not me._slamming, "landed")
	check_near(me.position.x, FLOOR.x, "straight down", 4.0)

func test_a_surge_charges_then_flies_ahead() -> void:
	await _learn(&"titans_pearl")
	await _stand()
	Input.action_press("move_down")
	Input.action_press("dash")
	await ui.ticks(TDPlayer.SURGE_CHARGE + 4)
	check_eq(me._animation(), &"crouch", "crouched while it charges")
	check_near(me.position.x, FLOOR.x, "still while charging", 1.0)
	Input.action_release("dash")
	Input.action_release("move_down")
	await ui.ticks(20)
	check(me.position.x > FLOOR.x + 150.0, "flying ahead")
	check(_effect_of(&"titans_pearl"), "with its painted trail")
	check_eq(me.position.y, FLOOR.y, "straight across")

func test_a_surge_let_go_too_soon_fizzles() -> void:
	await _learn(&"titans_pearl")
	await _stand()
	Input.action_press("move_down")
	Input.action_press("dash")
	await ui.ticks(5)
	Input.action_release("dash")
	Input.action_release("move_down")
	await ui.ticks(10)
	check_near(me.position.x, FLOOR.x, "goes nowhere", 1.0)
