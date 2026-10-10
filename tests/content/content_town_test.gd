extends TestCase
## Towns read like a classic side-scroller street: no monsters, buildings in a row with open
## ground between them (measured from their real pictures, so new art that's wider or
## narrower shows up here), exits standing in the open, background houses spaced out and
## never straight behind a building, and no long empty stretches of street.

const Scan := preload("res://tests/content/content_scan.gd")

## Least open ground between two buildings, in game pixels (the hero is about 85 wide).
const MIN_BUILDING_GAP := 100.0
## Half a portal's width, plus a little room so it doesn't touch a building's edge.
const PORTAL_CLEAR := 50.0
## The longest stretch of street with nothing on it: no building, portal, NPC or sign.
const MAX_EMPTY := 320.0

func _towns() -> Array[MapDef]:
	var out: Array[MapDef] = []
	for m: MapDef in Content.maps.values():
		if m.town and not m.interior:
			out.append(m)
	return out

func _streets() -> Array[MapDef]:
	return _towns().filter(func(m: MapDef) -> bool: return not m.buildings.is_empty())

## Buildings on platform `plat`, left to right.
func _row(m: MapDef, plat: int) -> Array[BuildingPlacement]:
	var out: Array[BuildingPlacement] = []
	for b in m.buildings:
		if b.platform == plat:
			out.append(b)
	out.sort_custom(func(a: BuildingPlacement, b: BuildingPlacement) -> bool: return a.span().x < b.span().x)
	return out

func test_there_are_towns_with_streets() -> void:
	check(_streets().size() >= 7, "the start village and six hub towns have buildings (found %d)" % _streets().size())
	check(Content.map(Character.START_MAP).town, "the start map is a town")

func test_towns_have_no_monsters() -> void:
	for m in _towns():
		check(m.spawns.is_empty(), "%s: a town has %d monster spawns" % [Scan.where(m), m.spawns.size()])

func test_buildings_keep_apart_inside_the_map() -> void:
	for m in _streets():
		var plats := {}
		for b in m.buildings:
			plats[b.platform] = true
			check(b.building != null and b.building.texture != null, "%s: a building has no picture" % Scan.where(m))
		for plat in plats:
			var row := _row(m, plat)
			for i in row.size():
				var s := row[i].span()
				check(s.x >= 0.0 and s.y <= m.width, "%s: %s spans x %d-%d, outside the map (0-%d)" % [Scan.where(m), row[i].building.id, s.x, s.y, m.width])
				if i > 0:
					var gap := s.x - row[i - 1].span().y
					check(gap >= MIN_BUILDING_GAP, "%s: %s and %s are %d px apart (want %d+)" % [Scan.where(m), row[i - 1].building.id, row[i].building.id, gap, MIN_BUILDING_GAP])

func test_exits_stand_in_the_open() -> void:
	for m in _streets():
		for p in m.portals:
			if p.door:
				continue
			for b in m.buildings:
				if b.platform != p.platform:
					continue
				var s := b.span()
				check(p.x + PORTAL_CLEAR <= s.x or p.x - PORTAL_CLEAR >= s.y,
					"%s: the portal to %s (x %d) stands in front of %s (x %d-%d)" % [Scan.where(m), p.target_map, p.x, b.building.id, s.x, s.y])

func test_doors_are_in_their_building() -> void:
	for m in _streets():
		for p in m.portals:
			if p.door:
				check(m.buildings.any(func(b: BuildingPlacement) -> bool: return b.x == p.x and b.platform == p.platform),
					"%s: the door to %s (x %d) has no building there" % [Scan.where(m), p.target_map, p.x])

func test_streets_have_no_long_empty_stretches() -> void:
	for m in _streets():
		var spans: Array[Vector2] = [Vector2(0, 0), Vector2(m.width, m.width)]
		for b in m.buildings:
			if b.platform == 0:
				spans.append(b.span())
		for p in m.portals:
			if p.platform == 0:
				spans.append(Vector2(p.x - 34.0, p.x + 34.0))
		for n in m.npcs:
			if n.platform == 0:
				spans.append(Vector2(n.x - 30.0, n.x + 30.0))
		if m.sign_text != "":
			var sign_x := SceneryBuilder.sign_post_x(m)
			spans.append(Vector2(sign_x - 30.0, sign_x + 30.0))
		spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var reach := 0.0
		for s in spans:
			check(s.x - reach <= MAX_EMPTY, "%s: x %d-%d is empty street (%d px, want at most %d)" % [Scan.where(m), reach, s.x, s.x - reach, MAX_EMPTY])
			reach = maxf(reach, s.y)

func test_background_houses_are_spaced_out() -> void:
	var seen := 0
	for m in _streets():
		for rule in m.biome.town_decor:
			var w := SceneryBuilder.back_house_width(rule)
			var slots := SceneryBuilder.back_house_slots(rule, m)
			seen += slots.size()
			for i in slots.size():
				var x := slots[i]
				check(x - w * 0.5 >= 0.0 and x + w * 0.5 <= m.width, "%s: a background house at x %d is outside the map" % [Scan.where(m), x])
				if i > 0:
					check(x - slots[i - 1] - w >= SceneryBuilder.BACK_HOUSE_GAP - 0.01,
						"%s: background houses at x %d and %d are too close" % [Scan.where(m), slots[i - 1], x])
				for b in m.buildings:
					var s := b.span()
					check(x + w * 0.5 + SceneryBuilder.BACK_HOUSE_CLEAR <= s.x + 0.01 or x - w * 0.5 - SceneryBuilder.BACK_HOUSE_CLEAR >= s.y - 0.01,
						"%s: a background house at x %d stands behind %s (x %d-%d)" % [Scan.where(m), x, b.building.id, s.x, s.y])
	check(seen > 0, "some town has background houses")
