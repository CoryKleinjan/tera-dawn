extends TestCase
## The floor and platforms aren't cluttered: the biome's scattered trees, bushes, rocks and
## flowers stand wholly on their own land, clear of buildings, portals, NPCs, ropes and
## ladders, props and lanterns, never on top of each other, and only as often as the shared
## density allows (see DecorPlacement).

const Scan := preload("res://tests/content/content_scan.gd")

func _outdoor() -> Array[MapDef]:
	var out: Array[MapDef] = []
	for m: MapDef in Content.maps.values():
		if not m.interior and m.look():
			out.append(m)
	return out

func _rng(m: MapDef) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(m.id)
	return rng

func _clear(s: Vector2, a: Vector2) -> bool:
	return s.y <= a.x or s.x >= a.y

func test_maps_have_some_scenery() -> void:
	var floor_n := 0
	for m in _outdoor():
		floor_n += DecorPlacement.floor_pieces(m, _rng(m)).size()
	check(floor_n > 0, "some map has floor scenery")

func test_scenery_stands_wholly_on_its_land() -> void:
	for m in _outdoor():
		for p in DecorPlacement.floor_pieces(m, _rng(m)):
			var s := p.span()
			check(s.x >= 0.0 and s.y <= m.width, "%s: a %s at x %d hangs off the map" % [Scan.where(m), p.texture.resource_path.get_file(), p.x])
		var rng := _rng(m)
		DecorPlacement.floor_pieces(m, rng)
		for p in DecorPlacement.platform_pieces(m, rng):
			var s := p.span()
			var on := m.platforms.any(func(d: PlatformDef) -> bool:
				return is_equal_approx(d.y, p.y) and s.x >= d.x and s.y <= d.x + d.width)
			check(on, "%s: a %s at x %d hangs off its platform" % [Scan.where(m), p.texture.resource_path.get_file(), p.x])

func test_floor_scenery_keeps_clear() -> void:
	for m in _outdoor():
		var near := DecorPlacement.standing_on(m, 0)
		near.append_array(LanternPlacement.keep_clear(m))
		var back := DecorPlacement.building_spans(m, 0)
		back.append_array(LanternPlacement.keep_clear(m))
		for p in DecorPlacement.floor_pieces(m, _rng(m)):
			var s := p.span()
			for a in (back if DecorPlacement.is_back(p.rule) else near):
				check(_clear(s, a), "%s: a %s at x %d overlaps scenery at x %d-%d" % [Scan.where(m), p.texture.resource_path.get_file(), p.x, a.x, a.y])
		# the things it keeps clear of, named directly
		for p in DecorPlacement.floor_pieces(m, _rng(m)):
			var s := p.span()
			for b in m.buildings:
				if b.platform == 0:
					check(_clear(s, b.span()), "%s: a %s stands in front of or behind %s" % [Scan.where(m), p.texture.resource_path.get_file(), b.building.id])
			if DecorPlacement.is_back(p.rule):
				continue
			for n in m.npcs:
				if n.platform == 0:
					var r := LanternPlacement.npc_rect(n)
					check(_clear(s, Vector2(n.x + r.position.x, n.x + r.end.x)), "%s: a %s stands behind %s" % [Scan.where(m), p.texture.resource_path.get_file(), n.npc.id])
			for q in m.portals:
				if q.platform == 0:
					check(_clear(s, Vector2(q.x, q.x) + Vector2(-1, 1) * LanternPlacement.PORTAL_HALF), "%s: a %s stands behind a portal" % [Scan.where(m), p.texture.resource_path.get_file()])

func test_platform_scenery_keeps_clear() -> void:
	for m in _outdoor():
		var rng := _rng(m)
		DecorPlacement.floor_pieces(m, rng)
		for p in DecorPlacement.platform_pieces(m, rng):
			var i := -1
			for k in m.platforms.size():
				var d := m.platforms[k]
				if is_equal_approx(d.y, p.y) and p.x >= d.x and p.x <= d.x + d.width:
					i = k
			if i < 0:
				continue
			for a in DecorPlacement.standing_on(m, i + 1):
				check(_clear(p.span(), a), "%s: a %s on platform %d overlaps scenery at x %d-%d" % [Scan.where(m), p.texture.resource_path.get_file(), i + 1, a.x, a.y])

func test_pieces_of_a_kind_never_overlap() -> void:
	for m in _outdoor():
		var rng := _rng(m)
		var all := DecorPlacement.floor_pieces(m, rng)
		all.append_array(DecorPlacement.platform_pieces(m, rng))
		for i in all.size():
			for j in range(i + 1, all.size()):
				var a := all[i]
				var b := all[j]
				if a.rule == b.rule and is_equal_approx(a.y, b.y):
					check(_clear(a.span(), b.span()), "%s: two %s pieces overlap at x %d and %d" % [Scan.where(m), a.rule.textures[0].resource_path.get_file(), a.x, b.x])

func test_scenery_is_sparse() -> void:
	# Each rule fills at most one slot per (its nearest spacing / density) of the land.
	for m in _outdoor():
		var counts := {}
		for p in DecorPlacement.floor_pieces(m, _rng(m)):
			counts[p.rule] = counts.get(p.rule, 0) + 1
		for rule: DecorDef in counts:
			var dens := 1.0 if m.look().town_decor.has(rule) else DecorPlacement.density(m)
			var most := ceili(m.width * dens / rule.spacing.x) + 1
			check(counts[rule] <= most, "%s: %d pieces from one rule (want at most %d)" % [Scan.where(m), counts[rule], most])

func test_density_can_be_set_per_map() -> void:
	var fields := _outdoor().filter(func(f: MapDef) -> bool: return not f.town)
	var m: MapDef = fields[0].duplicate()
	m.decor_density = 0.0
	check(DecorPlacement.floor_pieces(m, _rng(m)).is_empty(), "a map with decor_density 0 has no floor scenery")
	check(DecorPlacement.platform_pieces(m, _rng(m)).is_empty(), "a map with decor_density 0 has no platform scenery")
	m.decor_density = -1.0
	check_eq(DecorPlacement.density(m), DecorPlacement.DENSITY, "-1 uses the shared density")
