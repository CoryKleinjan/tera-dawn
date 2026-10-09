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
