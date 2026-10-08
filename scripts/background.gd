class_name TDBackground
extends Node2D
## Screen-space sky, sun, clouds and parallax ridges behind the map.

var world: TDWorld

func _process(_delta: float) -> void:
	queue_redraw()

func _ridge(seed_: float, x: float) -> float:
	return sin(x * 0.004 + seed_) * 40 + sin(x * 0.011 + seed_ * 2.3) * 18 + sin(x * 0.027 + seed_ * 5.1) * 7

func _draw() -> void:
	if world == null or world.colors.is_empty():
		return
	var th := world.colors
	var v := TDWorld.VIEW
	var cam := world.cam
	var sky: Array = th["sky"]
	var band := v.y / (sky.size() - 1)
	for i in sky.size() - 1:
		DrawUtil.vgradient_rect(self, Rect2(0, i * band, v.x, band + 1), sky[i], sky[i + 1])
	# sun low on the horizon
	var sun: Color = th["sun"]
	var sp := Vector2(v.x * 0.68 - cam.x * 0.03, 330 - cam.y * 0.1)
	for i in 8:
		var r := 220.0 - i * 22.0
		draw_circle(sp, r, Color(sun, 0.06))
	draw_circle(sp, 46, sun)
	# clouds
	var cloud := Color(1, 0.94, 0.9, 0.18)
	var wrap := v.x + 400
	for i in 6:
		var cx := fposmod(i * 380 + world.tick * (0.15 + i * 0.03) - cam.x * 0.15, wrap) - 200
		var cy := 70.0 + (i * 53) % 150 - cam.y * 0.1
		DrawUtil.ellipse(self, Vector2(cx, cy), 90, 18, cloud)
		DrawUtil.ellipse(self, Vector2(cx + 40, cy - 10), 50, 16, cloud)
	# parallax ridges
	var layers := [[th["far"], 0.2, 360.0, 1.3], [th["mid"], 0.4, 430.0, 4.1], [th["near"], 0.65, 500.0, 7.7]]
	for l in layers:
		var f: float = l[1]
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= v.x:
			pts.append(Vector2(x, l[2] - cam.y * f * 0.5 + _ridge(l[3], x + cam.x * f)))
			x += 12.0
		pts.append(Vector2(v.x, v.y))
		pts.append(Vector2(0, v.y))
		draw_colored_polygon(pts, l[0])
