class_name TDFloatText
extends Node2D
## A floating number, drawn by the overlay at its projected screen position: damage (hit,
## crit, taken or miss), or something you gained (exp, shards) as a smaller "+9 EXP".

## Gains younger than this stack above each other (see TDWorldFx.show_gain).
const GAIN_STACK_TICKS := 30
## What each kind of gain says after its amount, and its colour.
const GAINS := {
	"exp": ["EXP", Color("ffe39a")],
	"shards": ["Dawnshards", Color("ffd36b")],
}

var world: TDWorld
var value := 0
var kind := "hit" # hit, crit, taken, miss, or a gain (exp, shards)
var t := 0

func is_gain() -> bool:
	return GAINS.has(kind)

## What a gain reads ("+9 EXP").
func gain_text() -> String:
	return "+%d %s" % [value, GAINS[kind][0]]

func step() -> void:
	t += 1
	position.y -= 0.45 if is_gain() else 0.7
	if t > 70:
		queue_free()

## Closest a number gets to the screen's edges (screen pixels), so it never runs off.
const SCREEN_MARGIN := Vector2(40, 70)

func draw_at(ci: CanvasItem, at: Vector2) -> void:
	var v := TDWorld.VIEW
	at = at.clamp(SCREEN_MARGIN, v - SCREEN_MARGIN)
	var k := t / 70.0
	var a := (1.0 - k) / 0.3 if k > 0.7 else 1.0
	if is_gain():
		DrawUtil.text(ci, Game.num_font, at, gain_text(), 14, Color(GAINS[kind][1], a), 0, 4, Color(Palette.NIGHT, 0.8 * a))
		return
	var size := 34 if kind == "crit" else (26 if kind == "taken" else 28)
	var pop := 1.0 + (6 - t) * 0.08 if t < 6 else 1.0
	var fill := Color("ff5d73") if kind == "crit" else (Color("d79bff") if kind == "taken" else Color("ffb347"))
	var edge := Color("3b1550") if kind == "taken" else Color("5a2a10")
	ci.draw_set_transform(at, 0, Vector2(pop, pop))
	if kind == "miss":
		DrawUtil.text(ci, Game.num_font, Vector2.ZERO, "MISS", 24, Color(Color("c9d6ff"), a), 0, 8, Color(Color("27305a"), a))
	else:
		DrawUtil.text(ci, Game.num_font, Vector2.ZERO, str(value), size, Color(fill, a), 0, 8, Color(edge, a))
	ci.draw_set_transform(Vector2.ZERO)
