extends TestCase
## The world's shape (Cory, 2026-10-11): each region (major zone) has a main city in it; two
## neighbouring regions are joined by exactly one crossing on foot; a region you can't walk to
## is reached by ship; every map of a region can be walked to from its city without leaving the
## region; and each region's zone map (its part of the world map) shows all of its maps. A
## zone drawn to shape (Cory, 2026-10-16) fits its maps together like rooms: none overlap, and
## every portal between two of them joins rooms that touch, standing by the edge they share.

const Scan := preload("res://tests/content/content_scan.gd")

## How far (game pixels) a portal between rooms may stand from the side edge it leads through,
## and how far along a top or bottom edge from where it leads through.
const SIDE_DOOR_REACH := 300.0
const FLOOR_DOOR_REACH := 100.0

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

func test_shaped_zones_fit_their_maps_together() -> void:
	for r: RegionDef in Content.regions.values():
		if not r.shaped_zone:
			continue
		var rooms := TDWorldMapWindow.placed_in(r.id)
		for i in rooms.size():
			for k in range(i + 1, rooms.size()):
				check(not rooms[i].zone_rect().intersects(rooms[k].zone_rect()), "%s: %s and %s overlap on the zone map" % [r.id, rooms[i].id, rooms[k].id])
		for m in rooms:
			for i in m.portals.size():
				var p := m.portals[i]
				var to: MapDef = Content.maps.get(p.target_map)
				if to == null or to.region != r.id or to.world_pos == Vector2.ZERO or p.one_way or p.after_boss:
					continue
				var at := m.zone_pos + Vector2(p.x, m.surface_y(p.platform))
				var edge := TDWorldMapWindow.door_edge(m, to, at - m.zone_pos)
				if not check(not edge.is_empty(), "%s: portals[%d] leads to %s, whose room doesn't touch this one" % [Scan.where(m), i, to.id]):
					continue
				var dir: Vector2 = edge[1]
				var off := at.distance_to(edge[0]) if dir.y == 0.0 else absf(at.x - edge[0].x)
				var most := SIDE_DOOR_REACH if dir.y == 0.0 else FLOOR_DOOR_REACH
				check(off <= most, "%s: portals[%d] to %s stands %d px from the edge it leads through (want %d at most)" % [Scan.where(m), i, to.id, off, most])
