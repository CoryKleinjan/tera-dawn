extends TestCase
## Monster-control skills through the server, with skills made for the test: a launch throws
## monsters up, a slam pulls them down and hits the grounded ones, an ambush blinks into a
## group and stuns it, a pinning root holds a monster even in mid-air, and a pull drags
## monsters back. Bosses take the damage but are never thrown, dragged or stunned.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var u := UnitHelpers.new()
var mob_def: MonsterDef
var map: MapInstance
var ann: SimPlayer

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()
	u.cleanup()

## `xs`: where each monster stands; Ann stands at 300 facing right.
func _setup(xs: Array, boss := false, flying := false) -> void:
	mob_def = ServerHarness.monster(&"test_mob", 100000)
	mob_def.attack = 40
	mob_def.boss = boss
	mob_def.flying = flying
	map = h.field_with([ServerHarness.spawn(mob_def, xs.size())])
	for i in xs.size():
		map.mobs[i].position.x = xs[i]
	ann = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	ann.face = 1
	ServerHarness.no_cards(ann, mob_def)

## Throws what it hits up into the air.
func _launch() -> SkillDef:
	var s := u.skill(&"t_launch")
	s.max_targets = 6
	s.knockback = 0.0
	s.aims = false
	s.launch = 9.0
	s.reach = 110.0
	s.height = 110.0
	return s

## Pulls monsters down all around, then hits the grounded ones.
func _slam() -> SkillDef:
	var s := u.skill(&"t_slam")
	s.max_targets = 8
	s.knockback = 0.5
	s.around = true
	s.slam = true
	s.reach = 200.0
	s.height = 260.0
	return s

## Blinks into the biggest group ahead and stuns it with two blows.
func _ambush() -> SkillDef:
	var s := u.skill(&"t_ambush")
	s.hits = 2
	s.max_targets = 6
	s.knockback = 0.0
	s.around = true
	s.ambush = 330.0
	s.stun = 1.0
	s.reach = 100.0
	s.height = 180.0
	return s

## An arrow that roots a monster and holds it where it was hit.
func _pin() -> SkillDef:
	var s := u.skill(&"t_pin")
	s.knockback = 0.0
	s.root = 2.0
	s.pin = true
	s.reach = 400.0
	s.height = 120.0
	s.projectile = ProjectileDef.new()
	return s

## Drags what it hits back to just in front of the player.
func _pull() -> SkillDef:
	var s := u.skill(&"t_pull")
	s.max_targets = 6
	s.knockback = 0.0
	s.aims = false
	s.pull = 50.0
	s.reach = 280.0
	s.height = 90.0
	return s

func _use(id: StringName, lvl := 1) -> void:
	ann.character.skills.learned[id] = lvl
	ann.character.mp = ann.character.max_mp()
	ann.cooldown = 0
	ann.recharge.clear()
	h.ask(ann.peer, &"req_skill", [id, ann.position, ann.face, Hitbox.Aim.AHEAD])

## {mob index: number of damage lines} in the last ev_skill.
func _lines() -> Dictionary:
	var out := {}
	for row: Array in h.last(2, &"ev_skill")[5]:
		out[row[0]] = (row[1] as Array).size()
	return out

func test_a_launch_throws_monsters_up() -> void:
	_setup([360.0, 400.0, 900.0])
	_use(_launch().id)
	var lines := _lines()
	check(lines.has(0) and lines.has(1), "it hits the monsters in front")
	check(not lines.has(2), "but not one far away")
	h.step(10)
	for i in 2:
		check(map.mobs[i].tossed and map.mobs[i].hop > 20.0, "monster %d is up in the air" % i)
	check_eq(map.mobs[2].hop, 0.0, "the far one stays down")
	var x := map.mobs[0].position.x
	map.mobs[0].hurt_t = 0
	h.step(60)
	check_eq(map.mobs[0].position.x, x, "it doesn't walk while thrown")
	h.step(120)
	check(not map.mobs[0].tossed and map.mobs[0].hop == 0.0, "and it lands again")

func test_a_thrown_monster_lies_knocked_down_after_landing() -> void:
	_setup([360.0])
	var m := map.mobs[0]
	m.launch(9.0)
	h.step(2)
	check(int(m.snapshot()[4]) & SnapshotFlags.MOB_TOSSED != 0, "clients see it knocked up")
	while m.tossed:
		h.step(1)
	check(m.held(), "it lies knocked down when it lands")
	check(int(m.snapshot()[4]) & SnapshotFlags.MOB_FLOORED != 0, "and clients see that")
	var x := m.position.x
	h.step(SimMob.FLOORED_TICKS - 2)
	check_eq(m.position.x, x, "it doesn't walk while down")
	h.step(3)
	check(not m.held(), "then gets up")

func test_a_thrown_monster_cant_hurt_by_touch() -> void:
	_setup([310.0])
	map.mobs[0].launch(9.0)
	var hp := ann.character.health.hp
	h.step(5)
	check_eq(ann.character.health.hp, hp, "no touch damage while it's in the air")

func test_bosses_are_not_thrown_dragged_or_stunned() -> void:
	_setup([360.0], true)
	var m := map.mobs[0]
	_use(_launch().id)
	check(_lines().has(0), "a launch still hits a boss")
	check(not m.tossed, "but doesn't throw it")
	m.stun(60)
	check_eq(m.stun_t, 0, "a boss can't be stunned")
	m.drag_to(100.0)
	check_eq(m.position.x, 360.0, "or dragged")

func test_a_slam_pulls_monsters_down_and_hits_the_ground() -> void:
	_setup([360.0, 200.0, 900.0])
	map.mobs[0].launch(9.0)
	h.step(10)
	check(map.mobs[0].hop > 0.0, "the first one is in the air")
	_use(_slam().id)
	check_eq(map.mobs[0].hop, 0.0, "it's pulled down")
	check(not map.mobs[0].tossed, "and no longer thrown")
	check(map.mobs[0].floored_t > 0, "but knocked down")
	var lines := _lines()
	check(lines.has(0), "then the shockwave hits it")
	check(lines.has(1), "and the one behind")
	check(not lines.has(2), "but not one far away")

func test_a_slam_grounds_fliers() -> void:
	_setup([360.0], false, true)
	var m := map.mobs[0]
	check(not m.grounded(), "a flier hovers")
	_use(_slam().id)
	check(m.grounded(), "pulled to the ground")
	check(_lines().has(0), "and hit")
	h.step(SimMob.DOWNED_TICKS + 1)
	check(not m.grounded(), "it rises again after a while")

func test_an_ambush_blinks_into_the_biggest_group_and_stuns_it() -> void:
	_setup([380.0, 560.0, 600.0, 630.0])
	var ambush := _ambush()
	_use(ambush.id)
	check(ann.position.x > 540.0 and ann.position.x < 640.0, "Ann lands in the group of three (at %.0f)" % ann.position.x)
	check(not h.last(2, &"ev_place").is_empty(), "and her screen is told where she is")
	var lines := _lines()
	for i in [1, 2, 3]:
		check_eq(lines.get(i, 0), ambush.hits, "monster %d is struck" % i)
		check_eq(map.mobs[i].stun_t, ambush.stun_ticks(1), "and stunned")
	check(not lines.has(0), "the lone one is left alone")

func test_an_ambush_with_nothing_ahead_stays_put() -> void:
	_setup([100.0])
	_use(_ambush().id)
	check_eq(ann.position.x, 300.0, "no blink with no monsters ahead")

func test_a_stunned_monster_hangs_in_the_air_and_doesnt_act() -> void:
	_setup([360.0])
	var m := map.mobs[0]
	m.launch(9.0)
	h.step(8)
	m.stun(60)
	var hop := m.hop
	h.step(30)
	check_eq(m.hop, hop, "it hangs where it was stunned")
	check(not m.moves.busy(), "and doesn't attack")
	h.step(120)
	check_eq(m.hop, 0.0, "then it falls")

func test_a_pinning_shot_holds_a_monster_in_mid_air() -> void:
	_setup([500.0])
	var pin := _pin()
	var m := map.mobs[0]
	m.launch(9.0)
	h.step(8)
	_use(pin.id)
	check(_lines().has(0), "the arrow hits")
	check_eq(m.root_t, pin.root_ticks(1), "rooted for its time")
	var hop := m.hop
	h.step(30)
	check(hop > 0.0 and is_equal_approx(m.hop, hop), "and held up in the air")

func test_a_pull_drags_monsters_back() -> void:
	_setup([480.0, 540.0, 900.0])
	var pull := _pull().pull
	_use(&"t_pull")
	for i in 2:
		check_near(map.mobs[i].position.x, 300.0 + pull, "monster %d is dragged in front of Ann" % i)
	check_eq(map.mobs[2].position.x, 900.0, "the far one stays")

func test_ambush_spot_picks_the_bigger_group() -> void:
	var s := _ambush()
	var bodies: Array[Vector2] = [Vector2(400, 500), Vector2(560, 500), Vector2(600, 500), Vector2(200, 500)]
	var to := s.ambush_spot(Vector2(300, 500), 1, bodies)
	check_near(to.x, 580.0, "the middle of the pair ahead")
	check_eq(s.ambush_spot(Vector2(300, 500), -1, [Vector2(900, 500)] as Array[Vector2]), Vector2.INF, "nothing behind counts")
