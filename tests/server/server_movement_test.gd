extends TestCase
## Movement reports: the server accepts moves a player could make and puts them back
## (ev_place) when a report is impossible.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var p: SimPlayer

func before_each() -> void:
	h = ServerHarness.new()
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)

func after_each() -> void:
	h.close()

func test_a_short_move_is_accepted() -> void:
	h.ask(2, &"req_move", [Vector2(340, 600), 1, &"walk"])
	check_eq(p.position, Vector2(340, 600), "moved")
	check_eq(p.animation, &"walk", "animation passed on")
	check_eq(h.count(2, &"ev_place"), 0, "not corrected")

func test_a_teleport_is_refused_and_corrected() -> void:
	h.ask(2, &"req_move", [Vector2(1200, 600), 1, &"walk"])
	check_eq(p.position, Vector2(300, 600), "position unchanged")
	check_eq(h.last(2, &"ev_place"), [300.0, 600.0], "put back where the server has them")

func test_allowed_distance_grows_with_ticks_since_the_last_report() -> void:
	# one tick allows MAX_STEP + 40 = 56 pixels; 100 needs four ticks
	h.ask(2, &"req_move", [Vector2(400, 600), 1, &"walk"])
	check_eq(p.position.x, 300.0, "100 px in one tick is refused")
	h.step(4)
	h.ask(2, &"req_move", [Vector2(400, 600), 1, &"walk"])
	check_eq(p.position.x, 400.0, "100 px after four ticks is fine")

func test_exactly_the_limit_is_accepted() -> void:
	h.ask(2, &"req_move", [Vector2(300 + SimPlayer.MAX_STEP + 40.0, 600), 1, &"walk"])
	check_eq(p.position.x, 356.0, "56 px in one tick")

func test_moves_are_clamped_to_the_map() -> void:
	h.place(p, 1990.0)
	h.ask(2, &"req_move", [Vector2(2030, 600), 1, &"walk"])
	check_eq(p.position.x, 2000.0, "kept inside the map's width")

func test_facing_is_either_left_or_right() -> void:
	h.ask(2, &"req_move", [Vector2(300, 600), -7, &"idle"])
	check_eq(p.face, -1, "negative faces left")
	h.ask(2, &"req_move", [Vector2(300, 600), 0, &"idle"])
	check_eq(p.face, 1, "zero faces right")

func test_a_fainted_player_cannot_move() -> void:
	p.faint_t = 10
	h.ask(2, &"req_move", [Vector2(310, 600), 1, &"walk"])
	check_eq(p.position.x, 300.0, "lying still")
	check_eq(h.count(2, &"ev_place"), 0, "no correction while fainted")

func test_unknown_peers_are_ignored() -> void:
	h.ask(9, &"req_move", [Vector2(310, 600), 1, &"walk"])
	check_eq(h.api.sent.size(), 0, "nothing happens")
