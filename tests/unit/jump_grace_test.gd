extends TestCase
## JumpGrace: jumps on the ground, coyote time after walking off a ledge (but not after a
## jump or a knockback), and jump presses buffered for a few ticks before landing.

var g: JumpGrace

func before_each() -> void:
	g = JumpGrace.new()

## Runs `n` ticks with the feet on the ground or not.
func _ticks(n: int, on_ground: bool) -> void:
	for i in n:
		g.step(on_ground)

func test_no_press_no_jump() -> void:
	_ticks(3, true)
	check(not g.can_jump(true), "standing still")

func test_a_press_on_the_ground_jumps() -> void:
	_ticks(3, true)
	g.press()
	check(g.can_jump(true), "jumps at once")

func test_coyote_time_after_walking_off_a_ledge() -> void:
	_ticks(3, true)
	_ticks(JumpGrace.COYOTE_TICKS, false)
	g.press()
	check(g.can_jump(false), "%d ticks off the ledge still jumps" % JumpGrace.COYOTE_TICKS)

func test_coyote_time_runs_out() -> void:
	_ticks(3, true)
	_ticks(JumpGrace.COYOTE_TICKS + 1, false)
	g.press()
	check(not g.can_jump(false), "one tick later is too late")

func test_no_coyote_time_after_a_jump() -> void:
	_ticks(3, true)
	g.press()
	check(g.can_jump(true), "jumps")
	g.cancel()
	g.step(false)
	g.press()
	check(not g.can_jump(false), "no second jump in the air")

func test_no_coyote_time_after_a_knockback() -> void:
	_ticks(3, true)
	g.cancel()
	g.step(false)
	g.press()
	check(not g.can_jump(false), "knocked off the ground")

func test_a_press_before_landing_jumps_on_landing() -> void:
	_ticks(20, false)
	g.press()
	check(not g.can_jump(false), "not in the air")
	_ticks(JumpGrace.BUFFER_TICKS, false)
	check(g.can_jump(true), "goes off on landing %d ticks later" % JumpGrace.BUFFER_TICKS)

func test_a_press_too_long_before_landing_is_dropped() -> void:
	_ticks(20, false)
	g.press()
	_ticks(JumpGrace.BUFFER_TICKS + 1, false)
	check(not g.can_jump(true), "forgotten by landing")

func test_a_buffered_press_jumps_only_once() -> void:
	_ticks(20, false)
	g.press()
	g.step(false)
	check(g.can_jump(true), "jumps on landing")
	g.cancel()
	g.step(true)
	check(not g.can_jump(true), "the press is spent")
