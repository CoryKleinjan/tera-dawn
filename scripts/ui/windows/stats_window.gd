class_name TDStatsWindow
extends TDWindow
## Character info (S): job, level, HP/MP, the four base stats with what gear adds, unspent
## Ability Points with a "+" per stat (and Auto, once you have a job), and everything the
## stats work out to in combat. A Beginner also sees the job paths and the stats each one
## still needs, so points don't go where they shut a path.

const ROW_H := 17.0
## The Ability Points row and the four stat rows are taller, so each "+" (STAT_PLUS tall)
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
## The window's height without the job paths, and the paths' rows.
const BASE_H := 374.0
const PATH_ROW_H := 13.0
const PATHS_TOP := 18.0
const AUTO_SIZE := Vector2(46, 20)

## Where the last row ended when the window was last drawn (for checking it fits).
var content_end := 0.0
## The Auto button drawn last frame (empty when there isn't one).
var auto_rect := Rect2()

func _init() -> void:
	super("Character", Vector2(330, BASE_H))

func _process(delta: float) -> void:
	if visible:
		size.y = wanted_height()
	super(delta)

func toggle() -> void:
	size.y = wanted_height()
	super()

## The window's height for the character as they are now: taller for a Beginner, who sees
## the job paths.
func wanted_height() -> float:
	var paths := _paths()
	return BASE_H + (PATHS_TOP + paths.size() * PATH_ROW_H if not paths.is_empty() else 0.0)

## The jobs a Beginner could advance into (none once you have a job).
func _paths() -> Array[JobDef]:
	if Game.me.job == null or not Game.me.job.is_starting_job():
		return []
	return JobDef.paths_from(Game.me.job.id)

func _draw_body() -> void:
	var s := Game.me.stats
	var y := 52.0
	y = _pair(y, ["Job", Game.me.job.display_name], ["Level", str(Game.me.level)])
	y = _pair(y, ["Guild", Game.me.guild if Game.me.guild != "" else "-"],
		["Fame", str(Game.me.fame), Palette.GOOD if Game.me.fame > 0 else (Palette.WARN if Game.me.fame < 0 else Palette.MIST)])
	# the long numbers get a row each, so they line up with the values above
	y = _row(y, "EXP", TDStatusBar.MAX_LEVEL_TEXT if Game.me.at_max_level() else "%d / %d" % [Game.me.xp, Game.me.xp_need()])
	y = _row(y, "HP", "%d / %d" % [Game.me.health.hp, Game.me.max_hp()])
	y = _row(y, "MP", "%d / %d" % [Game.me.mp, Game.me.max_mp()])
	y = _divider(y)
	auto_rect = Rect2()
	if Game.me.ap.points > 0 and not Game.me.job.is_starting_job():
		# left of the "+" column, so it never touches the STR "+" under it
		auto_rect = Rect2(Vector2(_plus_x() - 6 - AUTO_SIZE.x, y - TEXT_MID - AUTO_SIZE.y / 2.0), AUTO_SIZE)
		add_button(auto_rect, "Auto", auto_assign, true, true)
	y = _row(y, "Ability Points", str(Game.me.ap.points), Palette.SUN if Game.me.ap.points > 0 else Palette.MIST, 0.0, COL_VALUE, STAT_ROW_H)
	var main_stats: Array = Game.me.job.damage_stats() if not Game.me.job.uses_best_stat else [Game.me.job.damage_stat(s)]
	for stat in StatBlock.BASE:
		var extra := s.value(stat) - Game.me.base.value(stat)
		var text := str(s.value(stat)) + (" (+%d)" % extra if extra > 0 else "")
		if Game.me.ap.points > 0:
			plus_button(Vector2(_plus_x(), y - TEXT_MID - STAT_PLUS / 2.0), Net.ask.bind(&"req_add_ap", [stat]), STAT_PLUS)
		y = _row(y, StatBlock.LABELS[stat], text, Palette.SUN if stat in main_stats else Palette.MIST, 0.0, COL_VALUE, STAT_ROW_H)
	y = _divider(y - STAT_ROW_H + ROW_H)
	# combat numbers in two columns, so the window ends above the status bar's HP
	var dmg := Game.me.damage_range()
	y = _pair(y, ["Damage", "%d ~ %d" % [dmg.x, dmg.y], Palette.SUN], ["Critical Rate", "%d%%" % roundi(CharacterStats.crit_rate(s) * 100)])
	y = _pair(y, ["Weapon Attack", str(s.attack)], ["Magic Attack", str(CharacterStats.magic_attack(s, Game.me.job))])
	y = _pair(y, ["Weapon Defense", str(s.defense)], ["Magic Defense", str(s.magic_defense)])
	y = _pair(y, ["Accuracy", str(CharacterStats.accuracy(s))], ["Avoidability", str(CharacterStats.avoid(s))])
	y = _pair(y, ["Speed", "%d%%" % roundi(CharacterStats.speed_multiplier(s) * 100)], ["Jump", "%d%%" % roundi(CharacterStats.jump_multiplier(s) * 100)])
	content_end = _draw_paths(y)

## A Beginner's job paths: the ones whose stats are there in green, the rest with what's
## still short ("Thief: 25 LUK (you have 4)"). Returns where the rows end.
func _draw_paths(y: float) -> float:
	var paths := _paths()
	if paths.is_empty():
		return y
	_divider(y)
	var top := y + 6
	DrawUtil.text(self, Game.ui_font, Vector2(PAD + 2, top), "Job paths (base stats needed)", 11, Palette.MUTED, 1)
	for i in paths.size():
		var ready := Game.me.stats_short_of(paths[i]).is_empty()
		DrawUtil.text(self, Game.ui_font, Vector2(PAD + 2, top + (i + 1) * PATH_ROW_H), path_text(Game.me, paths[i]), 11,
			Palette.GOOD if ready else Palette.MIST, 1, 3, Color(Palette.NIGHT, 0.6))
	y += PATHS_TOP + paths.size() * PATH_ROW_H
	return y

## One path's line for character `c`: every stat it asks for when they're all there,
## otherwise only the ones still short and what `c` has of each.
static func path_text(c: Character, j: JobDef) -> String:
	var short := c.stats_short_of(j)
	var bits := []
	if short.is_empty():
		var lines := j.requirement_lines()
		for i in range(1, lines.size()): # after "Level N"
			bits.append(lines[i])
	for stat in StatBlock.BASE:
		if short.has(stat):
			bits.append("%d %s (you have %d)" % [short[stat], StatBlock.LABELS[stat], c.base.value(stat)])
	return "%s: %s" % [j.display_name, ", ".join(bits) if not bits.is_empty() else "ready"]

## Spends every Ability Point the way AbilityPoints.auto_plan says (all in the job's one
## stat). The server does the spending.
func auto_assign() -> void:
	var plan := Game.me.ap.auto_plan()
	for stat in plan:
		Net.ask(&"req_add_ap_many", [stat, plan[stat]])

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
