extends TestCase
## Everywhere on a map can be walked to: every platform, rope, portal, NPC and monster
## spawn is reachable with the hero's own jump (see map_reach.gd) from where players
## arrive; land-shaped art is a real platform, never background scenery; and no two exits
## of a map lead to the same place.

const Scan := preload("res://tests/content/content_scan.gd")
const MapReach := preload("res://tests/content/map_reach.gd")

func test_everything_on_every_map_can_be_reached() -> void:
	for m: MapDef in Content.maps.values():
		var w := Scan.where(m)
		var reach := MapReach.new(m, MapReach.arrivals_of(m))
		for i in m.platforms.size():
			var p := m.platforms[i]
			check(reach.platform_reached(i + 1), "%s: platforms[%d] (x %d-%d, y %d) can't be reached" % [w, i, p.x, p.x + p.width, p.y])
		for i in m.climbables.size():
			var c := m.climbables[i]
			check(reach.climbable_reached(i), "%s: climbables[%d] (x %d, y %d-%d) can't be reached" % [w, i, c.x, c.top, c.bottom])
		for i in m.portals.size():
			check(reach.platform_reached(m.portals[i].platform), "%s: portals[%d] to %s can't be reached" % [w, i, m.portals[i].target_map])
		for i in m.npcs.size():
			check(reach.platform_reached(m.npcs[i].platform), "%s: npcs[%d] can't be reached" % [w, i])
		for i in m.spawns.size():
			check(reach.platform_reached(m.spawns[i].platform), "%s: spawns[%d] can't be reached" % [w, i])

func test_land_art_is_never_scenery() -> void:
	var land := {}
	for m: MapDef in Content.maps.values():
		for p in m.platforms:
			if p.look:
				land[p.look.resource_path] = true
	check(land.size() > 0, "no platform has a look")
	for m: MapDef in Content.maps.values():
		for i in m.props.size():
			var p := m.props[i]
			if p.texture:
				check(not land.has(p.texture.resource_path), "%s: props[%d] is land art (%s); make it a platform with that look" % [Scan.where(m), i, p.texture.resource_path.get_file()])

func test_no_two_exits_lead_to_the_same_map() -> void:
	for m: MapDef in Content.maps.values():
		var seen := {}
		for i in m.portals.size():
			var to := m.portals[i].target_map
			check(not seen.has(to), "%s: portals[%d] and portals[%s] both lead to %s" % [Scan.where(m), i, seen.get(to), to])
			seen[to] = i
