extends TestCase
## Hearts and Mana through the server (Cory Oct 19): hitting monsters fills Mana, holding the
## heal key spends it on a heart, and a boss's big hit takes two hearts.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var map: MapInstance
var p: SimPlayer
var c: Character

func before_each() -> void:
	h = ServerHarness.new()
	var dummy := ServerHarness.monster(&"test_mob", 100000)
	map = h.field_with([ServerHarness.spawn(dummy, 2)])
	for m in map.mobs:
		m.position.x = 340.0
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	c = p.character
	ServerHarness.no_cards(p, dummy)

func after_each() -> void:
	h.close()

func _swing() -> void:
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])

func test_hitting_monsters_fills_mana_for_each_one_struck() -> void:
	check_eq(c.mp, 0, "an empty orb to start")
	_swing()
	var struck: int = (h.last(2, &"ev_skill")[5] as Array).size()
	check(struck > 0, "struck")
	check_eq(c.mp, CharacterStats.MANA_PER_HIT * struck, "Mana for each monster struck")
	check(p.dirty_vitals, "sent to the client")

func test_a_swing_at_nothing_fills_no_mana() -> void:
	h.place(p, 900.0)
	_swing()
	check_eq(c.mp, 0, "nothing struck")

func test_mana_stops_at_a_full_orb() -> void:
	c.mp = c.max_mp() - 1
	_swing()
	check_eq(c.mp, c.max_mp(), "full")

func test_healing_spends_mana_on_a_heart() -> void:
	c.health.set_hp(2)
	c.mp = CharacterStats.HEAL_COST
	h.ask(2, &"req_heal")
	check_eq(c.health.hp, 3, "a heart back")
	check_eq(c.mp, 0, "paid")
	check_eq(h.last(2, &"ev_effect")[0], EffectDef.HEAL, "a glow everyone sees")

func test_heals_wait_for_each_other() -> void:
	c.health.set_hp(1)
	c.mp = c.max_mp()
	h.ask(2, &"req_heal")
	h.ask(2, &"req_heal")
	check_eq(c.health.hp, 2, "the second came too soon")
	h.step(SimPlayer.HEAL_TICKS)
	h.ask(2, &"req_heal")
	check_eq(c.health.hp, 3, "healed again")

func test_no_heal_without_the_mana_or_a_missing_heart() -> void:
	c.health.set_hp(2)
	c.mp = CharacterStats.HEAL_COST - 1
	h.ask(2, &"req_heal")
	check_eq(c.health.hp, 2, "not enough Mana")
	c.health.set_hp(c.max_hp())
	c.mp = c.max_mp()
	h.ask(2, &"req_heal")
	check_eq(c.mp, c.max_mp(), "nothing to heal, nothing spent")

func test_a_bosss_big_move_takes_two_hearts() -> void:
	var boss := ServerHarness.monster(&"test_boss", 100000)
	boss.boss = true
	map.hurt_player(p, boss, 400.0, Combat.BIG_HIT_POWER)
	check_eq(c.health.hp, c.max_hp() - 2, "two hearts")
	p.inv = 0
	map.hurt_player(p, boss, 400.0)
	check_eq(c.health.hp, c.max_hp() - 3, "its touch takes one")
