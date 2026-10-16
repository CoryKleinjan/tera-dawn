extends TestCase
## Fainting: a monster's blow that takes the last HP, the Dawn Essence it costs, lying still, and
## waking up in town with half HP and MP and a moment of invincibility.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var map: MapInstance
var p: SimPlayer
var c: Character

func before_each() -> void:
	h = ServerHarness.new()
	var brute := ServerHarness.monster(&"brute", 100000, 1)
	brute.attack = 100000
	map = h.field_with([ServerHarness.spawn(brute)])
	map.mobs[0].position.x = 300.0
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	c = p.character
	c.base.luck = 0 # no avoid: the blow can't be dodged
	c.recalc()
	c.essence = 15

func after_each() -> void:
	h.close()

func test_losing_all_hp_faints_and_costs_a_tenth_of_your_essence() -> void:
	h.step(1)
	check(p.fainted(), "fainted")
	check_eq(c.health.hp, 0, "no HP")
	check_eq(c.essence, 14, "lost 10% (rounded down)")
	check_eq(h.count(2, &"ev_fainted"), 1, "told the client")
	check(h.told(2, "You fainted and lost 1 Dawn Essence."), "told the player")

func test_fainted_players_take_no_more_hits() -> void:
	h.step(1)
	h.step(20)
	check_eq(h.count(2, &"ev_hurt"), 1, "hurt once")
	check_eq(c.essence, 14, "lost essence once")

func test_you_wake_up_in_the_maps_town_after_lying_still() -> void:
	h.step(1)
	h.step(SimPlayer.FAINT_TICKS - 1)
	check(p.fainted(), "still lying there one tick early")
	check_eq(p.map.def.id, ServerHarness.FIELD, "still on the field")
	h.step(1)
	check(not p.fainted(), "awake")
	check_eq(p.map.def.id, ServerHarness.TOWN, "in the field's town")
	check_eq(h.last(2, &"ev_enter_map").slice(0, 2), [ServerHarness.TOWN, 500.0], "at the town's start")

func test_waking_up_gives_half_hp_and_mp_and_invincibility() -> void:
	h.step(SimPlayer.FAINT_TICKS + 1)
	check_eq(c.health.hp, ceili(c.max_hp() / 2.0), "half HP, rounded up")
	check_eq(c.mp, ceili(c.max_mp() / 2.0), "half MP, rounded up")
	check_eq(p.inv, 120, "a moment of invincibility")

func test_fainting_in_a_town_wakes_you_in_that_town() -> void:
	var town := h.server.map_instance(ServerHarness.TOWN)
	h.move_to(p, ServerHarness.TOWN, 900.0)
	c.health.set_hp(0)
	p.faint_t = 1
	h.step(1)
	check(p.map == town, "same town")
	check_eq(p.position.x, 500.0, "at its start")

func test_a_map_without_a_return_map_sends_you_to_the_start_map() -> void:
	var wild := ServerHarness.field_def(&"test_wild")
	wild.return_map = &""
	h.add_map(wild)
	h.move_to(p, &"test_wild")
	c.health.set_hp(0)
	p.faint_t = 1
	h.step(1)
	check_eq(p.map.def.id, Character.START_MAP, "back at the start")

func test_leaving_while_fainted_wakes_you_in_town() -> void:
	h.step(1)
	check(p.fainted(), "fainted")
	h.ask(2, &"req_leave_character")
	var saved := h.saved("Ann")
	check_eq(saved.map_id, ServerHarness.TOWN, "saved in the field's town")
	check_eq(saved.health.hp, ceili(saved.max_hp() / 2.0), "with half HP")
	h.play(2, "Ann")
	check_eq(h.server.player_of(2).map.def.id, ServerHarness.TOWN, "and comes back there")
	check(not h.server.player_of(2).fainted(), "awake")

func test_disconnecting_while_fainted_wakes_you_in_town() -> void:
	h.step(1)
	h.leave(2)
	check_eq(h.saved("Ann").map_id, ServerHarness.TOWN, "saved in the field's town")
