class_name TDFloatText
extends Node2D
## A floating word, drawn by the overlay at its projected screen position: "MISS" (the game
## shows no damage numbers), or something you gained (exp, essence, shards) as a smaller "+9 EXP".

## Gains younger than this stack above each other (see TDWorldFx.show_gain).
const GAIN_STACK_TICKS := 30
## What each kind of gain says after its amount, and its colour.
const GAINS := {
	"exp": ["EXP", Color("fff0c2")],
	"essence": ["Dawn Essence", Color("ffe39a")],
	"shards": ["Dawnshards", Color("ffd36b")],
}

var world: TDWorld
var value := 0
var kind := "miss" # miss, or a gain (exp, essence, shards)
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
	var pop := 1.0 + (6 - t) * 0.08 if t < 6 else 1.0
	ci.draw_set_transform(at, 0, Vector2(pop, pop))
	DrawUtil.text(ci, Game.num_font, Vector2.ZERO, "MISS", 24, Color(Color("c9d6ff"), a), 0, 8, Color(Color("27305a"), a))
	ci.draw_set_transform(Vector2.ZERO)
