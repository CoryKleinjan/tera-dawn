extends TestCase
## Attacks and skills against monsters on the server: what gets hit, damage, kills,
## cooldowns, Mana, buffs and monsters coming back.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var u := UnitHelpers.new()
var mob_def: MonsterDef
var map: MapInstance
var p: SimPlayer

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()
	u.cleanup()

## A field with `count` test monsters of `hp` HP, all at `x`, and Ann at 300 facing right.
func _setup(hp := 1, count := 1, x := 340.0) -> void:
	mob_def = ServerHarness.monster(&"test_mob", hp)
	map = h.field_with([ServerHarness.spawn(mob_def, count)])
	for m in map.mobs:
		m.position.x = x
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	ServerHarness.no_cards(p, mob_def)

## A melee skill made for the test that costs Mana and reaches past a plain swing.
func _bash() -> SkillDef:
	var s := u.skill(&"t_bash")
	s.mp_cost = 5
	s.reach = 160.0
	return s

func _attack(peer := 2, skill := &"basic_attack") -> void:
	var who: SimPlayer = h.server.sessions[peer]
	h.ask(peer, &"req_skill", [skill, who.position, who.face])

func test_basic_attack_damages_the_monster_in_front() -> void:
	_setup(1000)
	_attack()
	var ev := h.last(2, &"ev_skill")
	check_eq(ev.slice(0, 2), [2, &"basic_attack"], "who and what")
	var lines: Array = ev[5]
	check_eq(lines.size(), 1, "one monster hit")
	var dmg: int = lines[0][1][0][0]
	check_eq(lines[0][0], 0, "monster index")
	check(dmg > 0, "it did damage")
	check_eq(map.mobs[0].health.hp, 1000 - dmg, "HP lost matches the damage shown")

func test_damage_is_within_the_characters_range() -> void:
	_setup(100000)
	var r := p.character.damage_range()
	for i in 10:
		map.mobs[0].position.x = 340.0
		_attack()
		var hit: Array = h.last(2, &"ev_skill")[5][0][1][0]
		var low := r.x if hit[1] == "hit" else roundi(r.x * Combat.CRIT_MULTIPLIER)
		var high := r.y if hit[1] == "hit" else roundi(r.y * Combat.CRIT_MULTIPLIER)
		check_between(hit[0], low, high, "hit %d (%s)" % [i, hit[1]])
		h.step(p.cooldown)

func test_monster_behind_you_is_not_hit() -> void:
	_setup(1000, 1, 240.0)
	_attack()
	check_eq(h.last(2, &"ev_skill")[5], [], "nothing hit")
	check_eq(map.mobs[0].health.hp, 1000, "full HP")

func test_monster_out_of_reach_is_not_hit() -> void:
	_setup(1000, 1, 300.0 + 78.0 + 18.0 + 1.0)
	_attack()
	check_eq(h.last(2, &"ev_skill")[5], [], "nothing hit")

func test_plain_attack_hits_only_the_nearest_monster() -> void:
	_setup(1000, 2)
	map.mobs[0].position.x = 360.0
	map.mobs[1].position.x = 330.0
	_attack()
	var lines: Array = h.last(2, &"ev_skill")[5]
	check_eq(lines.size(), 1, "one target")
	check_eq(lines[0][0], 1, "the nearer monster")
	check_eq(map.mobs[0].health.hp, 1000, "the farther one is untouched")

func test_everyone_on_the_map_sees_the_attack() -> void:
	_setup(1000)
	h.join(3, "Bob", ServerHarness.FIELD, 900.0)
	h.join(4, "Cat", ServerHarness.TOWN)
	_attack()
	check_eq(h.count(3, &"ev_skill"), 1, "Bob on the same map sees it")
	check_eq(h.count(4, &"ev_skill"), 0, "Cat in town doesn't")

func test_a_hit_monster_turns_on_its_attacker() -> void:
	_setup(1000)
	_attack()
	var m := map.mobs[0]
	check_eq(m.target, 2, "target")
	check_eq(m.aggro, 600, "angry")
	check_eq(m.show_hp, SimMob.SHOW_HP_TICKS, "HP bar shown")

func test_killing_a_monster_announces_it() -> void:
	_setup(1)
	h.join(3, "Bob", ServerHarness.FIELD, 900.0)
	_attack()
	check(map.mobs[0].dead, "dead")
	check_eq(h.last(2, &"ev_mob_died"), [0], "killer told")
	check_eq(h.last(3, &"ev_mob_died"), [0], "others on the map told")

func test_attacks_wait_for_the_cooldown() -> void:
	_setup(100000)
	var cd := Content.skill(&"basic_attack").cooldown
	_attack()
	_attack()
	check_eq(h.count(2, &"ev_skill"), 1, "second attack too soon")
	h.step(cd - TDServer.COOLDOWN_SLACK - 1)
	_attack()
	check_eq(h.count(2, &"ev_skill"), 1, "still too soon one tick before the slack")
	h.step(1)
	_attack()
	check_eq(h.count(2, &"ev_skill"), 2, "allowed within the slack")

func test_dead_monsters_are_not_hit() -> void:
	_setup(1)
	_attack()
	h.step(30)
	_attack()
	check_eq(h.last(2, &"ev_skill")[5], [], "nothing to hit")

func test_monster_respawns_with_full_hp_after_its_timer() -> void:
	_setup(5)
	var m := map.mobs[0]
	m.health.damage(4)
	_attack()
	check(m.dead, "defeated")
	# 40 ticks of dying, then respawn_ticks (100)
	h.step(139)
	check(m.dead, "still gone one tick early")
	h.step(1)
	check(not m.dead, "back")
	check_eq(m.health.hp, 5, "full HP")
	check_eq(m.target, 0, "forgot who beat it")

func test_leaving_and_coming_back_brings_the_monsters_back_at_full_hp() -> void:
	_setup(5)
	var m := map.mobs[0]
	m.health.damage(4)
	_attack()
	h.move_to(p, ServerHarness.TOWN)
	check(not h.server.maps.has(ServerHarness.FIELD), "nobody on the field, so it's dropped")
	h.move_to(p, ServerHarness.FIELD)
	var fresh: MapInstance = h.server.maps[ServerHarness.FIELD]
	check(fresh != map, "the field loads fresh")
	check(not fresh.mobs[0].dead, "back")
	check_eq(fresh.mobs[0].health.hp, 5, "full HP")

func test_in_co_op_a_map_resets_only_once_everyone_has_left() -> void:
	_setup(5)
	var bob := h.join(3, "Bob", ServerHarness.FIELD, 300.0)
	var m := map.mobs[0]
	m.health.damage(4)
	_attack()
	h.move_to(p, ServerHarness.TOWN)
	h.move_to(p, ServerHarness.FIELD)
	check(h.server.maps[ServerHarness.FIELD] == map, "Bob stayed, so the field kept going")
	check(m.dead, "and the monster is still gone")
	h.move_to(p, ServerHarness.TOWN)
	h.move_to(bob, ServerHarness.TOWN)
	h.move_to(p, ServerHarness.FIELD)
	check(not h.server.maps[ServerHarness.FIELD].mobs[0].dead, "everyone left, so it's back")

func test_skills_you_dont_know_are_refused() -> void:
	_setup(1000)
	var mp := p.character.mp
	_attack(2, _bash().id)
	check_eq(h.count(2, &"ev_skill"), 0, "not used")
	check(h.told(2, "You don't know that skill."), "told why")
	check_eq(p.character.mp, mp, "no Mana spent")

func test_unknown_skill_ids_are_ignored() -> void:
	_setup(1000)
	_attack(2, &"no_such_skill")
	check_eq(h.api.sent.size(), 0, "nothing happens")

func test_a_known_skill_spends_its_mp_and_reaches_further() -> void:
	_setup(1000, 1, 400.0)
	var c := p.character
	var bash := _bash()
	c.skills.learned[bash.id] = 1
	c.mp = c.max_mp()
	var mp := c.mp
	_attack(2, bash.id)
	check_eq(c.mp, mp - bash.mp_at(1), "Mana paid")
	check_eq((h.last(2, &"ev_skill")[5] as Array).size(), 1, "hit the monster 100 px away, past a plain swing")

func test_not_enough_mp_refuses_the_skill() -> void:
	_setup(1000)
	var bash := _bash()
	p.character.skills.learned[bash.id] = 1
	p.character.mp = 2
	_attack(2, bash.id)
	check_eq(h.count(2, &"ev_skill"), 0, "not used")
	check(h.told(2, "Not enough Mana for T Bash."), "told why")
	check_eq(p.character.mp, 2, "Mana kept")

func test_a_buff_raises_stats_until_it_wears_off() -> void:
	_setup()
	var c := p.character
	var skill := u.skill(&"t_step", SkillDef.Kind.BUFF)
	skill.animation = SkillDef.SPELL
	skill.duration = 2.0
	skill.stats = UnitHelpers.stats({"speed": 10})
	c.skills.learned[skill.id] = 1
	var speed := c.stats.speed
	_attack(2, skill.id)
	check_eq(c.stats.speed, speed + skill.stats_at(1).speed, "faster")
	check_eq(h.last(2, &"ev_skill").slice(0, 2), [2, skill.id], "shown")
	h.step(skill.duration_ticks(1) - 1)
	check(c.skills.buffs.has(skill.id), "still running one tick before the end")
	h.step(1)
	check(not c.skills.buffs.has(skill.id), "ended")
	check_eq(c.stats.speed, speed, "speed back")
	check(h.told(2, "T Step wore off."), "told")

func test_a_fainted_player_cannot_attack() -> void:
	_setup(1000)
	p.faint_t = 50
	_attack()
	check_eq(h.count(2, &"ev_skill"), 0, "no attack")

func test_kills_are_written_in_the_monster_book() -> void:
	_setup(1)
	_attack()
	check_eq(p.character.book.kills(mob_def), 1, "kill recorded")

func test_boss_kills_are_counted() -> void:
	_setup(1)
	mob_def.boss = true
	_attack()
	check_eq(int(p.character.counters.get(Counters.BOSSES, 0)), 1, "boss tally")
