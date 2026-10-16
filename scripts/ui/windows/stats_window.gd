class_name TDStatsWindow
extends TDWindow
## Character info (S): job, HP/MP, unspent Dawn Essence, the four base stats with what gear
## adds and what the next point of each costs, a "+" per stat the essence pays for (and Auto,
## once you have a job), and everything the stats work out to in combat.

const ROW_H := 17.0
## The Dawn Essence row and the four stat rows are taller, so each "+" (STAT_PLUS tall)
## has a gap above and below it.
const STAT_ROW_H := 20.0
const STAT_PLUS := 16.0
## How far above a row's baseline the middle of its text sits (12 px text).
const TEXT_MID := 4.0
const COL_VALUE := 112.0
## Where the right-hand column of combat numbers starts, and its values.
const COL_RIGHT := 168.0
const COL_RIGHT_VALUE := 98.0
## The room kept between a left-hand value and the right-hand column's label.
const COL_GAP := 8.0
## The window's height.
const BASE_H := 357.0
const AUTO_SIZE := Vector2(46, 20)

## Where the last row ended when the window was last drawn (for checking it fits).
var content_end := 0.0
## The Auto button drawn last frame (empty when there isn't one).
var auto_rect := Rect2()

func _init() -> void:
	super("Character", Vector2(330, BASE_H))

func _draw_body() -> void:
	var s := Game.me.stats
	var y := 52.0
	y = _pair(y, ["Job", Game.me.job.display_name],
		["Fame", str(Game.me.fame), Palette.GOOD if Game.me.fame > 0 else (Palette.WARN if Game.me.fame < 0 else Palette.MIST)])
	# the long numbers get a row each, so they line up with the values above
	y = _row(y, "Guild", Game.me.guild if Game.me.guild != "" else "-")
	y = _row(y, "HP", "%d / %d" % [Game.me.health.hp, Game.me.max_hp()])
	y = _row(y, "MP", "%d / %d" % [Game.me.mp, Game.me.max_mp()])
	y = _divider(y)
	auto_rect = Rect2()
	if can_buy_any(Game.me) and not Game.me.job.is_starting_job():
		# left of the "+" column, so it never touches the STR "+" under it
		auto_rect = Rect2(Vector2(_plus_x() - 6 - AUTO_SIZE.x, y - TEXT_MID - AUTO_SIZE.y / 2.0), AUTO_SIZE)
		add_button(auto_rect, "Auto", auto_assign, true, true)
	y = _row(y, "Dawn Essence", str(Game.me.essence), Palette.SUN if Game.me.essence > 0 else Palette.MIST, 0.0, COL_VALUE, STAT_ROW_H)
	var main_stats: Array = Game.me.job.damage_stats() if not Game.me.job.uses_best_stat else [Game.me.job.damage_stat(s)]
	for stat in StatBlock.BASE:
		var extra := s.value(stat) - Game.me.base.value(stat)
		var text := str(s.value(stat)) + (" (+%d)" % extra if extra > 0 else "")
		var price := Game.me.ap.price(stat)
		# the next point's price, left of the "+" (dim when the essence doesn't cover it)
		DrawUtil.text(self, Game.ui_font, Vector2(_plus_x() - 5, y), str(price), 11,
			Palette.MIST if Game.me.essence >= price else Palette.MUTED, -1, 3, Color(Palette.NIGHT, 0.6))
		if Game.me.essence >= price:
			plus_button(Vector2(_plus_x(), y - TEXT_MID - STAT_PLUS / 2.0), Net.ask.bind(&"req_buy_stat", [stat]), STAT_PLUS)
		y = _row(y, StatBlock.LABELS[stat], text, Palette.SUN if stat in main_stats else Palette.MIST, 0.0, COL_VALUE, STAT_ROW_H)
	y = _divider(y - STAT_ROW_H + ROW_H)
	# combat numbers in two columns, so the window ends above the status bar's HP
	var dmg := Game.me.damage_range()
	y = _pair(y, ["Damage", "%d ~ %d" % [dmg.x, dmg.y], Palette.SUN], ["Critical Rate", "%d%%" % roundi(CharacterStats.crit_rate(s) * 100)])
	y = _pair(y, ["Weapon Attack", str(s.attack)], ["Magic Attack", str(CharacterStats.magic_attack(s, Game.me.job))])
	y = _pair(y, ["Weapon Defense", str(s.defense)], ["Magic Defense", str(s.magic_defense)])
	y = _pair(y, ["Accuracy", str(CharacterStats.accuracy(s))], ["Avoidability", str(CharacterStats.avoid(s))])
	y = _pair(y, ["Speed", "%d%%" % roundi(CharacterStats.speed_multiplier(s) * 100)], ["Jump", "%d%%" % roundi(CharacterStats.jump_multiplier(s) * 100)])
	content_end = y

## Spends essence on the job's damage stats the way AbilityPoints.auto does. The server does
## the spending.
func auto_assign() -> void:
	Net.ask(&"req_auto_stats")

## Whether `c`'s essence pays for the next point of any base stat.
static func can_buy_any(c: Character) -> bool:
	return StatBlock.BASE.any(func(stat: StringName) -> bool: return c.essence >= c.ap.price(stat))

## Where the column of "+" buttons starts.
func _plus_x() -> float:
	return size.x - PAD - 2 - STAT_PLUS

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
