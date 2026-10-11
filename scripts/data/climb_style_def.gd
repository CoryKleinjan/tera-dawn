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

## Game pixels of one-way platform left (x) and right (y) of `x` on the platform whose top is
## at `y`; infinite on the floor or with no platform there.
static func ledge_room(x: float, y: float, platforms: Array[Platform]) -> Vector2:
	for pl in platforms:
		if not pl.solid and pl.contains_x(x) and absf(pl.y - y) < 1.0:
			return Vector2(x - pl.x, pl.x + pl.w - x)
	return Vector2(INF, INF)
