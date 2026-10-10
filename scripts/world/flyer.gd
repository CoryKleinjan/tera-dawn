class_name TDFlyer
extends AnimatedSprite3D
## A bird (or other small creature) crossing the sky behind the scene, for a town's ambient
## life (BiomeDef.flyers). It glides across the map with a gentle bob and starts over on
## the other side.

var speed := 1.0 # 3D units per second, signed
var span := Vector2.ZERO # x range in 3D units
var base_y := 0.0
var _t := randf() * TAU

func _process(delta: float) -> void:
	_t += delta
	position.x += speed * delta
	position.y = base_y + sin(_t * 1.3) * 0.25
	if speed > 0.0 and position.x > span.y:
		position.x = span.x
	elif speed < 0.0 and position.x < span.x:
		position.x = span.y
