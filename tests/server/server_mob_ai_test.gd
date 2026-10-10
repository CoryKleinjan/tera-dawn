extends TestCase
## Monster behaviour run by the server: chasing, standing still, touching players, shooting
## and splitting into smaller monsters.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()

## A monster that walks at `speed` and never dodges touches (level 50: no player dodge).
func _walker(id := &"walker", speed := 1.0) -> MonsterDef:
	var d := ServerHarness.monster(id, 100000, 1)
	d.speed = speed
	return d

func test_a_hurt_monster_chases_its_attacker_on_its_platform() -> void:
	var d := _walker()
	var map := h.field_with([ServerHarness.spawn(d)])
	var m := map.mobs[0]
	m.position.x = 600.0
	var p := h.join(2, "Ann", ServerHarness.FIELD, 300.0)
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
	var p := h.join(2, "Ann", ServerHarness.FIELD, 300.0)
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
	h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	m.hurt(1, 2)
	h.step(600)
	check_eq(m.aggro, 0, "calmed down after 600 ticks")

func test_leaving_the_map_ends_the_chase() -> void:
	var map := h.field_with([ServerHarness.spawn(_walker())])
	var m := map.mobs[0]
	m.position.x = 1500.0
	var p := h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	m.hurt(1, 2)
	h.move_to(p, ServerHarness.TOWN)
	check_eq(m.aggro, 0, "forgot Ann")

func test_stationary_monsters_never_move_even_when_hit() -> void:
	var d := _walker(&"turret", 2.0)
	d.stationary = true
	var map := h.field_with([ServerHarness.spawn(d)])
	var m := map.mobs[0]
	m.position.x = 340.0
	var p := h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	ServerHarness.no_cards(p, d)
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	check(m.health.hp < d.max_hp, "it was hit")
	h.step(120)
	check_eq(m.position.x, 340.0, "never knocked back or walked")

func test_touching_a_monster_hurts_then_gives_invincibility() -> void:
	var d := ServerHarness.monster(&"toucher", 100000, 1)
	d.level = 50 # far above the player: they can't dodge, and the hit is exactly 1
	var map := h.field_with([ServerHarness.spawn(d)])
	map.mobs[0].position.x = 300.0
	var p := h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	var full := p.character.health.hp
	h.step(1)
	check_eq(p.character.health.hp, full - 1, "one damage on touch")
	check_eq(h.last(2, &"ev_hurt"), [300.0], "knocked back from the monster")
	check_eq(h.last(2, &"ev_number").slice(2), [1, "taken"], "damage number")
	check_eq(p.inv, SimPlayer.HURT_INV, "invincible for a while")
	h.step(SimPlayer.HURT_INV - 1)
	check_eq(p.character.health.hp, full - 1, "no more damage while invincible")
	h.step(1)
	check_eq(p.character.health.hp, full - 2, "hurt again once it wears off")

func test_a_monster_far_away_doesnt_hurt() -> void:
	var d := ServerHarness.monster(&"toucher", 100000, 1)
	d.level = 50
	var map := h.field_with([ServerHarness.spawn(d)])
	map.mobs[0].position.x = 600.0
	var p := h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	h.step(60)
	check_eq(p.character.health.hp, p.character.max_hp(), "untouched")

func _shooter() -> MonsterDef:
	var d := ServerHarness.monster(&"shooter", 100000, 1)
	d.level = 50
	d.stationary = true
	d.aggressive = true
	d.shot = load("res://data/projectiles/mob_bolt.tres")
	d.shot_range = 320.0
	d.shot_cooldown = 150
	return d

func test_an_aggressive_shooter_fires_at_a_player_in_range() -> void:
	var map := h.field_with([ServerHarness.spawn(_shooter())])
	var m := map.mobs[0]
	m.position.x = 500.0
	m.shot_t = 1
	var p := h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	var full := p.character.health.hp
	h.step(1)
	check_eq(h.last(2, &"ev_mob_shot"), [0, 300.0, 570.0], "fires at where Ann stands")
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
	m.shot_t = 1
	var p := h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	h.step(1)
	h.place(p, 240.0)
	h.step(int(m.shots[0][1]))
	check(m.shots.is_empty(), "the shot landed")
	check_eq(p.character.health.hp, p.character.max_hp(), "missed her")

func test_a_shooter_winds_up_before_it_fires_only_with_someone_to_aim_at() -> void:
	var map := h.field_with([ServerHarness.spawn(_shooter())])
	var m := map.mobs[0]
	m.position.x = 500.0
	m.shot_t = SimMob.WINDUP_TICKS + 5
	h.step(1)
	check(int(m.snapshot()[4]) & SnapshotFlags.MOB_WINDUP == 0, "nobody in range: no wind-up")
	h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	h.step(3)
	check(int(m.snapshot()[4]) & SnapshotFlags.MOB_WINDUP == 0, "not yet: the shot is still a while off")
	h.step(2)
	check(int(m.snapshot()[4]) & SnapshotFlags.MOB_WINDUP != 0, "winding up for the last ticks before the shot")
	h.step(SimMob.WINDUP_TICKS)
	check_eq(h.count(2, &"ev_mob_shot"), 1, "then it fires")
	check(int(m.snapshot()[4]) & SnapshotFlags.MOB_WINDUP == 0, "and the wind-up ends")

func test_shooters_ignore_players_out_of_range() -> void:
	var map := h.field_with([ServerHarness.spawn(_shooter())])
	var m := map.mobs[0]
	m.position.x = 1000.0
	m.shot_t = 1
	h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	h.step(30)
	check_eq(h.count(2, &"ev_mob_shot"), 0, "no shot at 700 px")

func test_a_calm_shooter_only_fires_at_whoever_hit_it() -> void:
	var d := _shooter()
	d.aggressive = false
	var map := h.field_with([ServerHarness.spawn(d)])
	var m := map.mobs[0]
	m.position.x = 500.0
	m.shot_t = 1
	h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	h.step(30)
	check_eq(h.count(2, &"ev_mob_shot"), 0, "leaves Ann alone")
	m.hurt(1, 2)
	m.shot_t = 1
	h.step(15)
	check_eq(h.count(2, &"ev_mob_shot"), 1, "shoots back once hit")

func _slime() -> MonsterDef:
	var small := ServerHarness.monster(&"small_slime", 1, 2)
	var big := ServerHarness.monster(&"big_slime", 1, 10)
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
	var p := h.join(2, "Ann", ServerHarness.FIELD, 300.0)
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
	h.join(2, "Ann", ServerHarness.FIELD, 300.0)
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
	var p := h.join(2, "Ann", ServerHarness.FIELD, 300.0)
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
