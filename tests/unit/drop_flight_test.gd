extends TestCase
## DropFlight: drops land the same way from the same start (server and clients agree),
## land on the floor at their landing x, stop once resting, and survive to_array/from_array.

func _fly(f: DropFlight, max_steps := 1000) -> int:
	var n := 0
	while not f.resting() and n < max_steps:
		f.step()
		n += 1
	return n

func test_same_seed_same_flight() -> void:
	seed(31)
	var a := DropFlight.create(Vector2(100, 300), 400.0)
	seed(31)
	var b := DropFlight.create(Vector2(100, 300), 400.0)
	check_eq(a.vel, b.vel, "same start velocity")
	for i in 60:
		a.step()
		b.step()
		check_eq(a.position, b.position, "same position at step %d" % i)

func test_same_inputs_land_identically() -> void:
	var a := DropFlight.from_array([50.0, 200.0, 1.2, -5.0, 380.0, NAN])
	var b := DropFlight.from_array([50.0, 200.0, 1.2, -5.0, 380.0, NAN])
	check_eq(_fly(a), _fly(b), "same number of steps")
	check_eq(a.position, b.position, "same landing spot")

func test_start_velocity_ranges() -> void:
	for i in 200:
		var f := DropFlight.create(Vector2.ZERO, 100.0)
		check_between(f.vel.x, -1.6, 1.6, "sideways")
		check_between(f.vel.y, -6.0, -4.0, "upward pop")

func test_not_resting_at_start() -> void:
	var f := DropFlight.create(Vector2(0, 100), 100.0)
	check(not f.resting(), "pops up first even when starting on the floor")

func test_lands_on_floor_at_landing_x() -> void:
	var f := DropFlight.create(Vector2(100, 300), 400.0, 160.0)
	var steps := _fly(f)
	check(steps < 1000, "lands")
	check(f.resting(), "resting")
	check_eq(f.position, Vector2(160, 400), "exactly at landing x on the floor")
	check_eq(f.vel, Vector2.ZERO, "stopped")

func test_without_landing_x_drifts_with_velocity() -> void:
	var f := DropFlight.from_array([100.0, 300.0, 1.0, -5.0, 300.0, NAN])
	var steps := _fly(f)
	check_near(f.position.x, 100.0 + steps, "moved 1 px a step")
	check_eq(f.position.y, 300.0, "on the floor")

func test_flight_steps_are_exact() -> void:
	# vy: -5 + 0.45 = -4.55 → y 295.45; then -4.10 → 291.35
	var f := DropFlight.from_array([0.0, 300.0, 0.0, -5.0, 300.0, NAN])
	f.step()
	check_near(f.position.y, 295.45, "first step")
	check_near(f.vel.y, -4.55, "gravity")
	f.step()
	check_near(f.position.y, 291.35, "second step")

func test_falls_from_above_to_lower_floor() -> void:
	var f := DropFlight.from_array([0.0, 0.0, 0.0, 0.0, 500.0, NAN])
	_fly(f)
	check_eq(f.position.y, 500.0, "lands on the far floor, not through it")

func test_step_after_resting_does_nothing() -> void:
	var f := DropFlight.create(Vector2(10, 50), 90.0, 20.0)
	_fly(f)
	var p := f.position
	for i in 10:
		f.step()
	check_eq(f.position, p, "stays put")

func test_array_round_trip_continues_identically() -> void:
	seed(5)
	var a := DropFlight.create(Vector2(70, 120), 260.0, 90.0)
	for i in 5:
		a.step()
	var b := DropFlight.from_array(a.to_array())
	check_eq(b.position, a.position, "position")
	check_eq(b.vel, a.vel, "velocity")
	check_eq(b.floor_y, a.floor_y, "floor")
	_fly(a)
	_fly(b)
	check_eq(b.position, a.position, "land in the same place")

func test_array_keeps_nan_landing() -> void:
	var f := DropFlight.create(Vector2.ZERO, 10.0)
	var back := DropFlight.from_array(f.to_array())
	check(is_nan(back.land_x), "no landing x")
