extends TestCase
## How fighting feels on your own character in a running game: you can swing on the move
## and keep facing the swing, a downward blow bounces you off a monster (pogo), your melee
## blows push you back a little, and a monster's hit freezes you a beat then knocks you away.
## Runs on Dawnrise Meadow.

const FLOOR := Vector2(1305, 620)

var ui: UiHelpers
var me: TDPlayer

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()
	await ui.enter_map(&"meadow", 200)
	me = ui.world.player

func after_each() -> void:
	for a in ["move_left", "move_right", "move_down"]:
		Input.action_release(a)
	ui.stop()

func _stand() -> void:
	ui.teleport(FLOOR)
	me.on_ground = true
	me.cooldown = 0
	await ui.ticks(2)

func test_you_can_swing_while_walking_and_keep_facing_the_swing() -> void:
	await _stand()
	# meadow monsters come after you now: one in reach would turn the swing into a hit
	# (hit-stop) or hurt you, and either stops the walk
	for m in ui.player().map.mobs:
		m.dead = true
		m.respawn = 1 << 30
	await ui.ticks(2)
	Input.action_press("move_right")
	await ui.ticks(6)
	me._use(Game.me.skills.basic_attack())
	var x := me.position.x
	await ui.ticks(4)
	check(me.position.x > x + 4.0, "still walking mid-swing")
	Input.action_release("move_right")
	Input.action_press("move_left")
	await ui.ticks(4)
	check_eq(me.face, 1, "still facing the swing while backing off")
	await ui.ticks(Game.me.skills.basic_attack().action_ticks)
	check_eq(me.face, -1, "turns once the swing is over")

func test_a_downward_blow_bounces_off_a_monster() -> void:
	var m: TDMob = ui.world.mobs()[0]
	ui.teleport(m.body_position() + Vector2(0, -60))
	me.on_ground = false
	me.vel = Vector2.ZERO
	me.cooldown = 0
	Input.action_press("move_down")
	me._use(Game.me.skills.basic_attack())
	check_eq(me._aim, Hitbox.Aim.DOWN, "aimed down")
	check_eq(me.vel.y, TDPlayer.POGO_SPEED, "bounced up")

func test_a_downward_blow_over_nothing_does_not_bounce() -> void:
	ui.teleport(Vector2(FLOOR.x, -150))  # high over the map, clear of every monster
	me.on_ground = false
	me.vel = Vector2.ZERO
	me.cooldown = 0
	Input.action_press("move_down")
	me._use(Game.me.skills.basic_attack())
	check(me.vel.y >= 0.0, "no bounce")

func test_down_on_the_ground_swings_ahead() -> void:
	await _stand()
	Input.action_press("move_down")
	me._use(Game.me.skills.basic_attack())
	check_eq(me._aim, Hitbox.Aim.AHEAD, "only in the air does down aim down")

func test_your_melee_blow_pushes_you_back() -> void:
	await _stand()
	me._aim = Hitbox.Aim.AHEAD
	me.recoil()
	check_eq(me.vel.x, -TDPlayer.RECOIL, "pushed back, away from the way he faces")
	var x := me.position.x
	await ui.ticks(TDPlayer.RECOIL_TICKS)
	check(me.position.x < x - TDPlayer.RECOIL, "slid back a little")

func test_a_hit_freezes_you_then_knocks_you_away() -> void:
	await _stand()
	me.knock_back(FLOOR.x + 30)
	var at := me.position
	await ui.ticks(TDPlayer.HURT_FREEZE - 1)
	check_eq(me.position, at, "held still for a beat")
	await ui.ticks(TDPlayer.HURT_LOCK)
	check(me.position.x < at.x - 20.0, "then thrown away from the monster")
