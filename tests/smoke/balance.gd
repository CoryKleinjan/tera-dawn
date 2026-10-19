extends SmokeArea
## Balance: every job against monsters of its tier, and the achievements' Steam ids.

## Every job's main attack beats regular monsters of its tier (from Balance.JOB_TIER on) in a
## sensible number of hits (see Balance and tests/balance_report.tscn). Bosses take many more
## by design, so they're left out.
func check() -> void:
	var worst := ""
	for m: MonsterDef in Content.monsters.values():
		if m.boss or m.level < Balance.JOB_TIER:
			continue
		# a slime's bits are meant to pop in one hit, so only the high end applies to them
		var low := 0.0 if _only_split_from(m) else Balance.BAND.x - 0.2
		for j in Balance.lines():
			var hits := Balance.hits_to_kill(Balance.typical(j, m.level), m)
			if hits < low or hits > Balance.BAND.y:
				worst += " %s/%s %.1f" % [j, m.id, hits]
	_check(worst == "", "every job beats monsters of its tier in a few hits%s" % worst)
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
