extends TestCase
## The world's shape (Cory, 2026-10-11): each region (major zone) has a main city in it; two
## neighbouring regions are joined by exactly one crossing on foot; a region you can't walk to
## is reached by ship; every map of a region can be walked to from its city without leaving the
## region; and each region's zone map (its part of the world map) shows all of its maps.

const Scan := preload("res://tests/content/content_scan.gd")

func test_every_region_has_a_city_of_its_own() -> void:
	for r: RegionDef in Content.regions.values():
		var c: MapDef = Content.maps.get(r.capital)
		if check(c != null, "%s: capital %s is not a map" % [r.id, r.capital]):
			check(c.town and not c.interior and c.region == r.id, "%s: capital %s must be a town in the region" % [r.id, c.id])

func test_zone_maps_show_every_map_of_their_region() -> void:
	for r: RegionDef in Content.regions.values():
		check(r.zone_rect.has_area(), "%s: no zone_rect" % r.id)
		var inside := Rect2(Vector2.ZERO, TDWorldMapWindow.WORLD)
		check(inside.encloses(r.zone_rect), "%s: zone_rect %s runs off the world map" % [r.id, r.zone_rect])
		for m in TDWorldMapWindow.placed_in(r.id):
			check(r.zone_rect.grow(-8).has_point(m.world_pos), "%s: %s at %s is not inside its region's zone_rect %s" % [r.id, m.id, m.world_pos, r.zone_rect])

func test_one_crossing_between_neighbouring_regions() -> void:
	for route in WorldRoutes.routes():
		if route.by == "Walk":
			check_eq(route.crossings.size(), 1, "%s - %s: crossings %s; neighbouring regions share one" % [route.a, route.b, route.crossings])

func test_every_region_is_on_a_route() -> void:
	var start: MapDef = Content.maps[Character.START_MAP]
	var reached := {start.region: true}
	var todo: Array = [start.region]
	while not todo.is_empty():
		var at: StringName = todo.pop_back()
		for route in WorldRoutes.routes_of(at):
			var next := WorldRoutes.other_end(route, at)
			if not reached.has(next):
				reached[next] = true
				todo.append(next)
	for r: RegionDef in Content.regions.values():
		check(reached.has(r.id), "%s can't be reached by the major routes from %s" % [r.id, start.region])

func test_shortcuts_are_not_routes() -> void:
	# coaches run between regions you can already walk between
	for route in WorldRoutes.routes():
		check(route.by in ["Walk", "Ship"], "%s - %s: a %s route; only walking and ships join regions" % [route.a, route.b, route.by])

func test_every_map_can_be_walked_to_from_its_city() -> void:
	for r: RegionDef in Content.regions.values():
		var reached := {r.capital: true}
		var todo: Array = [r.capital]
		while not todo.is_empty():
			var at: StringName = todo.pop_back()
			for next in WorldRoutes.linked(at):
				var m: MapDef = Content.maps.get(next)
				if m and m.region == r.id and not reached.has(next):
					reached[next] = true
					todo.append(next)
		for m in TDWorldMapWindow.placed_in(r.id):
			check(reached.has(m.id), "%s: %s can't be walked to from %s inside the region" % [r.id, Scan.where(m), r.capital])

func test_links_join_outdoor_maps_once() -> void:
	var seen := {}
	for pair in WorldRoutes.links():
		var key := "%s|%s" % pair
		check(not seen.has(key), "link %s listed twice" % key)
		seen[key] = true
		check(String(pair[0]) < String(pair[1]), "link %s is not in order" % key)
		for id in pair:
			check(not Content.maps[id].interior, "link %s includes the room %s" % [key, id])
