class_name LookShapes
extends RefCounted
## Pictures drawn on the hero at a point of his rig (hero_rig.json) rather than as a layer
## that plays with him: hats, drawn in code as stand-ins until hat art exists. A stand-in is
## a few flat polygons in the hero's pixel scale, filled in the item's colour with a darker
## and a lighter tone and a dark outline, so it reads like pixel art next to him. (Weapons are
## layers now, held in his fist frame by frame: see Paperdoll.weapon_layers.)
##
## A shape says where it sits on the hero (`anchor`: "head_top"), which pixel of the picture
## goes on that point (`pivot`) and whether it's drawn behind him. The picture faces right
## like the hero; Paperdoll mirrors it.
##
## Add a hat by adding an entry to SHAPES and a `_draw_<name>` function.

## name -> [anchor, pivot, size, behind, turns with the weapon]
const SHAPES := {
	# hats (anchor "head_top": the top of the head)
	&"cap": [&"head_top", Vector2(22, 2), Vector2i(52, 24), false, false],
	&"helm": [&"head_top", Vector2(22, 1), Vector2i(46, 30), false, false],
	&"hood": [&"head_top", Vector2(24, 2), Vector2i(50, 46), false, false],
	&"bandana": [&"head_top", Vector2(22, -8), Vector2i(52, 16), false, false],
	&"wizard": [&"head_top", Vector2(26, 16), Vector2i(58, 38), false, false],
	&"tricorn": [&"head_top", Vector2(26, -2), Vector2i(56, 24), false, false],
}
## Shapes drawn without the dark outline.
const NO_OUTLINE: Array[StringName] = []

const INK := Color(0.16, 0.09, 0.12)
const GOLD := Color(0.98, 0.78, 0.3)
const WHITE := Color(0.97, 0.96, 0.92)

## shape + colour -> ImageTexture, drawn once.
static var _cache := {}

static func has(shape: StringName) -> bool:
	return SHAPES.has(shape)

static func anchor(shape: StringName) -> StringName:
	return SHAPES[shape][0]

static func pivot(shape: StringName) -> Vector2:
	return SHAPES[shape][1]

static func behind(shape: StringName) -> bool:
	return SHAPES[shape][3]

static func turns(shape: StringName) -> bool:
	return SHAPES[shape][4]

## The picture of a shape in a colour.
static func texture(shape: StringName, col: Color) -> Texture2D:
	var key := "%s/%s" % [shape, col.to_html(false)]
	if not _cache.has(key):
		var size: Vector2i = SHAPES[shape][2]
		var pen := Pen.new(size, col)
		Callable(LookShapes, "_draw_" + String(shape)).call(pen)
		_cache[key] = ImageTexture.create_from_image(pen.finish(not shape in NO_OUTLINE))
	return _cache[key]

## Fills polygons into an image, then outlines everything filled.
class Pen:
	var img: Image
	var base: Color
	var dark: Color
	var light: Color

	func _init(size: Vector2i, col: Color) -> void:
		img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		base = col
		dark = col.darkened(0.3)
		light = col.lightened(0.28)

	## Fills a polygon (pixels whose centre is inside it).
	func poly(points: PackedVector2Array, col: Color) -> void:
		var box := Rect2(points[0], Vector2.ZERO)
		for p in points:
			box = box.expand(p)
		for y in range(maxi(0, floori(box.position.y)), mini(img.get_height(), ceili(box.end.y) + 1)):
			for x in range(maxi(0, floori(box.position.x)), mini(img.get_width(), ceili(box.end.x) + 1)):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
					img.set_pixel(x, y, col)

	func ellipse(center: Vector2, radius: Vector2, col: Color, from := 0.0, to := TAU) -> void:
		var pts := PackedVector2Array()
		if to - from < TAU:
			pts.append(center)
		for i in 25:
			var a := lerpf(from, to, i / 24.0)
			pts.append(center + Vector2(cos(a), sin(a)) * radius)
		poly(pts, col)

	## A thick line (as a polygon).
	func line(a: Vector2, b: Vector2, width: float, col: Color) -> void:
		var n := (b - a).orthogonal().normalized() * width / 2.0
		poly(PackedVector2Array([a + n, b + n, b - n, a - n]), col)

	func dot(at: Vector2i, col: Color) -> void:
		if Rect2i(Vector2i.ZERO, img.get_size()).has_point(at):
			img.set_pixelv(at, col)

	## The finished picture with a one-pixel outline around everything drawn.
	func finish(outline := true) -> Image:
		if not outline:
			return img
		var out := img.duplicate() as Image
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.0:
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = Vector2i(x, y) + d
					if Rect2i(Vector2i.ZERO, img.get_size()).has_point(n) and img.get_pixelv(n).a > 0.0 and img.get_pixelv(n) != INK:
						out.set_pixel(x, y, INK)
						break
		return out

static func _p(values: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, values.size(), 2):
		out.append(Vector2(values[i], values[i + 1]))
	return out

# ---------- hats ----------

static func _draw_cap(p: Pen) -> void:
	p.ellipse(Vector2(22, 17), Vector2(20, 15), p.base, PI, TAU)
	p.poly(_p([20, 15, 51, 15, 49, 20, 22, 20]), p.dark)
	p.ellipse(Vector2(15, 9), Vector2(7, 4), p.light)
	p.ellipse(Vector2(22, 3), Vector2(3, 2), p.dark)

static func _draw_helm(p: Pen) -> void:
	p.ellipse(Vector2(22, 19), Vector2(21, 18), p.base, PI, TAU)
	p.poly(_p([1, 18, 43, 18, 43, 22, 10, 22, 10, 29, 2, 29]), p.dark)
	p.line(Vector2(22, 2), Vector2(22, 18), 3, p.light)
	p.poly(_p([34, 18, 39, 18, 38, 27, 35, 27]), p.dark)
	p.dot(Vector2i(6, 25), GOLD)

static func _draw_hood(p: Pen) -> void:
	# over the top and back of the head, open at the face (the face is around 18..38, 21..38)
	p.poly(_p([2, 16, 8, 5, 20, 0, 34, 1, 44, 8, 48, 18, 44, 22, 34, 18, 22, 19, 16, 24, 16, 44, 6, 44, 2, 32]), p.base)
	p.poly(_p([3, 18, 9, 10, 12, 22, 12, 42, 6, 43, 3, 32]), p.dark)
	p.line(Vector2(16, 21), Vector2(44, 20), 2, p.light)

static func _draw_bandana(p: Pen) -> void:
	# a band round the forehead, knotted at the back
	p.poly(_p([5, 4, 24, 1, 45, 3, 47, 9, 26, 8, 7, 11]), p.base)
	p.line(Vector2(8, 6), Vector2(44, 5), 1, p.light)
	p.poly(_p([6, 6, 0, 14, 4, 15, 9, 9]), p.dark)
	p.poly(_p([7, 7, 7, 15, 11, 14, 10, 8]), p.dark)
	p.dot(Vector2i(32, 5), WHITE)
	p.dot(Vector2i(20, 6), WHITE)

static func _draw_wizard(p: Pen) -> void:
	p.poly(_p([2, 28, 56, 28, 50, 34, 8, 34]), p.dark)
	p.poly(_p([14, 29, 22, 12, 30, 3, 40, 1, 34, 8, 36, 29]), p.base)
	p.poly(_p([14, 26, 36, 26, 36, 29, 14, 29]), GOLD)
	p.line(Vector2(24, 12), Vector2(30, 5), 2, p.light)
	p.dot(Vector2i(28, 18), WHITE)

static func _draw_tricorn(p: Pen) -> void:
	p.poly(_p([2, 12, 26, 6, 54, 12, 48, 20, 26, 16, 8, 20]), p.dark)
	p.ellipse(Vector2(27, 10), Vector2(14, 9), p.base, PI, TAU)
	p.poly(_p([12, 10, 42, 10, 42, 13, 12, 13]), GOLD)
	p.ellipse(Vector2(24, 5), Vector2(4, 2), p.light)
