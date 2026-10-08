class_name TDDrop
extends Node2D
## A Dawnshard pile dropped by a monster. Picked up by walking over it.

var world: TDWorld
var vel := Vector2.ZERO
var floor_y := 0.0
var amount := 1
var t := 0
var spin := randf() * 6.0
var taken := false

func step() -> void:
	t += 1
	spin += 0.1
	if vel.y != 0.0 or position.y < floor_y:
		vel.y += 0.45
		position += vel
		if position.y >= floor_y:
			position.y = floor_y
			vel = Vector2.ZERO
	var p := world.player
	if not taken and t > 25 and p.dead == 0 and absf(position.x - p.position.x) < 26 and absf(position.y - p.position.y) < 50:
		taken = true
		Game.shards += amount
		world.add_log("Picked up %d Dawnshards" % amount, GameData.MIST)
		queue_free()
	elif t > 3600:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var hover := sin(spin * 2.0) * 2.0 if vel == Vector2.ZERO else 0.0
	var sx := absf(cos(spin)) * 0.7 + 0.3
	draw_set_transform_matrix(Transform2D(0, Vector2(0, -8 - hover)) * Transform2D(0, Vector2(sx, 1), 0, Vector2.ZERO) * Transform2D(PI / 4, Vector2.ZERO))
	draw_polygon(PackedVector2Array([Vector2(-6, -6), Vector2(6, -6), Vector2(6, 6), Vector2(-6, 6)]),
		PackedColorArray([Color("fff2b8"), GameData.SUN, GameData.EMBER, GameData.SUN]))
