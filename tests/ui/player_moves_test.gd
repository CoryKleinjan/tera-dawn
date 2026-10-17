extends TestCase
## Job movement skills on your own character in a running game: a Charge lunges flat, a
## Flash Jump only works in the air, a Blink jumps the held way, a Backstep Leap springs back
## still facing ahead, a Rolling Dash rolls along the ground, and air moves work once per jump.
## Runs on Dawnrise Meadow's open floor.

const FLOOR := Vector2(1305, 620)

var ui: UiHelpers
var me: TDPlayer

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()
	await ui.enter_map(&"meadow", 200)
	me = ui.world.player
	# meadow monsters come after you: keep them out of the way
	for m in ui.player().map.mobs:
		m.dead = true
		m.respawn = 1 << 30

func after_each() -> void:
	Input.action_release("move_up")
	ui.stop()

func _learn(id: StringName) -> SkillDef:
	await ui.edit(func(c: Character) -> void:
		c.skills.learned[id] = 1
		c.mp = 999)
	return Content.skill(id)

func _stand() -> void:
	ui.teleport(FLOOR)
	me.on_ground = true
	me.cooldown = 0
	me.face = 1
	await ui.ticks(2)

func test_charge_lunges_ahead_flat() -> void:
	var skill: SkillDef = await _learn(&"charge")
	await _stand()
	me._use(skill)
	await ui.ticks(skill.move.ticks + 1)
	check_near(me.position.x - FLOOR.x, skill.move.distance_at(1), "about its distance ahead", 12.0)
	check_eq(me.position.y, FLOOR.y, "along the ground")

func test_charge_in_the_air_works_once_per_jump() -> void:
	var skill: SkillDef = await _learn(&"charge")
	ui.teleport(FLOOR + Vector2(0, -200))
	me.on_ground = false
	me.cooldown = 0
	me._use(skill)
	var y := me.position.y
	await ui.ticks(4)
	check_eq(me.position.y, y, "flat through the air")
	await ui.ticks(skill.move.ticks)
	me.cooldown = 0
	var x := me.position.x
	me._use(skill)
	await ui.ticks(4)
	check(me.position.x < x + 20.0, "no second Charge in the same jump")

func test_flash_jump_only_in_the_air() -> void:
	var skill: SkillDef = await _learn(&"flash_jump")
	await _stand()
	me._use(skill)
	await ui.ticks(2)
	check(me.on_ground, "nothing on the ground")
	ui.teleport(FLOOR + Vector2(0, -150))
	me.on_ground = false
	me.cooldown = 0
	me._use(skill)
	check(me.vel.y < 0.0 and me.vel.x > TDPlayer.RUN_SPEED, "bursts up and forward")

func test_blink_jumps_the_held_way() -> void:
	var skill: SkillDef = await _learn(&"blink")
	await _stand()
	Input.action_press("move_up")
	me._use(skill)
	check_near(FLOOR.y - me.position.y, skill.move.distance_at(1), "straight up")
	check_eq(me.position.x, FLOOR.x, "no sideways")
	await ui.ticks(3)
	check_near(ui.player().position.x, me.position.x, "the server agrees", 1.0)

func test_backstep_springs_back_still_facing_ahead() -> void:
	var skill: SkillDef = await _learn(&"backstep_leap")
	await _stand()
	me._use(skill)
	await ui.ticks(skill.move.ticks)
	check(me.position.x < FLOOR.x - 60.0, "well back")
	check_eq(me.face, 1, "still facing ahead")

func test_rolling_dash_rolls_curled_up_on_the_ground() -> void:
	var skill: SkillDef = await _learn(&"rolling_dash")
	await _stand()
	me._use(skill)
	await ui.ticks(2)
	check_eq(me._animation(), skill.animation, "curled up in its roll pose")
	check(ui.player().dodge_t > 0, "the server won't let anything hit him")
	await ui.ticks(skill.move.ticks)
	check(me.position.x > FLOOR.x + 80.0, "rolled ahead")
