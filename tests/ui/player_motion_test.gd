extends TestCase
## Your own character's animation in a running game: an attack plays your weapon's motion,
## then a ready stance; holding a direction long enough breaks into a run; a hop lands
## without the landing crouch; buffs make no motion.
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

func test_a_hop_lands_without_the_landing_crouch_but_a_drop_does() -> void:
	ui.teleport(FLOOR)
	me.on_ground = true
	await ui.ticks(2)
	Input.action_press("jump")
	await ui.ticks(2)
	Input.action_release("jump")
	check(not me.on_ground, "off the ground")
	for i in 90:
		await ui.ticks(1)
		if me.on_ground:
			break
	check(me.on_ground, "back down")
	check(me._animation() != &"land", "no crouch after a plain hop")
	ui.teleport(FLOOR + Vector2(0, -220))
	me.on_ground = false
	me.vel = Vector2.ZERO
	for i in 90:
		await ui.ticks(1)
		if me.on_ground:
			break
	check_eq(me._animation(), &"land", "but there is one after a long drop")

func test_a_buff_makes_no_motion() -> void:
	ui.teleport(FLOOR)
	me.on_ground = true
	await ui.ticks(2)
	var buff: SkillDef = Content.skills[&"iron_body"]
	await ui.edit(func(c: Character) -> void:
		c.skills[buff.id] = 1
		c.mp = 999)
	me.cooldown = 0
	me._use(buff)
	check_eq(me.action_t, 0, "no pose to hold")
	check(me._animation() == &"idle" or me._animation() == &"ready", "he just stands there (%s)" % me._animation())
