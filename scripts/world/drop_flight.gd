class_name DropFlight
extends RefCounted
## How a dropped item flies out and lands. The server and every client run the same
## steps from the same start, so drops land in the same place everywhere.

var position := Vector2.ZERO
var vel := Vector2.ZERO
var floor_y := 0.0
## Where it lands; NAN means wherever it flies.
var land_x := NAN

static func create(from: Vector2, ground: float, landing_x := NAN) -> DropFlight:
	var f := DropFlight.new()
	f.position = from
	f.floor_y = ground
	f.land_x = landing_x
	f.vel = Vector2(randf_range(-1.6, 1.6), randf_range(-6, -4))
	return f

func resting() -> bool:
	return vel == Vector2.ZERO and position.y >= floor_y

func step() -> void:
	if vel.y == 0.0 and position.y >= floor_y:
		return
	vel.y += 0.45
	position.y += vel.y
	if is_nan(land_x):
		position.x += vel.x
	else:
		position.x = lerpf(position.x, land_x, 0.12)
	if position.y >= floor_y:
		position.y = floor_y
		if not is_nan(land_x):
			position.x = land_x
		vel = Vector2.ZERO

func to_array() -> Array:
	return [position.x, position.y, vel.x, vel.y, floor_y, land_x]

static func from_array(a: Array) -> DropFlight:
	var f := DropFlight.new()
	f.position = Vector2(a[0], a[1])
	f.vel = Vector2(a[2], a[3])
	f.floor_y = a[4]
	f.land_x = a[5]
	return f
