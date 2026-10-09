extends Node
## Prints how many hits each job's main attack takes against monsters of its level, and how
## many kills a level takes. Run: godot --headless --path . res://tests/balance_report.tscn

func _ready() -> void:
	var by_level := {}
	for m: MonsterDef in Content.monsters.values():
		if not m.boss and m.splits_into == null or not m.boss:
			by_level[m.level] = by_level.get(m.level, []) + [m]
	var levels := by_level.keys()
	levels.sort()
	print("lvl  monster              hp    exp  kills/lvl  " + "  ".join(Balance.LINES.map(func(j: StringName) -> String: return String(j).substr(0, 7).rpad(7))))
	for lvl: int in levels:
		for m: MonsterDef in by_level[lvl]:
			var row := "%3d  %-18s %6d %5d %8.1f   " % [lvl, m.id, m.max_hp, m.exp_reward, Balance.kills_per_level(lvl, m)]
			for j in Balance.LINES:
				row += "%7.1f  " % Balance.hits_to_kill(Balance.typical(j, maxi(1, lvl)), m)
			print(row)
	# damage a level-L character's main attack does per cast, averaged over the jobs
	var dmg := []
	for lvl in range(1, 41):
		var total := 0.0
		for j in Balance.LINES:
			var c := Balance.typical(j, lvl)
			var a: Array = Balance.main_attack(c)
			total += Balance._average(c, a[0], a[1]) * a[0].hits
		dmg.append(roundi(total / Balance.LINES.size()))
	print("DAMAGE ", dmg)
	for j in Balance.LINES:
		for lvl in [10, 20, 30]:
			var c := Balance.typical(j, lvl)
			var a: Array = Balance.main_attack(c)
			print("%s %d: %s Lv.%d, weapon %s, damage %s, magic %s" % [j, lvl, a[0].id, a[1], c.weapon().id if c.weapon() else "-", c.damage_range(), c.magic_range()])
	get_tree().quit()
