extends TestCase
## Rest spots, the Hollow Knight way (MapDef.rest_spots): sitting by one's bench fills HP and
## MP and makes it where you wake after fainting in its region, instead of in town. It's saved
## with the character.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")
const ROOM := &"test_rest_room"
const BENCH := 800

var h: ServerHarness
var p: SimPlayer
var c: Character

func before_each() -> void:
	h = ServerHarness.new()
	var m := ServerHarness.field_def(ROOM)
	m.rest_spots.append(Vector2i(BENCH, 0))
	h.add_map(m)
	p = h.join(2, "Ann", ROOM, BENCH + 40.0)
	c = p.character

func after_each() -> void:
	h.close()

func _faint() -> void:
	c.health.set_hp(0)
	p.faint_t = 1
	h.step(1)

func _rest() -> void:
	h.ask(2, &"req_sit", [true])
	h.ask(2, &"req_sit", [false])

func test_sitting_by_a_bench_rests_there() -> void:
	c.health.set_hp(1)
	c.mp = 0
	h.ask(2, &"req_sit", [true])
	check(p.sitting, "sat down on the ground")
	check_eq(c.health.hp, c.max_hp(), "HP filled")
	check_eq(c.mp, c.max_mp(), "MP filled")
	check_eq([c.rest_map, c.rest_spot], [ROOM, 0], "rested here")
	check(h.told(2, "You rested. You'll wake here if you faint nearby."), "told the player")

func test_sitting_away_from_a_bench_is_just_sitting() -> void:
	h.place(p, BENCH + MapLayout.REST_REACH + 20.0)
	c.health.set_hp(1)
	h.ask(2, &"req_sit", [true])
	check(p.sitting, "sat down")
	check_eq(c.health.hp, 1, "no rest")
	check_eq(c.rest_map, &"", "no rest spot")

func test_fainting_after_resting_wakes_you_at_the_bench() -> void:
	_rest()
	h.move_to(p, ServerHarness.FIELD)
	_faint()
	check_eq(h.last(2, &"ev_enter_map").slice(0, 2), [ROOM, float(BENCH)], "woke at the bench")
	check_eq(c.health.hp, ceili(c.max_hp() / 2.0), "with half HP, as in town")

func test_fainting_in_another_region_wakes_you_in_town() -> void:
	_rest()
	var far := ServerHarness.field_def(&"test_far_field")
	far.region = &"test_far"
	h.add_map(far)
	h.move_to(p, &"test_far_field")
	_faint()
	check_eq(p.map.def.id, ServerHarness.TOWN, "woke in that field's town")

func test_leaving_while_fainted_comes_back_at_the_bench_room() -> void:
	_rest()
	h.move_to(p, ServerHarness.FIELD)
	c.health.set_hp(0)
	p.faint_t = 100
	h.leave(2)
	var saved := h.saved("Ann")
	check_eq(saved.map_id, ROOM, "saved in the bench's room")
	check_eq([saved.rest_map, saved.rest_spot], [ROOM, 0], "with the rest spot")
