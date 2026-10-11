extends TestCase
## Lanterns are few and stand in open ground: never more than one per spacing of a map's
## width, spread apart, and never in front of or behind a building, portal, rope or ladder,
## prop, NPC or low platform (see LanternPlacement). Background houses and the floor's
## trees, bushes and rocks give way to them.

const Scan := preload("res://tests/content/content_scan.gd")

func _lit_maps() -> Array[MapDef]:
	var out: Array[MapDef] = []
	for m: MapDef in Content.maps.values():
		if LanternPlacement.spacing(m) > 0.0 and LanternPlacement.post_size(m) != Vector2.ZERO:
			out.append(m)
	return out

func test_maps_have_a_few_lanterns() -> void:
	check(not _lit_maps().is_empty(), "some map has lanterns")
	for m in _lit_maps():
		var n := LanternPlacement.slots(m).size()
		var most := maxi(1, roundi(m.width / LanternPlacement.spacing(m)))
		check(n >= 1 and n <= most, "%s: %d lanterns (want 1 to %d)" % [Scan.where(m), n, most])

func test_rooms_have_no_lanterns() -> void:
	for m: MapDef in Content.maps.values():
		if m.interior:
			check(LanternPlacement.slots(m).is_empty(), "%s: a room has lanterns" % Scan.where(m))

func test_lanterns_stand_apart_and_inside_the_map() -> void:
	for m in _lit_maps():
		var xs := LanternPlacement.slots(m)
		var half := LanternPlacement.post_size(m).x * 0.5
		for i in xs.size():
			check(xs[i] - half >= 0.0 and xs[i] + half <= m.width, "%s: a lantern at x %d is outside the map" % [Scan.where(m), xs[i]])
			if i > 0:
				check(xs[i] - xs[i - 1] >= LanternPlacement.spacing(m) * 0.5,
					"%s: lanterns at x %d and %d are too close" % [Scan.where(m), xs[i - 1], xs[i]])

func test_lanterns_stand_clear_of_other_scenery() -> void:
	for m in _lit_maps():
		var half := LanternPlacement.post_size(m).x * 0.5
		var taken := LanternPlacement.blocked(m)
		for x in LanternPlacement.slots(m):
			for s in taken:
				check(x + half <= s.x or x - half >= s.y,
					"%s: the lantern at x %d overlaps scenery at x %d-%d" % [Scan.where(m), x, s.x, s.y])
		# and the things it checks against, named directly
		for x in LanternPlacement.slots(m):
			for b in m.buildings:
				if b.platform == 0:
					var s := b.span()
					check(x + half <= s.x or x - half >= s.y, "%s: the lantern at x %d stands in front of %s" % [Scan.where(m), x, b.building.id])
			for p in m.portals:
				if p.platform == 0:
					check(absf(x - p.x) >= half + LanternPlacement.PORTAL_HALF, "%s: the lantern at x %d stands on a portal" % [Scan.where(m), x])
			for n in m.npcs:
				if n.platform == 0:
					check(absf(x - n.x) >= half + LanternPlacement.NPC_HALF, "%s: the lantern at x %d stands behind %s" % [Scan.where(m), x, n.npc.id])
			for c in m.climbables:
				if c.bottom >= m.ground_y - 1.0:
					check(absf(x - c.x) >= half + LanternPlacement.CLIMB_HALF, "%s: the lantern at x %d stands behind a rope or ladder" % [Scan.where(m), x])

func test_floor_decor_keeps_off_lanterns() -> void:
	for m in _lit_maps():
		var clear := LanternPlacement.keep_clear(m)
		check_eq(clear.size(), LanternPlacement.slots(m).size(), "%s: every lantern keeps its ground clear" % Scan.where(m))
		for c in clear:
			check(c.y - c.x > LanternPlacement.post_size(m).x, "%s: a lantern's clear ground is wider than the post" % Scan.where(m))
