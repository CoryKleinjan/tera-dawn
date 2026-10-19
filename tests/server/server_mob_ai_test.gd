extends TestCase
## Monster behaviour run by the server: chasing, standing still, touching players, shooting
## and splitting into smaller monsters.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()

## Puts `char_name` on the test field at `x` with every heart.
func _join(peer: int, char_name: String, x: float) -> SimPlayer:
	var p := h.join(peer, char_name, ServerHarness.FIELD, x)
	p.character.refill()
	return p

## A monster that walks at `speed`.
func _walker(id := &"walker", speed := 1.0) -> MonsterDef:
	var d := ServerHarness.monster(id, 100000)
	d.speed = speed
	return d

func test_a_hurt_monster_chases_its_attacker_on_its_platform() -> void:
	var d := _walker()
	var map := h.field_with([ServerHarness.spawn(d)])
	var m := map.mobs[0]
	m.position.x = 600.0
	var p := _join(2, "Ann", 300.0)
	m.hurt(1, 2)
	h.step(14) # knocked back first
	var x := m.position.x
	h.step(10)
	check_near(m.position.x, x - 10 * d.speed * 1.3, "walks toward Ann at 1.3x speed")
	check_eq(m.dir, -1, "facing her")
	check_eq(p.position.x, 300.0, "Ann didn't move")

func test_a_monster_doesnt_chase_someone_on_another_platform() -> void:
	var d := _walker()
	var field := ServerHarness.field_def()
	field.platforms.append(ServerHarness.platform(100, 450, 400))
	field.spawns.append(ServerHarness.spawn(d))
	h.add_map(field)
	var map := h.server.map_instance(ServerHarness.FIELD)
	var m := map.mobs[0]
	m.position.x = 600.0
	var p := _join(2, "Ann", 300.0)
	h.place(p, 300.0, 450.0)
	m.hurt(1, 2)
	h.step(14)
	m.dir = 1
	m.walk_t = 1000
	var x := m.position.x
	h.step(10)
	check_near(m.position.x, x + 10 * d.speed, "keeps patrolling away at normal speed")

func test_the_chase_ends_when_aggro_runs_out() -> void:
	var d := _walker()
	var map := h.field_with([ServerHarness.spawn(d)])
	var m := map.mobs[0]
	m.position.x = 1500.0
	_join(2, "Ann", 300.0)
	m.hurt(1, 2)
	h.step(600)
	check_eq(m.aggro, 0, "calmed down after 600 ticks")

func test_leaving_the_map_ends_the_chase() -> void:
	var map := h.field_with([ServerHarness.spawn(_walker())])
	var m := map.mobs[0]
	m.position.x = 1500.0
	var p := _join(2, "Ann", 300.0)
	m.hurt(1, 2)
	h.move_to(p, ServerHarness.TOWN)
	check_eq(m.aggro, 0, "forgot Ann")

func test_stationary_monsters_never_move_even_when_hit() -> void:
	var d := _walker(&"turret", 2.0)
	d.stationary = true
	var map := h.field_with([ServerHarness.spawn(d)])
	var m := map.mobs[0]
	m.position.x = 340.0
	var p := _join(2, "Ann", 300.0)
	ServerHarness.no_cards(p, d)
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	check(m.health.hp < d.max_hp, "it was hit")
	h.step(120)
	check_eq(m.position.x, 340.0, "never knocked back or walked")

func test_touching_a_monster_hurts_then_gives_invincibility() -> void:
	var d := ServerHarness.monster(&"toucher", 100000)
	var map := h.field_with([ServerHarness.spawn(d)])
	map.mobs[0].position.x = 300.0
	var p := _join(2, "Ann", 300.0)
	var full := p.character.health.hp
	h.step(1)
	check_eq(p.character.health.hp, full - 1, "a heart lost on touch")
	check_eq(h.last(2, &"ev_hurt"), [300.0], "knocked back from the monster")
	check_eq(p.inv, SimPlayer.HURT_INV, "invincible for a while")
	h.step(SimPlayer.HURT_INV - 1)
	check_eq(p.character.health.hp, full - 1, "no more damage while invincible")
	h.step(1)
	check_eq(p.character.health.hp, full - 2, "hurt again once it wears off")

func test_a_monster_far_away_doesnt_hurt() -> void:
	var d := ServerHarness.monster(&"toucher", 100000)
	var map := h.field_with([ServerHarness.spawn(d)])
	map.mobs[0].position.x = 600.0
	var p := _join(2, "Ann", 300.0)
	h.step(60)
	check_eq(p.character.health.hp, p.character.max_hp(), "untouched")

## A move of `kind` for a test monster, ready the moment it fits.
static func _move(kind: MonsterMove.Kind, reach := 320.0) -> MonsterMove:
	var mv := MonsterMove.new()
	mv.id = &"test_move"
	mv.kind = kind
	mv.reach = reach
	mv.windup = 20
	mv.cooldown = 150
	mv.recover = 20
	if kind == MonsterMove.Kind.SHOT:
		mv.projectile = load("res://data/projectiles/mob_bolt.tres")
	return mv

## A monster with `mv`, ready to use it straight away.
func _with_move(mv: MonsterMove, id := &"mover") -> MonsterDef:
	var d := ServerHarness.monster(id, 100000)
	d.attack = 10
	d.sight = 320.0
	d.moves = [mv]
	return d

func _ready_now(m: SimMob) -> void:
	m.moves.cool.fill(0)
	m.moves.gap = 0

func _shooter() -> MonsterDef:
	var d := _with_move(_move(MonsterMove.Kind.SHOT), &"shooter")
	d.attack = 1
	d.stationary = true
	return d

func test_a_shooter_fires_at_a_player_in_sight() -> void:
	var map := h.field_with([ServerHarness.spawn(_shooter())])
	var m := map.mobs[0]
	m.position.x = 500.0
	_ready_now(m)
	var p := _join(2, "Ann", 300.0)
	var full := p.character.health.hp
	h.step(1)
	check(int(m.snapshot()[4]) & SnapshotFlags.MOB_WINDUP != 0, "winds up first")
	check_eq(int(m.snapshot()[5]), 1, "clients know which move, to show its frames")
	check_eq(h.count(2, &"ev_mob_shot"), 0, "no shot yet")
	h.step(20)
	check_eq(h.last(2, &"ev_mob_shot"), [0, 0, 300.0, 600.0 - SimPlayer.CHEST], "fires at where Ann stands")
	check(int(m.snapshot()[4]) & SnapshotFlags.MOB_WINDUP == 0, "and the wind-up ends")
	check_eq(m.dir, -1, "turned to face her")
	var flight: int = m.shots[0][1]
	h.step(flight - 1)
	check_eq(p.character.health.hp, full, "not hit while the shot flies")
	h.step(1)
	check_eq(p.character.health.hp, full - 1, "hit when it lands")

func test_stepping_out_of_the_way_dodges_a_shot() -> void:
	var map := h.field_with([ServerHarness.spawn(_shooter())])
	var m := map.mobs[0]
	m.position.x = 500.0
	_ready_now(m)
	var p := _join(2, "Ann", 300.0)
	h.step(21)
	check_eq(m.shots.size(), 1, "fired")
	h.place(p, 240.0)
	h.step(int(m.shots[0][1]))
	check(m.shots.is_empty(), "the shot landed")
	check_eq(p.character.health.hp, p.character.max_hp(), "missed her")

func test_monsters_ignore_players_out_of_sight() -> void:
	var map := h.field_with([ServerHarness.spawn(_shooter())])
	var m := map.mobs[0]
	m.position.x = 1000.0
	_ready_now(m)
	_join(2, "Ann", 300.0)
	h.step(60)
	check_eq(m.target, 0, "didn't notice Ann 700 px away")
	check_eq(h.count(2, &"ev_mob_shot"), 0, "no shot")

func test_a_monster_notices_a_player_who_comes_in_sight() -> void:
	var d := _walker()
	var map := h.field_with([ServerHarness.spawn(d)])
	var m := map.mobs[0]
	m.position.x = 1000.0
	var p := _join(2, "Ann", 300.0)
	h.step(5)
	check_eq(m.target, 0, "too far to notice")
	h.place(p, 1000.0 - d.sight + 20.0)
	h.step(1)
	check_eq(m.target, 2, "notices her once she's in sight")
	var x := m.position.x
	h.step(10)
	check_near(m.position.x, x - 10 * d.speed * SimMob.CHASE_SPEED, "and goes after her")

func test_a_monster_gives_up_after_losing_sight() -> void:
	var d := _walker()
	var map := h.field_with([ServerHarness.spawn(d)])
	var m := map.mobs[0]
	m.position.x = 600.0
	var p := _join(2, "Ann", 450.0)
	h.step(1)
	check_eq(m.target, 2, "noticed her")
	h.place(p, 1900.0)
	h.step(SimMob.SIGHT_TICKS - 5)
	check_eq(m.target, 2, "still after her for a while")
	h.step(10)
	check_eq(m.target, 0, "then gives up")

func test_it_goes_for_the_nearest_player_it_sees() -> void:
	var map := h.field_with([ServerHarness.spawn(_walker())])
	var m := map.mobs[0]
	m.position.x = 600.0
	_join(2, "Ann", 400.0)
	_join(3, "Bo", 700.0)
	h.step(1)
	check_eq(m.target, 3, "Bo is closer")

func test_it_keeps_after_its_target_while_it_can_see_them() -> void:
	var map := h.field_with([ServerHarness.spawn(_walker())])
	var m := map.mobs[0]
	m.position.x = 600.0
	_join(2, "Ann", 700.0)
	h.step(1)
	check_eq(m.target, 2, "after Ann")
	var bo := _join(3, "Bo", 1200.0)
	m.hurt(1, 3) # Bo hits it from afar
	h.step(1)
	check_eq(m.target, 2, "still after Ann, who's in front of it")
	h.place(map.players[2], 1900.0)
	h.step(SimMob.SIGHT_TICKS + 2)
	check_eq(m.target, 3, "Ann gone: turns on Bo, who hit it")
	check(bo != null, "Bo joined")

func test_a_lunge_hurts_and_each_player_once() -> void:
	var mv := _move(MonsterMove.Kind.LUNGE, 120.0)
	mv.distance = 80.0
	mv.speed = 5.0
	mv.power = 3.0
	var d := _with_move(mv)
	var map := h.field_with([ServerHarness.spawn(d)])
	var m := map.mobs[0]
	m.position.x = 600.0
	_ready_now(m)
	var p := _join(2, "Ann", 520.0)
	p.inv = 0
	h.step(1)
	check(m.moves.winding(), "winds up")
	h.place(p, 520.0)
	h.step(20) # strikes
	var hurt_by := 0
	for i in 30:
		h.place(p, 520.0)
		h.step(1)
		if p.character.health.hp < p.character.max_hp():
			hurt_by = p.character.max_hp() - p.character.health.hp
			break
	check_eq(hurt_by, 1, "the lunge takes one heart")
	check(m.position.x < 600.0, "it lunged forward")

func test_a_charge_dashes_along_the_platform() -> void:
	var mv := _move(MonsterMove.Kind.CHARGE, 300.0)
	mv.distance = 200.0
	mv.speed = 8.0
	var map := h.field_with([ServerHarness.spawn(_with_move(mv))])
	var m := map.mobs[0]
	m.position.x = 800.0
	_ready_now(m)
	_join(2, "Ann", 600.0)
	h.step(21)
	check(not m.moves.winding(), "done winding up")
	h.step(25)
	check_near(m.position.x, 600.0, "dashed 200 px toward her", 1.0)

func test_a_slam_misses_a_player_in_the_air() -> void:
	var mv := _move(MonsterMove.Kind.SLAM, 100.0)
	mv.radius = 120.0
	mv.power = 2.0
	var map := h.field_with([ServerHarness.spawn(_with_move(mv))])
	var m := map.mobs[0]
	m.position.x = 600.0
	_ready_now(m)
	var p := _join(2, "Ann", 690.0)
	h.step(1)
	check(m.moves.winding(), "winds up")
	h.place(p, 690.0, ServerHarness.GROUND - 40.0) # jumps
	h.step(20)
	check_eq(h.last(2, &"ev_mob_move").slice(1, 2), [&"slam"], "slams")
	check_eq(p.character.health.hp, p.character.max_hp(), "jumping over it dodges it")

func test_a_slam_hurts_a_player_on_the_ground_nearby() -> void:
	var mv := _move(MonsterMove.Kind.SLAM, 100.0)
	mv.radius = 120.0
	mv.power = 2.0
	var map := h.field_with([ServerHarness.spawn(_with_move(mv))])
	var m := map.mobs[0]
	m.position.x = 600.0
	_ready_now(m)
	var p := _join(2, "Ann", 690.0)
	h.step(21)
	check_eq(p.character.max_hp() - p.character.health.hp, 1, "one heart: only a boss's big hit takes two")

func test_a_swoop_dives_down_to_the_player() -> void:
	var mv := _move(MonsterMove.Kind.SWOOP, 250.0)
	mv.distance = 260.0
	mv.speed = 5.0
	var d := _with_move(mv)
	d.flying = true
	d.hover_height = 60.0
	var map := h.field_with([ServerHarness.spawn(d)])
	var m := map.mobs[0]
	m.position.x = 600.0
	_ready_now(m)
	var p := _join(2, "Ann", 450.0)
	var lowest := -INF
	var hurt := false
	for i in 120:
		h.place(p, 450.0)
		h.step(1)
		lowest = maxf(lowest, m.body_position().y)
		hurt = hurt or p.character.health.hp < p.character.max_hp()
	check(lowest > ServerHarness.GROUND - 20.0, "dived down to her feet (lowest body %s)" % lowest)
	check(hurt, "and hit her")
	check(not m.moves.busy(), "then climbed back up and rested")
	check_eq(m.hop, 0.0, "back at its height")

func test_a_hit_doesnt_knock_a_monster_out_of_its_move() -> void:
	var mv := _move(MonsterMove.Kind.CHARGE, 300.0)
	mv.distance = 200.0
	mv.speed = 8.0
	var map := h.field_with([ServerHarness.spawn(_with_move(mv))])
	var m := map.mobs[0]
	m.position.x = 800.0
	_ready_now(m)
	_join(2, "Ann", 600.0)
	h.step(5)
	m.hurt(1, 2)
	check_eq(m.kx, 0.0, "no knockback mid-move")
	h.step(16)
	check(m.moves.busy() and not m.moves.winding(), "charging anyway")

func _boss(moves: Array[MonsterMove]) -> MonsterDef:
	var d := ServerHarness.monster(&"test_boss", 100000)
	d.boss = true
	d.sight = 700.0
	d.moves = moves
	return d

## Moves the boss starts over `ticks`, in order.
func _moves_used(m: SimMob, ticks: int, want: int) -> Array[int]:
	var used: Array[int] = []
	for i in ticks:
		var before := m.moves.index
		h.step(1)
		if m.moves.index >= 0 and m.moves.index != before:
			used.append(m.moves.index)
		if used.size() >= want:
			break
	return used

func _pattern_boss() -> SimMob:
	var a := _move(MonsterMove.Kind.LUNGE, 400.0)
	a.distance = 10.0
	a.cooldown = 1
	var b := _move(MonsterMove.Kind.SLAM, 400.0)
	b.cooldown = 1
	var c := _move(MonsterMove.Kind.SHOT, 400.0)
	c.cooldown = 1
	var map := h.field_with([ServerHarness.spawn(_boss([a, b, c]))])
	var m := map.mobs[0]
	m.position.x = 600.0
	_ready_now(m)
	_join(2, "Ann", 900.0)
	return m

func test_a_boss_goes_through_its_moves_in_order() -> void:
	var m := _pattern_boss()
	var used := _moves_used(m, 2000, 7)
	check_eq(used.size(), 7, "used moves: %s" % [used])
	for i in range(1, used.size()):
		check_eq(used[i], (used[i - 1] + 1) % 3, "move %d comes next in the pattern (%s)" % [i, used])

func test_after_its_second_wind_a_boss_strings_two_moves_together() -> void:
	var m := _pattern_boss()
	m.health.damage(m.def.max_hp / 2 + 1)
	h.step(1)
	var gaps: Array[int] = []
	var idle := 0
	for i in 2000:
		var before := m.moves.index
		h.step(1)
		if not m.moves.busy():
			idle += 1
		elif m.moves.index != before and m.moves.index >= 0:
			gaps.append(idle)
			idle = 0
		if gaps.size() >= 7:
			break
	check_eq(gaps.size(), 7, "moves started (%s)" % [gaps])
	var quick := gaps.slice(1).filter(func(g: int) -> bool: return g <= MobMoves.COMBO_GAP_TICKS + 1)
	var slow := gaps.slice(1).filter(func(g: int) -> bool: return g >= MobMoves.BOSS_GAP_TICKS)
	check(quick.size() >= 2 and slow.size() >= 2, "every other move follows straight on (idle ticks before each: %s)" % [gaps])

func test_beating_a_boss_opens_the_way_home_for_everyone_there() -> void:
	var boss := _boss([])
	var field := ServerHarness.field_def()
	field.spawns.append(ServerHarness.spawn(boss))
	var home := PortalDef.new()
	home.x = 1800.0
	home.target_map = ServerHarness.TOWN
	home.target_x = 300.0
	home.one_way = true
	home.after_boss = boss
	field.portals.append(home)
	h.add_map(field)
	h.add_map(ServerHarness.town_def())
	var map := h.server.map_instance(ServerHarness.FIELD)
	var ann := _join(2, "Ann", 1800.0)
	var bo := _join(3, "Bo", 1800.0)
	check(home.locked(), "it waits on the boss")
	h.ask(2, &"req_portal")
	check_eq(ann.map.def.id, ServerHarness.FIELD, "shut while the boss stands")
	ServerHarness.no_cards(ann, boss)
	map.kill_mob(map.mobs[0], ann)
	h.step(1)
	check(home.open_to(ann.character) and home.open_to(bo.character), "open for both of them")
	check(not h.events(3, &"ev_character").is_empty(), "Bo's game is told")
	h.ask(3, &"req_portal")
	check_eq(bo.map.def.id, ServerHarness.TOWN, "Bo goes home through it")

func test_a_boss_beaten_untouched_counts() -> void:
	var boss := _boss([])
	var map := h.field_with([ServerHarness.spawn(boss)])
	var ann := _join(2, "Ann", 300.0)
	ServerHarness.no_cards(ann, boss)
	map.kill_mob(map.mobs[0], ann)
	check_eq(int(ann.character.counters.get(Counters.CLEAN_BOSSES, 0)), 1, "untouched")
	ann.inv = 0
	map.hurt_player(ann, boss, 0.0)
	map.mobs[0].health.reset(boss.max_hp)
	map.kill_mob(map.mobs[0], ann)
	check_eq(int(ann.character.counters.get(Counters.CLEAN_BOSSES, 0)), 1, "a hit spoils it")
	check_eq(int(ann.character.counters.get(Counters.BOSSES, 0)), 2, "both count as bosses")

func test_a_boss_goes_for_whoever_hurt_it_most() -> void:
	var map := h.field_with([ServerHarness.spawn(_boss([]))])
	var m := map.mobs[0]
	m.position.x = 600.0
	_join(2, "Ann", 650.0)
	_join(3, "Bo", 1000.0)
	h.step(1)
	check_eq(m.target, 2, "Ann is nearest")
	m.health.damage(50)
	m.hurt(1, 3)
	m.health.damage(5)
	m.hurt(1, 2)
	h.step(1)
	check_eq(m.target, 3, "Bo did the most damage")

func test_a_boss_aims_where_the_player_is_heading() -> void:
	var map := h.field_with([ServerHarness.spawn(_boss([_move(MonsterMove.Kind.SHOT, 600.0)]))])
	var m := map.mobs[0]
	m.position.x = 1000.0
	m.dir = -1
	var p := _join(2, "Ann", 500.0)
	_ready_now(m)
	m.moves.gap = 30
	for i in 50:
		h.place(p, 500.0 + i * 3.0) # running toward it
		h.step(1)
		if h.count(2, &"ev_mob_shot") > 0:
			break
	var shot: Array = h.last(2, &"ev_mob_shot")
	check(not shot.is_empty(), "it fired")
	if not shot.is_empty():
		check(shot[2] > p.position.x + 20.0, "aimed ahead of her (at %s, she's at %s)" % [shot[2], p.position.x])

func test_a_boss_leaps_to_the_players_platform() -> void:
	var field := ServerHarness.field_def()
	field.platforms.append(ServerHarness.platform(100, 450, 500))
	field.spawns.append(ServerHarness.spawn(_boss([])))
	h.add_map(field)
	var map := h.server.map_instance(ServerHarness.FIELD)
	var m := map.mobs[0]
	m.position.x = 700.0
	var p := _join(2, "Ann", 300.0)
	h.place(p, 300.0, 450.0)
	for i in 200:
		h.place(p, 300.0, 450.0)
		h.step(1)
		if m.plat.y == 450.0 and not m.moves.busy():
			break
	check_eq(m.plat.y, 450.0, "now on her platform")
	check_eq(m.position.y, 450.0, "standing on it")
	check_between(m.position.x, 100.0, 600.0, "within it")

func test_a_boss_gets_a_second_wind_at_half_hp() -> void:
	var map := h.field_with([ServerHarness.spawn(_boss([]))])
	var m := map.mobs[0]
	m.position.x = 1500.0
	_join(2, "Ann", 300.0)
	h.step(1)
	check(not m.enraged, "calm at full HP")
	m.health.damage(m.def.max_hp / 2 + 1)
	h.step(1)
	check(m.enraged, "angry below half")
	check(int(m.snapshot()[4]) & SnapshotFlags.MOB_ENRAGED != 0, "clients see it")
	check_eq(h.last(2, &"ev_mob_move").slice(1, 2), [&"rage"], "with a burst")

func test_a_blink_reappears_behind_the_player() -> void:
	var mv := _move(MonsterMove.Kind.BLINK, 500.0)
	mv.min_reach = 100.0
	mv.distance = 60.0
	mv.speed = 6.0
	var map := h.field_with([ServerHarness.spawn(_with_move(mv))])
	var m := map.mobs[0]
	m.position.x = 1000.0
	_ready_now(m)
	var p := _join(2, "Ann", 700.0)
	p.face = 1 # facing the monster
	var was_hidden := false
	for i in 60:
		h.place(p, 700.0)
		p.face = 1
		h.step(1)
		was_hidden = was_hidden or int(m.snapshot()[4]) & SnapshotFlags.MOB_HIDDEN != 0
		if was_hidden and not m.moves.hidden:
			break
	check(was_hidden, "vanished")
	check(m.position.x < 700.0, "came back behind her (at %s)" % m.position.x)

func _slime() -> MonsterDef:
	var small := ServerHarness.monster(&"small_slime", 1)
	var big := ServerHarness.monster(&"big_slime", 1)
	big.splits_into = small
	big.split_count = 2
	return big

func test_split_monsters_wait_asleep_until_their_parent_falls() -> void:
	var map := h.field_with([ServerHarness.spawn(_slime())])
	check_eq(map.mobs.size(), 3, "parent and two children")
	check(not map.mobs[0].dead, "parent out")
	check(map.mobs[1].asleep and map.mobs[1].dead, "first child asleep")
	check(map.mobs[2].asleep and map.mobs[2].dead, "second child asleep")
	check(map.mobs[1].parent == map.mobs[0], "child knows its parent")

func test_defeating_a_splitter_wakes_its_children_beside_it() -> void:
	var big := _slime()
	var map := h.field_with([ServerHarness.spawn(big)])
	map.mobs[0].position.x = 340.0
	var p := _join(2, "Ann", 300.0)
	ServerHarness.no_cards(p, big)
	ServerHarness.no_cards(p, big.splits_into)
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	check(map.mobs[0].dead, "parent defeated")
	for i in [1, 2]:
		var child := map.mobs[i]
		check(not child.dead and not child.asleep, "child %d awake" % i)
		check_eq(child.target, 2, "child %d angry at Ann" % i)
	check_eq(map.mobs[1].position.x, 325.0, "first child pops out left of the parent")
	check_eq(map.mobs[2].position.x, 355.0, "second child pops out right of the parent")

func test_split_children_dont_come_back_on_their_own() -> void:
	var big := _slime()
	var map := h.field_with([ServerHarness.spawn(big)])
	map.mobs[0].position.x = 1500.0
	_join(2, "Ann", 300.0)
	var child := map.mobs[1]
	child.wake(1500.0, 2)
	child.die()
	h.step(2000)
	check(child.dead and child.asleep, "still asleep long after")

func test_a_patrol_range_keeps_monsters_on_its_stretch_of_floor() -> void:
	var d := _walker(&"walker", 3.0)
	var s := ServerHarness.spawn(d, 4)
	s.patrol_from = 900.0
	s.patrol_to = 1400.0
	var map := h.field_with([s])
	var p := _join(2, "Ann", 300.0)
	var half := d.size.x / 2.0
	for m in map.mobs:
		check_between(m.position.x, 900.0 + half, 1400.0 - half, "spawns in range")
	# even chasing someone outside it, or knocked back, they stay in
	map.mobs[0].hurt(-1, 2)
	map.mobs[1].hurt(1, 2)
	for i in 600:
		h.place(p, 300.0)
		h.step(1)
		for m in map.mobs:
			if not check_between(m.position.x, 900.0 + half, 1400.0 - half, "tick %d: stays in range" % i):
				return

func test_a_spawn_without_a_patrol_range_uses_the_whole_platform() -> void:
	var plat := Platform.new(100, 400, 300)
	var a := SpawnDef.new().patrol_area(plat)
	check_eq(Vector3(a.x, a.y, a.w), Vector3(100, 400, 300), "whole platform")
	var s := SpawnDef.new()
	s.patrol_from = 50.0
	s.patrol_to = 250.0
	a = s.patrol_area(plat)
	check_eq(Vector3(a.x, a.y, a.w), Vector3(100, 400, 150), "clipped to the platform")
