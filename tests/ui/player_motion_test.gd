extends TestCase
## Your own character's animation in a running game: an attack plays your weapon's motion,
## then a ready stance; holding a direction long enough breaks into a run.
## Runs on Dawnrise Meadow's open floor.

const FLOOR := Vector2(1305, 620)

var ui: UiHelpers
var me: TDPlayer

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()
	me = ui.world.player

func after_each() -> void:
	Input.action_release("move_right")
	ui.stop()

func test_an_attack_plays_the_weapons_motion_then_a_ready_stance() -> void:
	ui.teleport(FLOOR)
	me.on_ground = true
	await ui.ticks(2)
	var skill := Game.me.basic_attack()
	me._use(skill)
	check_eq(me._animation(), WeaponStyle.animation_for(Game.me.look(), skill.animation), "the weapon's own blow")
	await ui.ticks(skill.action_ticks + 2)
	check_eq(me._animation(), &"ready", "ready for the next one")
	await ui.ticks(TDPlayer.READY_TICKS)
	check_eq(me._animation(), &"idle", "then he relaxes")

func test_holding_a_direction_breaks_into_a_run() -> void:
	ui.teleport(FLOOR)
	me.on_ground = true
	await ui.ticks(2)
	Input.action_press("move_right")
	await ui.ticks(12)
	check_eq(me._animation(), &"walk", "walking while he speeds up")
	await ui.ticks(TDPlayer.RUN_AFTER + 10)
	check_eq(me._animation(), &"run", "running at full speed")
