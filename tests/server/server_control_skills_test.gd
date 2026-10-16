extends TestCase
## Each first job's monster-control skill through the server: Skyward Cleave throws monsters
## up, Gravity Well pulls them down and hits the grounded ones, Shadow Ambush blinks into a
## group and stuns it, Pinning Shot holds a monster even in mid-air, and Anchor Haul drags
## monsters back. Bosses take the damage but are never thrown, dragged or stunned.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var mob_def: MonsterDef
var map: MapInstance
var ann: SimPlayer

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()

## `xs`: where each monster stands; Ann stands at 300 facing right.
func _setup(xs: Array, boss := false, flying := false) -> void:
	mob_def = ServerHarness.monster(&"test_mob", 100000, 10)
	mob_def.attack = 40
	mob_def.boss = boss
	mob_def.flying = flying
	map = h.field_with([ServerHarness.spawn(mob_def, xs.size())])
	for i in xs.size():
		map.mobs[i].position.x = xs[i]
	ann = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	ann.face = 1
	ServerHarness.no_cards(ann, mob_def)

func _use(id: StringName, lvl := 1) -> void:
	ann.character.skills.learned[id] = lvl
	ann.character.mp = 999
	ann.cooldown = 0
	ann.recharge.clear()
	h.ask(ann.peer, &"req_skill", [id, ann.position, ann.face, Hitbox.Aim.AHEAD])

## {mob index: number of damage lines} in the last ev_skill.
func _lines() -> Dictionary:
	var out := {}
	for row: Array in h.last(2, &"ev_skill")[5]:
		out[row[0]] = (row[1] as Array).size()
	return out

func test_skyward_cleave_throws_monsters_up() -> void:
	_setup([360.0, 400.0, 900.0])
	_use(&"skyward_cleave")
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
	_use(&"skyward_cleave")
	check(_lines().has(0), "Skyward Cleave still hits a boss")
	check(not m.tossed, "but doesn't throw it")
	m.stun(60)
	check_eq(m.stun_t, 0, "a boss can't be stunned")
	m.drag_to(100.0)
	check_eq(m.position.x, 360.0, "or dragged")

func test_gravity_well_pulls_monsters_down_and_hits_the_ground() -> void:
	_setup([360.0, 200.0, 900.0])
	map.mobs[0].launch(9.0)
	h.step(10)
	check(map.mobs[0].hop > 0.0, "the first one is in the air")
	_use(&"gravity_well")
	check_eq(map.mobs[0].hop, 0.0, "it's pulled down")
	check(not map.mobs[0].tossed, "and no longer thrown")
	check(map.mobs[0].floored_t > 0, "but knocked down")
	var lines := _lines()
	check(lines.has(0), "then the shockwave hits it")
	check(lines.has(1), "and the one behind")
	check(not lines.has(2), "but not one far away")

func test_gravity_well_grounds_fliers() -> void:
	_setup([360.0], false, true)
	var m := map.mobs[0]
	check(not m.grounded(), "a flier hovers")
	_use(&"gravity_well")
	check(m.grounded(), "pulled to the ground")
	check(_lines().has(0), "and hit")
	h.step(SimMob.DOWNED_TICKS + 1)
	check(not m.grounded(), "it rises again after a while")

func test_shadow_ambush_blinks_into_the_biggest_group_and_stuns_it() -> void:
	_setup([380.0, 560.0, 600.0, 630.0])
	_use(&"shadow_ambush")
	check(ann.position.x > 540.0 and ann.position.x < 640.0, "Ann lands in the group of three (at %.0f)" % ann.position.x)
	check(not h.last(2, &"ev_place").is_empty(), "and her screen is told where she is")
	var lines := _lines()
	for i in [1, 2, 3]:
		check_eq(lines.get(i, 0), Content.skill(&"shadow_ambush").hits, "monster %d is struck" % i)
		check_eq(map.mobs[i].stun_t, Content.skill(&"shadow_ambush").stun_ticks(1), "and stunned")
	check(not lines.has(0), "the lone one is left alone")

func test_shadow_ambush_with_nothing_ahead_stays_put() -> void:
	_setup([100.0])
	_use(&"shadow_ambush")
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

func test_pinning_shot_holds_a_monster_in_mid_air() -> void:
	_setup([500.0])
	ann.character.equipment.put(&"weapon", ItemStack.exact(Content.item(&"willow_bow")))
	ann.character.recalc()
	var m := map.mobs[0]
	m.launch(9.0)
	h.step(8)
	_use(&"pinning_shot")
	check(_lines().has(0), "the arrow hits")
	var pin := Content.skill(&"pinning_shot")
	check_eq(m.root_t, pin.root_ticks(1), "rooted for its time")
	var hop := m.hop
	h.step(30)
	check(hop > 0.0 and is_equal_approx(m.hop, hop), "and held up in the air")

func test_anchor_haul_drags_monsters_back() -> void:
	_setup([480.0, 540.0, 900.0])
	_use(&"anchor_haul")
	var pull := Content.skill(&"anchor_haul").pull
	for i in 2:
		check_near(map.mobs[i].position.x, 300.0 + pull, "monster %d is dragged in front of Ann" % i)
	check_eq(map.mobs[2].position.x, 900.0, "the far one stays")

func test_ambush_spot_picks_the_bigger_group() -> void:
	var s := Content.skill(&"shadow_ambush")
	var bodies: Array[Vector2] = [Vector2(400, 500), Vector2(560, 500), Vector2(600, 500), Vector2(200, 500)]
	var to := s.ambush_spot(Vector2(300, 500), 1, bodies)
	check_near(to.x, 580.0, "the middle of the pair ahead")
	check_eq(s.ambush_spot(Vector2(300, 500), -1, [Vector2(900, 500)] as Array[Vector2]), Vector2.INF, "nothing behind counts")
