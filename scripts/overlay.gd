class_name TDOverlay
extends Control
## Screen-space text drawn over the map: map name, minimap, message log, banner and faint screen.

var world: TDWorld

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null or world.map.is_empty():
		return
	var font := Game.ui_font
	var v := TDWorld.VIEW
	var dark := Color(0.1, 0.07, 0.19, 0.6)
	# map name
	var name_w := DrawUtil.text_width(font, world.map["name"], 14) + 22
	DrawUtil.round_rect(self, Rect2(10, 10, name_w, 28), 8, dark)
	DrawUtil.text(self, font, Vector2(21, 29), world.map["name"], 14, GameData.MIST, 1)
	# minimap
	var mm := Rect2(v.x - 180, 10, 170, 46)
	var sx := mm.size.x / float(world.map["w"])
	var sy := mm.size.y / float(world.map["h"])
	DrawUtil.round_rect(self, mm, 8, dark)
	for pl in world.plats:
		draw_rect(Rect2(mm.position.x + pl.x * sx, mm.position.y + pl.y * sy, maxf(2, pl.w * sx), 2), Color(1, 0.95, 0.9, 0.5))
	for p in world.map["portals"]:
		draw_rect(Rect2(mm.position.x + float(p["x"]) * sx - 2, mm.position.y + world.plats[int(p["plat"])].y * sy - 6, 4, 6), Color("aa8cff"))
	var pp := world.player.position
	draw_circle(mm.position + Vector2(pp.x * sx, pp.y * sy - 3), 3, GameData.SUN)
	# message log, newest at the bottom, above the status bar
	var n := world.log_lines.size()
	for i in n:
		var line: Dictionary = world.log_lines[i]
		var y := v.y - 48 - (n - 1 - i) * 18
		var col: Color = line["color"]
		col.a = minf(1.0, line["t"] / 40.0)
		DrawUtil.text(self, font, Vector2(v.x - 12, y), line["text"], 13, col, -1, 4, Color(0.1, 0.07, 0.19, 0.8 * col.a))
	# map banner
	if world.banner_t > 0:
		var a := minf(1.0, minf(world.banner_t / 30.0, (180 - world.banner_t) / 20.0))
		DrawUtil.text(self, Game.num_font, Vector2(v.x / 2, 120), world.banner_text, 44, Color(GameData.MIST, a), 0, 10, Color(0.1, 0.07, 0.19, 0.8 * a))
	if world.player.dead > 0:
		draw_rect(Rect2(Vector2.ZERO, v), Color(0.1, 0.07, 0.19, 0.45))
		DrawUtil.text(self, Game.num_font, Vector2(v.x / 2, v.y / 2 - 10), "You fainted", 40, GameData.MIST)
		DrawUtil.text(self, font, Vector2(v.x / 2, v.y / 2 + 22), "Returning to Dawnrise Meadow…", 16, GameData.MIST)
