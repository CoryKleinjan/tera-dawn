class_name DrawUtil
extends RefCounted
## Small drawing helpers for the overlay: rounded boxes and outlined text.

static func ellipse_points(c: Vector2, rx: float, ry: float, from := 0.0, to := TAU, segs := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var full := is_equal_approx(to - from, TAU)
	var n := segs if full else segs + 1
	for i in n:
		var a := from + (to - from) * float(i) / segs
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_colored_polygon(ellipse_points(c, rx, ry), col)

static func round_rect_points(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) / 2.0 - 0.5)
	var pts := PackedVector2Array()
	var centers := [
		Vector2(r.end.x - rad, r.position.y + rad),
		Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.position.y + rad),
	]
	for k in 4:
		var start := -PI / 2.0 + k * PI / 2.0
		for i in 5:
			var a := start + (PI / 2.0) * i / 4.0
			pts.append(centers[k] + Vector2(cos(a), sin(a)) * rad)
	return pts

static func round_rect(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	ci.draw_colored_polygon(round_rect_points(r, rad), col)

static func vgradient_rect(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	ci.draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))

## Draws text anchored at `pos` (baseline). align: -1 right, 0 center, 1 left.
static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color, align := 0, outline := 0, outline_col := Color(0, 0, 0, 0.8)) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos
	if align == 0:
		p.x -= w / 2.0
	elif align == -1:
		p.x -= w
	if outline > 0:
		ci.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_col)
	ci.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

static func text_width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
