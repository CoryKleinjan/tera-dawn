class_name TDStatsWindow
extends TDWindow
## Character info (S): hearts, Mana, and what the gear works out to in combat.

const ROW_H := 17.0
## How far above a row's baseline the middle of its text sits (12 px text).
const TEXT_MID := 4.0
const COL_VALUE := 112.0
## Where the right-hand column of combat numbers starts, and its values.
const COL_RIGHT := 168.0
const COL_RIGHT_VALUE := 98.0
## The room kept between a left-hand value and the right-hand column's label.
const COL_GAP := 8.0
## The window's height.
const BASE_H := 164.0

## Where the last row ended when the window was last drawn (for checking it fits).
var content_end := 0.0

func _init() -> void:
	super("Character", Vector2(330, BASE_H))

func _draw_body() -> void:
	var me := Game.me
	var s := me.stats
	var y := 52.0
	# the long numbers get a row each, so they line up with the values above
	y = _row(y, "Hearts", "%d / %d" % [me.health.hp, me.max_hp()])
	y = _row(y, "Mana", "%d / %d" % [me.mp, me.max_mp()])
	y = _divider(y)
	# combat numbers in two columns
	var dmg := me.damage_range()
	y = _pair(y, ["Damage", "%d ~ %d" % [dmg.x, dmg.y], Palette.SUN], ["Critical Rate", "%d%%" % roundi(CharacterStats.crit_rate(s) * 100)])
	y = _pair(y, ["Weapon Attack", str(s.attack)], ["Magic Attack", str(s.magic_attack)])
	y = _row(y, "Speed", "%d%%" % roundi(CharacterStats.speed_multiplier(s) * 100))
	content_end = y

## A label and its value, the value `value_x` from the label (so values line up in columns),
## shrunk if it's wider than `value_w`.
func _row(y: float, label: String, value: String, col := Palette.MIST, x := 0.0, value_x := COL_VALUE, step := ROW_H, value_w := INF) -> float:
	DrawUtil.text(self, Game.ui_font, Vector2(PAD + 2 + x, y), label, 12, Palette.MUTED, 1)
	DrawUtil.text(self, Game.ui_font, Vector2(PAD + x + value_x, y), value, DrawUtil.fit_size(Game.ui_font, value, 12, value_w, 9), col, 1, 3, Color(Palette.NIGHT, 0.6))
	return y + step

## Two rows side by side, each [label, value] or [label, value, colour], their values in the
## same columns as every other row's. A long value shrinks rather than run into the right-hand
## label or the frame.
func _pair(y: float, left: Array, right: Array) -> float:
	_row(y, left[0], left[1], left[2] if left.size() > 2 else Palette.MIST, 0.0, COL_VALUE, ROW_H, COL_RIGHT - COL_VALUE - COL_GAP)
	return _row(y, right[0], right[1], right[2] if right.size() > 2 else Palette.MIST, COL_RIGHT, COL_RIGHT_VALUE, ROW_H, size.x - PAD * 2 - COL_RIGHT - COL_RIGHT_VALUE)

func _divider(y: float) -> float:
	draw_line(Vector2(PAD, y - 8), Vector2(size.x - PAD, y - 8), Color(Palette.SUN, 0.35), 1.0)
	return y + 6
