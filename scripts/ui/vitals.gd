class_name TDVitals
extends Control
## Hearts and Mana in the top left corner, Hollow Knight style (Cory Oct 19): the painted Mana
## orb, filling from the bottom, with a row of painted hearts beside it, one per heart the hero
## can hold. Art: art/sheets/hearts_mana.json (Cory approved the look 17:18Z Oct 19).

## Where the orb sits (screen pixels), under the menu button and map name.
const ORB := Rect2(8, 46, 58, 58)
## The first heart's centre, and the step to the next.
const FIRST_HEART := Vector2(84, 64)
const HEART_STEP := 30.0
const HEART_WIDTH := 24.0

const HEART_FULL := preload("res://assets/sprites/ui/heart_full.png")
const HEART_EMPTY := preload("res://assets/sprites/ui/heart_empty.png")
const MANA_FULL := preload("res://assets/sprites/ui/mana_full.png")
const MANA_EMPTY := preload("res://assets/sprites/ui/mana_empty.png")

var world: TDWorld
var _drawn := []

func _process(_delta: float) -> void:
	visible = world != null and world.started
	if not visible:
		return
	var state := [Game.me.health.hp, Game.me.max_hp(), Game.me.mp, Game.me.max_mp()]
	if state != _drawn:
		_drawn = state
		queue_redraw()

func _draw() -> void:
	var me := Game.me
	_draw_orb(clampf(float(me.mp) / maxf(1.0, me.max_mp()), 0.0, 1.0))
	var size := Vector2(HEART_WIDTH, HEART_WIDTH * HEART_FULL.get_height() / HEART_FULL.get_width())
	for i in me.max_hp():
		var at := FIRST_HEART + Vector2(i * HEART_STEP, 0) - size / 2.0
		draw_texture_rect(HEART_FULL if i < me.health.hp else HEART_EMPTY, Rect2(at, size), false)

## The orb: the empty orb, with the full orb's lower part laid over it up to the Mana level.
## Both paintings line up exactly (cut from one sheet with the same crop).
func _draw_orb(fill: float) -> void:
	draw_texture_rect(MANA_EMPTY, ORB, false)
	if fill <= 0.0:
		return
	var tex_h := float(MANA_FULL.get_height())
	var src := Rect2(0, tex_h * (1.0 - fill), MANA_FULL.get_width(), tex_h * fill)
	var dst := Rect2(ORB.position.x, ORB.end.y - ORB.size.y * fill, ORB.size.x, ORB.size.y * fill)
	draw_texture_rect_region(MANA_FULL, dst, src)
