class_name DrawUtil
extends RefCounted
## Small drawing helpers for the overlay: rounded boxes and outlined text.
## Filled shapes smaller than MIN_SIZE (a bar at a sliver of fill) are skipped: the renderer
## can't triangulate a collapsed polygon and logs an error every frame instead.

## The smallest width or height, in pixels, a filled shape is drawn at.
const MIN_SIZE := 1.0

static func ellipse_points(c: Vector2, rx: float, ry: float, from := 0.0, to := TAU, segs := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var full := is_equal_approx(to - from, TAU)
	var n := segs if full else segs + 1
	for i in n:
		var a := from + (to - from) * float(i) / segs
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	if big_enough(Vector2(rx, ry) * 2.0):
		fill(ci, ellipse_points(c, rx, ry), col)

## The outline of a box with rounded corners. A radius too small to show gives the plain
## four corners rather than corners folded back on themselves.
static func round_rect_points(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) / 2.0 - 0.5)
	var pts := PackedVector2Array()
	if rad < 0.5:
		pts.append_array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		return pts
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
	if big_enough(r.size):
		fill(ci, round_rect_points(r, rad), col)

## Whether a filled shape this big is drawn at all (see MIN_SIZE).
static func big_enough(size: Vector2) -> bool:
	return size.x >= MIN_SIZE and size.y >= MIN_SIZE

## Fills a polygon, unless it has collapsed to fewer than three different points.
static func fill(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if fillable(pts):
		ci.draw_colored_polygon(pts, col)

## Whether a polygon has at least three different points, so it can be filled.
static func fillable(pts: PackedVector2Array) -> bool:
	var seen := {}
	for p in pts:
		seen[p] = true
		if seen.size() >= 3:
			return true
	return false

## The faint dark backdrop behind text drawn straight over the scene (the message log, chat),
## faded by `alpha` along with its text.
static func backdrop(ci: CanvasItem, r: Rect2, alpha := 1.0) -> void:
	if alpha > 0.0:
		round_rect(ci, r, 6.0, Color(Palette.BACKDROP, Palette.BACKDROP.a * alpha))

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

## How tall the UI fonts' capitals are, as a share of the font size.
const CAP_HEIGHT := 0.7

## The baseline that puts the middle of a line's capitals, `size` big, on height `y`.
static func cap_baseline(y: float, size: int) -> float:
	return y + size * CAP_HEIGHT / 2.0

static func text_width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## The largest font size up to `size` (and no smaller than `min_size`) at which `s` fits in
## `max_w` pixels, for labels on art of a fixed width (tabs, slots, chips).
static func fit_size(font: Font, s: String, size: int, max_w: float, min_size := 8) -> int:
	while size > min_size and text_width(font, s, size) > max_w:
		size -= 1
	return size

## `text` broken into lines at most `max_w` pixels wide, between words.
static func wrap_text(font: Font, text: String, size: int, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		var next := word if line == "" else line + " " + word
		if line != "" and text_width(font, next, size) > max_w:
			out.append(line)
			line = word
		else:
			line = next
	if line != "":
		out.append(line)
	return out
