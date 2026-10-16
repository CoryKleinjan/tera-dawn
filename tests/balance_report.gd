extends Node
## Prints how many hits each job's main attack takes against monsters of its tier (see
## Balance), and how many kills pay for a tier. Run: godot --headless --path . res://tests/balance_report.tscn

func _ready() -> void:
	var by_level := {}
	for m: MonsterDef in Content.monsters.values():
		if not m.boss and m.splits_into == null or not m.boss:
			by_level[m.level] = by_level.get(m.level, []) + [m]
	var levels := by_level.keys()
	levels.sort()
	print("tier monster              hp   ess  kills/tier " + "  ".join(Balance.lines().map(func(j: StringName) -> String: return String(j).substr(0, 7).rpad(7))))
	for lvl: int in levels:
		for m: MonsterDef in by_level[lvl]:
			var row := "%3d  %-18s %6d %5d %8.1f   " % [lvl, m.id, m.max_hp, m.essence, Balance.kills_per_tier(lvl, m)]
			for j in Balance.lines():
				row += "%7.1f  " % Balance.hits_to_kill(Balance.typical(j, maxi(1, lvl)), m)
			print(row)
	# damage a tier-T character's main attack does per cast, averaged over the jobs
	var dmg := []
	for lvl in range(1, 41):
		var total := 0.0
		for j in Balance.lines():
			var c := Balance.typical(j, lvl)
			var a: Array = Balance.main_attack(c)
			total += Balance._average(c, a[0], a[1]) * a[0].hits
		dmg.append(roundi(total / Balance.lines().size()))
	print("DAMAGE ", dmg)
	for j in Balance.lines():
		for lvl in [10, 20, 30]:
			var c := Balance.typical(j, lvl)
			var a: Array = Balance.main_attack(c)
			print("%s %d: %s Lv.%d, weapon %s, damage %s, magic %s" % [j, lvl, a[0].id, a[1], c.gear.weapon().id if c.gear.weapon() else "-", c.damage_range(), c.magic_range()])
	get_tree().quit()
