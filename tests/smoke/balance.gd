extends SmokeArea
## Balance: every job against monsters of its tier, kills per tier, the Dawn Essence prices
## and the achievements' Steam ids.

## Every job can fight monsters of its tier, and tiers take a sensible number of kills
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
		var kills := Balance.kills_per_tier(m.level, m)
		# a slime's bits only come with the slime (it pays for both), so nobody grows on bits
		if kills > 1000.0 and not _only_split_from(m):
			slow += " %s %.0f" % [m.id, kills]
	_check(worst == "", "every job beats monsters of its tier in a few hits%s" % worst)
	_check(slow == "", "no monster takes too many kills a tier%s" % slow)
	# the stat point a tier-20 or tier-30 character buys next (all in one stat, as Balance.typical)
	var at_20 := CharacterStats.stat_price(19 * CharacterStats.GROWTH_POINTS)
	var at_30 := CharacterStats.stat_price(29 * CharacterStats.GROWTH_POINTS)
	_check(CharacterStats.stat_price(0) < 100 and CharacterStats.skill_price(0) < 100 and at_30 > at_20 * 2, "the first stat points are cheap and later ones cost more")
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
