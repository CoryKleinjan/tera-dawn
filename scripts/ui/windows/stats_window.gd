class_name TDStatsWindow
extends TDWindow
## Character info (S): job, level, HP/MP, the four base stats with what gear adds, unspent
## Ability Points with a "+" per stat, and everything the stats work out to in combat.

const ROW := 17.0
const COL_VALUE := 112.0

## The "+" buttons, rebuilt each draw: stat -> Rect2.
var _plus := {}

func _init() -> void:
	super("Character", Vector2(250, 462))

func _draw_body() -> void:
	var s := Game.me.stats
	var y := 52.0
	y = _row(y, "Job", Game.me.job.display_name)
	y = _row(y, "Level", str(Game.me.level))
	y = _row(y, "Guild", Game.me.guild if Game.me.guild != "" else "-")
	y = _row(y, "Fame", str(Game.me.fame), Color("8cf0a6") if Game.me.fame > 0 else (Color("ffb38a") if Game.me.fame < 0 else Palette.MIST))
	y = _row(y, "EXP", "%d / %d" % [Game.me.xp, Game.me.xp_need()])
	y = _row(y, "HP", "%d / %d" % [Game.me.health.hp, Game.me.max_hp()])
	y = _row(y, "MP", "%d / %d" % [Game.me.mp, Game.me.max_mp()])
	y = _divider(y)
	y = _row(y, "Ability Points", str(Game.me.ap), Palette.SUN if Game.me.ap > 0 else Palette.MIST)
	_plus.clear()
	for stat in StatBlock.BASE:
		var extra := s.value(stat) - Game.me.base.value(stat)
		var text := str(s.value(stat)) + (" (+%d)" % extra if extra > 0 else "")
		var main := stat == StringName(Game.me.job.primary_stat)
		y = _row(y, StatBlock.LABELS[stat], text, Palette.SUN if main else Palette.MIST)
		if Game.me.ap > 0:
			var r := Rect2(size.x - PAD - 20, y - ROW - 14, 18, 18)
			_plus[stat] = r
			draw_texture_rect(UiSkin.tex("stat_plus"), r, false, Color(1.25, 1.2, 1.1) if r.has_point(_hover) else Color.WHITE)
	y = _divider(y)
	var dmg := Game.me.damage_range()
	y = _row(y, "Damage", "%d ~ %d" % [dmg.x, dmg.y], Palette.SUN)
	y = _row(y, "Weapon Attack", str(s.attack))
	y = _row(y, "Magic Attack", str(CharacterStats.magic_attack(s)))
	y = _row(y, "Weapon Defense", str(s.defense))
	y = _row(y, "Magic Defense", str(s.magic_defense))
	y = _row(y, "Accuracy", str(CharacterStats.accuracy(s)))
	y = _row(y, "Avoidability", str(CharacterStats.avoid(s)))
	y = _row(y, "Speed", "%d%%" % roundi(CharacterStats.speed_multiplier(s) * 100))
	y = _row(y, "Jump", "%d%%" % roundi(CharacterStats.jump_multiplier(s) * 100))
	_row(y, "Critical Rate", "%d%%" % roundi(CharacterStats.crit_rate(s) * 100))

func _row(y: float, label: String, value: String, col := Palette.MIST) -> float:
	DrawUtil.text(self, Game.ui_font, Vector2(PAD + 2, y), label, 12, Color("c9b8d9"), 1)
	DrawUtil.text(self, Game.ui_font, Vector2(PAD + COL_VALUE, y), value, 12, col, 1, 3, Color(Palette.NIGHT, 0.6))
	return y + ROW

func _divider(y: float) -> float:
	draw_line(Vector2(PAD, y - 8), Vector2(size.x - PAD, y - 8), Color(Palette.SUN, 0.35), 1.0)
	return y + 6

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	for stat in _plus:
		if _plus[stat].has_point(at):
			Net.ask(&"req_add_ap", [stat])
			return
