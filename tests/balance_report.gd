extends Node
## Prints how many hits each job's main attack takes against monsters of its tier (see
## Balance). Run: godot --headless --path . res://tests/balance_report.tscn

func _ready() -> void:
	var monsters: Array = Content.monsters.values()
	monsters.sort_custom(func(a: MonsterDef, b: MonsterDef) -> bool: return [a.level, a.id] < [b.level, b.id])
	print("tier monster              hp  boss  " + "  ".join(Balance.lines().map(func(j: StringName) -> String: return String(j).substr(0, 7).rpad(7))))
	for m: MonsterDef in monsters:
		var row := "%3d  %-18s %6d  %-4s  " % [m.level, m.id, m.max_hp, "yes" if m.boss else ""]
		for j in Balance.lines():
			row += "%7.1f  " % Balance.hits_to_kill(Balance.typical(j, maxi(1, m.level)), m)
		print(row)
	for j in Balance.lines():
		for tier in [1, Balance.JOB_TIER, 20, Balance.TOP_TIER]:
			var c := Balance.typical(j, tier)
			var w := c.gear.weapon()
			print("%s %d: weapon %s tier %d, damage %s, swing %.1f" % [j, tier, w.id if w else "-",
				c.equipment.at(&"weapon").tier if w else 0, c.damage_range(), Balance.swing_damage(c)])
	get_tree().quit()
