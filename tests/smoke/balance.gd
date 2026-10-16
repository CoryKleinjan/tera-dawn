extends SmokeArea
## Balance: every job against monsters of its level, kills per level, the EXP curve and the
## achievements' Steam ids.

## Every job can fight monsters of its level, and levels take a sensible number of kills
## (see Balance and tests/balance_report.tscn).
func check() -> void:
	var worst := ""
	var slow := ""
	for m: MonsterDef in Content.monsters.values():
		if m.boss:
			continue
		# a slime's bits are meant to pop in one hit, so only the high end applies to them
		var low := 0.0 if _only_split_from(m) else Balance.BAND.x - 0.2
		for j in Balance.lines():
			var hits := Balance.hits_to_kill(Balance.typical(j, m.level), m)
			if hits < low or hits > Balance.BAND.y:
				worst += " %s/%s %.1f" % [j, m.id, hits]
		var kills := Balance.kills_per_level(m.level, m)
		# a slime's bits only come with the slime (it pays for both), so nobody levels on bits
		if kills > 1000.0 and not _only_split_from(m):
			slow += " %s %.0f" % [m.id, kills]
	_check(worst == "", "every job beats monsters of its level in a few hits%s" % worst)
	_check(slow == "", "no monster takes too many kills a level%s" % slow)
	var c := Character.new()
	_check(c.xp_need(1) < 100 and c.xp_need(30) > c.xp_need(20) * 2, "early levels are quick and later ones take longer")
	var steam_ids := {}
	var achievements := Achievements.all()
	for a in achievements:
		steam_ids[a.steam] = true
	_check(steam_ids.size() == achievements.size() and not steam_ids.has(""), "every achievement has its own Steam id")

## Whether `m` only appears when another monster splits into it (a slime's bits).
func _only_split_from(m: MonsterDef) -> bool:
	var split := false
	for other: MonsterDef in Content.monsters.values():
		split = split or other.splits_into == m
	for map: MapDef in Content.maps.values():
		for sp in map.spawns:
			if sp.monster == m:
				return false
	return split
