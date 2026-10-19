class_name TDVitals
extends Control
## Hearts and Mana in the top left corner, Hollow Knight style (Cory Oct 19): the Mana orb,
## filling from the bottom, with a row of hearts beside it, one per heart the hero can hold.
## PLACEHOLDER shapes until the painted heart and orb art is approved; then they draw that.

## Where the orb sits (screen pixels), under the menu button and map name.
const ORB := Rect2(8, 46, 58, 58)
## The first heart's centre, and the step to the next.
const FIRST_HEART := Vector2(84, 64)
const HEART_STEP := 30.0
const HEART_SIZE := 24.0
## A heart just lost or healed flashes for this many seconds.
const FLASH := 0.35

const HEART_FULL := Color(0.86, 0.16, 0.2)
const HEART_EMPTY := Color(0.12, 0.08, 0.12, 0.75)
const RIM := Color(0.95, 0.78, 0.38)
const MANA := Color(0.35, 0.62, 1.0)
const ORB_GLASS := Color(0.08, 0.1, 0.2, 0.8)

var world: TDWorld
var _hp_seen := -1
var _flash := 0.0
var _drawn := []

func _process(delta: float) -> void:
	visible = world != null and world.started
	if not visible:
		return
	var hp := Game.me.health.hp
	if _hp_seen >= 0 and hp != _hp_seen:
		_flash = FLASH
	_hp_seen = hp
	_flash = maxf(0.0, _flash - delta)
	var state := [hp, Game.me.max_hp(), Game.me.mp, Game.me.max_mp(), _flash > 0.0, world.player.heal_t if world.player else 0]
	if state != _drawn:
		_drawn = state
		queue_redraw()

func _draw() -> void:
	var me := Game.me
	_draw_orb(float(me.mp) / maxf(1.0, me.max_mp()))
	for i in me.max_hp():
		var at := FIRST_HEART + Vector2(i * HEART_STEP, 0)
		_draw_heart(at, i < me.health.hp)
	if _flash > 0.0 and me.health.hp < me.max_hp():
		var lost := FIRST_HEART + Vector2(me.health.hp * HEART_STEP, 0)
		draw_circle(lost, HEART_SIZE * 0.7, Color(1, 1, 1, _flash / FLASH * 0.5))

## The orb: a dark glass circle in a gold rim, its Mana rising from the bottom. While the
## heal key gathers Mana it glows brighter.
func _draw_orb(fill: float) -> void:
	var c := ORB.get_center()
	var r := ORB.size.x / 2.0
	draw_circle(c, r, ORB_GLASS)
	if fill > 0.0:
		var top := c.y + r - 2.0 * r * fill
		var pts := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			var p := c + Vector2(cos(a), sin(a)) * (r - 3.0)
			pts.append(Vector2(p.x, maxf(p.y, top)))
		var glow := 1.0 + (0.4 if world.player and world.player.heal_t > 0 else 0.0)
		draw_colored_polygon(pts, Color(MANA.r * glow, MANA.g * glow, MANA.b * glow))
	draw_arc(c, r, 0.0, TAU, 48, RIM, 3.0, true)

## One heart: two lobes and a point, red when full, dark when lost, with a gold rim.
func _draw_heart(at: Vector2, full: bool) -> void:
	var pts := _heart_points(at, HEART_SIZE)
	draw_colored_polygon(pts, HEART_FULL if full else HEART_EMPTY)
	pts.append(pts[0])
	draw_polyline(pts, RIM, 2.0, true)

static func _heart_points(at: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 40:
		# the classic heart curve, scaled to `size` across
		var t := TAU * i / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(at + Vector2(x, y) * size / 34.0)
	return pts
