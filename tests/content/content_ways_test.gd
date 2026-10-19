extends TestCase
## Ways between rooms, the Hollow Knight way (Cory, 2026-10-19; RoomExits): in a zone drawn to
## shape you walk off a room's side into the next room, jump up through a top way or drop
## through a bottom one. Each way has a way back at the facing side of the next room, a side
## way's ledge runs right to the edge so you can walk off it, and the two ends of a side way
## stand at the same height on the zone map, so you come out where you went in.

const Scan := preload("res://tests/content/content_scan.gd")

## How far apart (game pixels, on the zone map) the two ends of a side way may stand: less
## than a jump, so you come out about where you went in.
const LINE_UP := 100.0

## Every way out of every map, as [map, portal, side].
func _ways() -> Array:
	var out := []
	for m: MapDef in Content.maps.values():
		for p in m.portals:
			var side := RoomExits.side_of(m, p)
			if side != RoomExits.Side.NONE:
				out.append([m, p, side])
	return out

func test_every_shaped_field_leaves_through_ways() -> void:
	check(_ways().size() > 100, "the shaped zones' fields have their ways (%d)" % _ways().size())

func test_every_way_has_a_way_back() -> void:
	for w in _ways():
		var m: MapDef = w[0]
		var p: PortalDef = w[1]
		var r: RegionDef = Content.regions.get(Content.maps[p.target_map].region)
		if p.one_way or not r.shaped_zone:
			continue # a way into a zone not rebuilt yet comes out at its portal
		check(RoomExits.way_back(m, p) != null, "%s: the way to %s (%s) has no way back through the facing side" % [Scan.where(m), p.target_map, RoomExits.Side.keys()[w[2]]])

func test_side_ways_run_to_the_edge() -> void:
	for w in _ways():
		var m: MapDef = w[0]
		var p: PortalDef = w[1]
		if w[2] != RoomExits.Side.LEFT and w[2] != RoomExits.Side.RIGHT or p.platform == 0:
			continue
		var d := m.platforms[p.platform - 1]
		if w[2] == RoomExits.Side.LEFT:
			check(d.x <= RoomExits.LEDGE_SHORT, "%s: the way to %s leaves from platform %d, which stops %d px short of the left edge" % [Scan.where(m), p.target_map, p.platform, d.x])
		else:
			check(d.x + d.width >= m.width - RoomExits.LEDGE_SHORT, "%s: the way to %s leaves from platform %d, which stops %d px short of the right edge" % [Scan.where(m), p.target_map, p.platform, m.width - d.x - d.width])

func test_side_ways_line_up() -> void:
	for w in _ways():
		var m: MapDef = w[0]
		var p: PortalDef = w[1]
		if w[2] != RoomExits.Side.LEFT and w[2] != RoomExits.Side.RIGHT:
			continue
		var to: MapDef = Content.maps[p.target_map]
		if m.town or to.town or to.region != m.region or RoomExits.touching(m, to) == RoomExits.Side.NONE:
			continue # a town, or a path into the next zone: not on one zone map
		var back := RoomExits.way_back(m, p)
		if back == null:
			continue
		var here := m.zone_pos.y + m.surface_y(p.platform)
		var there := to.zone_pos.y + to.surface_y(back.platform)
		check(absf(here - there) <= LINE_UP, "%s: the way to %s stands %d px from its other end on the zone map" % [Scan.where(m), to.id, absf(here - there)])

func test_side_ways_on_one_side_keep_apart() -> void:
	for m: MapDef in Content.maps.values():
		var layout := MapLayout.new(m)
		var ways: Array = layout.ways.keys()
		for i in ways.size():
			for k in range(i + 1, ways.size()):
				var a: PortalDef = ways[i]
				var b: PortalDef = ways[k]
				var side := layout.side_of(a)
				if side != layout.side_of(b) or not side in [RoomExits.Side.LEFT, RoomExits.Side.RIGHT]:
					continue
				var gap := absf(layout.platforms[a.platform].y - layout.platforms[b.platform].y)
				check(gap > RoomExits.OPENING, "%s: the ways to %s and %s share an opening (%d px apart)" % [Scan.where(m), a.target_map, b.target_map, gap])
