class_name TDFloatText
extends Node2D
## A floating damage number, drawn by the overlay at its projected screen position.

var world: TDWorld
var value := 0
var kind := "hit" # hit, crit or taken
var t := 0

func step() -> void:
	t += 1
	position.y -= 0.7
	if t > 70:
		queue_free()

func draw_at(ci: CanvasItem, at: Vector2) -> void:
	var k := t / 70.0
	var size := 34 if kind == "crit" else (26 if kind == "taken" else 28)
	var pop := 1.0 + (6 - t) * 0.08 if t < 6 else 1.0
	var a := (1.0 - k) / 0.3 if k > 0.7 else 1.0
	var fill := Color("ff5d73") if kind == "crit" else (Color("d79bff") if kind == "taken" else Color("ffb347"))
	var edge := Color("3b1550") if kind == "taken" else Color("5a2a10")
	ci.draw_set_transform(at, 0, Vector2(pop, pop))
	DrawUtil.text(ci, Game.num_font, Vector2.ZERO, str(value), size, Color(fill, a), 0, 8, Color(edge, a))
	ci.draw_set_transform(Vector2.ZERO)
