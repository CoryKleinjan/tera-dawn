extends TestCase
## MonsterStrength and WorldRoutes.steps_from_town: towns are 0 steps out and their fields 1,
## shortcuts and one-way ways home (a boss arena's) never bring a map nearer; a monster is its own strength on the nearest map it
## lives on, PER_MAP stronger for each map farther out, and bosses never change.

var steps: Dictionary

func before_each() -> void:
	steps = WorldRoutes.steps_from_town()

func test_towns_are_zero_and_fields_count_up() -> void:
	for m: MapDef in Content.maps.values():
		if m.town and not m.interior:
			check_eq(steps.get(m.id, -1), 0, "%s is a town" % m.id)
		elif steps.has(m.id):
			check(steps[m.id] >= 1, "%s is a step or more from a town" % m.id)
			var nearer := false
			for p in m.portals:
				var two_way := not (p.one_way or p.after_boss)
				nearer = nearer or (not p.is_shortcut() and two_way and steps.get(p.target_map, 99) == steps[m.id] - 1)
			for other: MapDef in Content.maps.values():
				for p in other.portals:
					nearer = nearer or (p.target_map == m.id and not p.is_shortcut() and steps.get(other.id, 99) == steps[m.id] - 1)
			check(nearer, "%s: a neighbour is one step nearer a town, not through a shortcut or a one-way way home" % m.id)

func test_every_spawn_is_its_own_strength_at_home_and_stronger_farther_out() -> void:
	for map: MapDef in Content.maps.values():
		if not steps.has(map.id):
			continue
		for s in map.spawns:
			var m := s.monster
			if m == null:
				continue
			var got := MonsterStrength.on_map(m, map.id, steps)
			if m.boss:
				check_near(got, 1.0, "%s: a boss keeps its own numbers on %s" % [m.id, map.id])
				continue
			var farther: int = steps[map.id] - MonsterStrength.home_steps(m, steps)
			check(farther >= 0, "%s: %s is no nearer a town than its home" % [m.id, map.id])
			check_near(got, pow(1.0 + MonsterStrength.PER_MAP, farther), "%s on %s (%d maps past its home)" % [m.id, map.id, farther])

func test_an_unknown_map_leaves_it_as_it_is() -> void:
	var m := MonsterDef.new()
	check_near(MonsterStrength.on_map(m, &"nowhere", steps), 1.0, "no map, no change")
	check_near(MonsterStrength.on_map(null, &"nowhere", steps), 1.0, "no monster")

func test_scaled_rounds_and_never_drops_to_zero() -> void:
	check_eq(MonsterStrength.scaled(100, 1.15), 115, "15% more")
	check_eq(MonsterStrength.scaled(100, 1.15 * 1.15), 132, "two maps farther")
	check_eq(MonsterStrength.scaled(0, 1.0), 1, "at least 1")
