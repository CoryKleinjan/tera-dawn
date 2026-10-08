class_name TDEffect
extends Node2D
## Short-lived hit sparks, the Dawn Slash arc and the level-up burst.

var world: TDWorld
var kind := "spark"
var face := 1
var t := 0

func step() -> void:
	t += 1
	if kind == "levelup":
		position = world.player.position
	if t > (120 if kind == "levelup" else 24):
		queue_free()
	queue_redraw()

func _draw() -> void:
	match kind:
		"spark":
			var k := t / 24.0
			var col := Color(1, 0.9, 0.63, 1.0 - k)
			for i in 6:
				var a := i * 1.05 + position.x
				var dir := Vector2(cos(a), sin(a))
				draw_line(dir * (6 + k * 10), dir * (14 + k * 26), col, 3)
		"slash":
			var k := t / 24.0
			draw_set_transform(Vector2.ZERO, 0, Vector2(face, 1))
			draw_arc(Vector2(30 + k * 60, 0), 60, -1.1, 1.1, 24, Color(1, 0.82, 0.4, 1.0 - k), 10 * (1 - k) + 2)
			draw_arc(Vector2(10 + k * 90, 0), 48, -1.0, 1.0, 24, Color(1, 0.48, 0.35, 0.8 - k * 0.8), 4)
		"levelup":
			var k := t / 120.0
			modulate.a = 1.0 - k
			DrawUtil.vgradient_rect(self, Rect2(-40, -160, 80, 160), Color(1, 0.82, 0.4, 0), Color(1, 0.82, 0.4, 0.55))
			DrawUtil.text(self, Game.num_font, Vector2(0, -100 - k * 40), "LEVEL UP!", 40, GameData.SUN, 0, 10, GameData.PLUM)
