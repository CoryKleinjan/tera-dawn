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
@export var texel := 1.25
## Share of the top piece's height that rises above the ledge the climbable hangs from
## (a ladder's posts, a peg or knot sitting on the ledge). 0 hangs the top piece from the ledge.
@export_range(0.0, 1.0) var top_rise := 0.0
## "rope" or "ladder" (hero animations).
@export var climb_animation := &"rope"

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
