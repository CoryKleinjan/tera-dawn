class_name Hitbox
extends RefCounted
## A box standing on a character's feet, in game pixels. Used for being hit (hurtboxes)
## and for touching (monsters hurt the player on contact).

var size := Vector2(30, 60)

func _init(box_size := Vector2(30, 60)) -> void:
	size = box_size

## The box when the feet are at `feet` (bottom centre).
func rect_at(feet: Vector2) -> Rect2:
	return Rect2(feet.x - size.x / 2.0, feet.y - size.y, size.x, size.y)

## The area an attack covers: `reach` pixels in front of `feet`, a little behind, `height` tall.
static func attack_area(feet: Vector2, face: int, reach: float, height: float, behind := 10.0) -> Rect2:
	var x0 := feet.x - behind if face > 0 else feet.x - reach
	return Rect2(x0, feet.y - height + 10.0, reach + behind, height)

## Which way an attack aims: ahead of the player, straight up, or straight down (in the air).
enum Aim { AHEAD, UP, DOWN }

## How far above the feet an upward attack starts, and below the waist a downward one:
## the swing covers the body's edge too, so a monster pressed against it is hit.
const UP_FROM := 40.0
const DOWN_FROM := 30.0

## The area an attack aimed `aim` covers. Ahead is attack_area; up and down are the same
## shape turned on end: `reach` above or below the player, `height` wide, centred on them.
static func aimed_area(feet: Vector2, face: int, aim: Aim, reach: float, height: float) -> Rect2:
	match aim:
		Aim.UP:
			return Rect2(feet.x - height / 2.0, feet.y - UP_FROM - reach, height, reach + UP_FROM)
		Aim.DOWN:
			return Rect2(feet.x - height / 2.0, feet.y - DOWN_FROM, height, reach + DOWN_FROM)
	return attack_area(feet, face, reach, height)

## The way an attack aimed `aim` points, for a player facing `face` (a unit vector, y down).
static func aim_direction(face: int, aim: Aim) -> Vector2:
	match aim:
		Aim.UP:
			return Vector2.UP
		Aim.DOWN:
			return Vector2.DOWN
	return Vector2(face, 0)
