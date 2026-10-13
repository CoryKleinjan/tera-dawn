class_name ClimbStyleDef
extends Resource
## How a kind of climbable looks and which climbing animation the player uses on it.
## The art step (tools/art/climb_pieces.py) centres every piece on the rope or rails, so the
## pieces only need stacking: top, a whole number of middles, bottom, each touching the next.

## Game pixels the bottom piece reaches below the climbable's bottom (into the floor).
const BOTTOM_SINK := 2.0

@export var id: StringName
## Drawn at the top end (optional), repeated down the middle, and at the bottom end (optional).
@export var top: Texture2D
@export var middle: Texture2D
@export var bottom: Texture2D
## Game pixels per art pixel: a bit finer than TDStage.TEXEL, so ropes and ladders stay slim
## next to the hero.
@export var texel := 1.0
## Share of the top piece's height that rises above the ledge the climbable hangs from
## (a ladder's posts, a peg or knot sitting on the ledge). 0 hangs the top piece from the ledge.
@export_range(0.0, 1.0) var top_rise := 0.0
## "rope" or "ladder" (hero animations).
@export var climb_animation := &"rope"

static var _reach := {}

## The pieces of a climbable from `top_y` down to `bottom_y` (game pixels, y down), top
## first: dictionaries with "texture", "y" (top edge) and "height" (drawn height, game pixels).
## Middles share the space between the end pieces evenly, each squeezed or stretched a little
## so a whole number fit and rungs stay evenly spaced.
func pieces(top_y: float, bottom_y: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if middle == null:
		return out
	var y := top_y
	if top:
		var h := TDStage.art_size(top, texel).y
		y -= h * top_rise
		out.append({"texture": top, "y": y, "height": h})
		y += h
	var end := bottom_y + BOTTOM_SINK
	var bottom_h := TDStage.art_size(bottom, texel).y if bottom else 0.0
	var span := end - bottom_h - y
	var mid_h := TDStage.art_size(middle, texel).y
	var n := maxi(1, roundi(span / mid_h)) if span > 0.0 else 0
	for i in n:
		out.append({"texture": middle, "y": y + span * i / n, "height": span / n})
	if bottom:
		out.append({"texture": bottom, "y": end - bottom_h, "height": bottom_h})
	return out

## Whether to draw the top piece mirrored on a ledge with `room` game pixels left (x) and right
## (y) of the line: a peg or coil off to one side then points toward the wider side, so it
## stays over the ledge.
func top_flipped(room: Vector2) -> bool:
	if top == null:
		return false
	var r := solid_reach(top, texel)
	return minf(room.x - r.y, room.y - r.x) > minf(room.x - r.x, room.y - r.y)

## How far `tex`'s solid pixels reach left (x) and right (y) of its centre line, in game
## pixels at `texel`.
static func solid_reach(tex: Texture2D, texel: float) -> Vector2:
	if not _reach.has(tex):
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		var lo := img.get_width()
		var hi := -1
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					lo = mini(lo, x)
					hi = maxi(hi, x)
		_reach[tex] = Vector2(img.get_width() / 2.0 - lo, hi + 1 - img.get_width() / 2.0) / TDStage.art_density(tex)
	return _reach[tex] * texel

## How far apart (art pixels, on either side) an end piece's sides may be from the middles'
## where they join and still be fitted to them (piece_fit); further off, it's a decorative
## end (a vine's tangle, a rope ladder's beam) and is drawn as painted.
const FIT_RANGE := 4.0
## Rows at a piece's joining edge measured for its sides (join_sides): the ones that touch.
const JOIN_ROWS := 2

## How to draw `tex` (one of this style's pieces, mirrored when `flipped`) so it lines up with
## the middles where they join: x is how much wider to draw it, y how far right to move it,
## in game pixels. The painted end pieces can be a pixel or two wider or narrower than the
## middles; fitted, a ladder's rails and a rope's strands run on in one line.
func piece_fit(tex: Texture2D, flipped := false) -> Vector2:
	if middle == null or tex == middle or (tex != top and tex != bottom):
		return Vector2(1.0, 0.0)
	var is_top := tex == top
	var ref := join_sides(middle, texel, not is_top)
	if not is_top:
		ref += Vector2.ONE * slant()
	var own := join_sides(tex, texel, is_top)
	if flipped:
		own = Vector2(-own.y, -own.x)
	var tol := FIT_RANGE * texel / TDStage.art_density(tex)
	if absf(own.x - ref.x) > tol or absf(own.y - ref.y) > tol or own.y - own.x <= 0.0:
		return Vector2(1.0, 0.0)
	var fit := (ref.y - ref.x) / (own.y - own.x)
	return Vector2(fit, (ref.x + ref.y) / 2.0 - (own.x + own.y) / 2.0 * fit)

## How far right (game pixels) a middle is drawn leaning at its bottom edge, so its strand
## comes out where the next middle's goes in (a vine's stem wanders a little across a piece).
func slant() -> float:
	if middle == null:
		return 0.0
	var a := join_sides(middle, texel, false)
	var b := join_sides(middle, texel, true)
	return (a.x + a.y) / 2.0 - (b.x + b.y) / 2.0

## Where `tex`'s sides are along its bottom (or top) edge: over its last (first) JOIN_ROWS
## rows with anything solid, the innermost leftmost (x) and rightmost (y) solid pixel (so a
## leaf or knot poking out of one row doesn't count), from its centre line in game pixels at
## `texel` (left negative).
static func join_sides(tex: Texture2D, texel: float, bottom_edge: bool) -> Vector2:
	var key := [tex, bottom_edge]
	if not _reach.has(key):
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var lefts: Array[int] = []
		var rights: Array[int] = []
		for i in h:
			var y := h - 1 - i if bottom_edge else i
			var lo := -1
			var hi := -1
			for x in w:
				if img.get_pixel(x, y).a > 0.5:
					if lo < 0:
						lo = x
					hi = x
			if lo >= 0:
				lefts.append(lo)
				rights.append(hi + 1)
				if lefts.size() == JOIN_ROWS:
					break
		if lefts.is_empty():
			_reach[key] = Vector2(-w / 2.0, w / 2.0) / TDStage.art_density(tex)
		else:
			_reach[key] = Vector2(lefts.max() - w / 2.0, rights.min() - w / 2.0) / TDStage.art_density(tex)
	return _reach[key] * texel

## Game pixels of one-way platform left (x) and right (y) of `x` on the platform whose top is
## at `y`; infinite on the floor or with no platform there.
static func ledge_room(x: float, y: float, platforms: Array[Platform]) -> Vector2:
	for pl in platforms:
		if not pl.solid and pl.contains_x(x) and absf(pl.y - y) < 1.0:
			return Vector2(x - pl.x, pl.x + pl.w - x)
	return Vector2(INF, INF)
