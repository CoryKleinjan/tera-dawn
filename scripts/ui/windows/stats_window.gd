class_name TDStatsWindow
extends TDWindow
## Character info (S): job, level, HP/MP, the four base stats with what gear adds, unspent
## Ability Points with a "+" per stat, and everything the stats work out to in combat.

const ROW_H := 17.0
const COL_VALUE := 112.0

func _init() -> void:
	super("Character", Vector2(250, 462))

func _draw_body() -> void:
	var s := Game.me.stats
	var y := 52.0
	y = _row(y, "Job", Game.me.job.display_name)
	y = _row(y, "Level", str(Game.me.level))
	y = _row(y, "Guild", Game.me.guild if Game.me.guild != "" else "-")
	y = _row(y, "Fame", str(Game.me.fame), Palette.GOOD if Game.me.fame > 0 else (Palette.WARN if Game.me.fame < 0 else Palette.MIST))
	y = _row(y, "EXP", "%d / %d" % [Game.me.xp, Game.me.xp_need()])
	y = _row(y, "HP", "%d / %d" % [Game.me.health.hp, Game.me.max_hp()])
	y = _row(y, "MP", "%d / %d" % [Game.me.mp, Game.me.max_mp()])
	y = _divider(y)
	y = _row(y, "Ability Points", str(Game.me.ap), Palette.SUN if Game.me.ap > 0 else Palette.MIST)
	for stat in StatBlock.BASE:
		var extra := s.value(stat) - Game.me.base.value(stat)
		var text := str(s.value(stat)) + (" (+%d)" % extra if extra > 0 else "")
		var main := stat == StringName(Game.me.job.primary_stat)
		y = _row(y, StatBlock.LABELS[stat], text, Palette.SUN if main else Palette.MIST)
		if Game.me.ap > 0:
			plus_button(Vector2(size.x - PAD - 20, y - ROW_H - 15), Net.ask.bind(&"req_add_ap", [stat]))
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
	DrawUtil.text(self, Game.ui_font, Vector2(PAD + 2, y), label, 12, Palette.MUTED, 1)
	DrawUtil.text(self, Game.ui_font, Vector2(PAD + COL_VALUE, y), value, 12, col, 1, 3, Color(Palette.NIGHT, 0.6))
	return y + ROW_H

func _divider(y: float) -> float:
	draw_line(Vector2(PAD, y - 8), Vector2(size.x - PAD, y - 8), Color(Palette.SUN, 0.35), 1.0)
	return y + 6
